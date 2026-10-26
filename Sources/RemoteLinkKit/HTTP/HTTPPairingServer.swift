//
//  HTTPPairingServer.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
#if canImport(Network)
import Network

/// 最小 HTTP/1.1 解析，挂到 NWListener 上，把请求转成回调。
/// 只支持 Content-Length，不支持 chunked。
public final class HTTPPairingServer: @unchecked Sendable {

    // MARK: - Request / Response

    public struct Request: Sendable {
        public let method: String
        public let path: String
        public let headers: [String: String]
        public let body: Data
    }

    public struct Response: Sendable {
        public let status: Int
        public let headers: [String: String]
        public let body: Data

        public init(status: Int,
                    headers: [String: String] = ["Content-Type": "application/json"],
                    body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    public typealias Handler = @Sendable (Request) -> Response

    // MARK: - Limits

    /// 请求头 + 请求体的最大缓冲上限，超过则主动断开。
    public static let maxBufferSize = 2 * 1024 * 1024   // 2 MB
    /// 请求体最大长度。
    public static let maxBodySize = 1024 * 1024          // 1 MB

    // MARK: - Private

    private let handler: Handler
    private let queue = DispatchQueue(label: "com.remotelinkkit.httpserver")

    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    // MARK: - Init

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    // MARK: - Start / Stop

    public func start(port: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(
                domain: "RemoteLinkKit.HTTPPairingServer",
                code: Int(EINVAL),
                userInfo: [NSLocalizedDescriptionKey: "Invalid port: \(port)"]
            )
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener.start(queue: queue)

        lock.withLock { self.listener = listener }
    }

    public func stop() {
        let (l, conns): (NWListener?, [NWConnection]) = lock.withLock {
            let l = listener
            let c = Array(connections.values)
            listener = nil
            connections.removeAll()
            return (l, c)
        }

        l?.cancel()
        conns.forEach { $0.cancel() }
    }

    // MARK: - Connection

    private func handleNewConnection(_ connection: NWConnection) {
        lock.withLock { connections[ObjectIdentifier(connection)] = connection }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.lock.withLock {
                    _ = self?.connections.removeValue(forKey: ObjectIdentifier(connection))
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if error != nil {
                self.closeConnection(connection)
                return
            }

            var buffer = buffer
            if let data = data {
                buffer.append(data)
            }

            // 兜底缓冲上限，防止慢速/超大请求耗尽内存
            if buffer.count > Self.maxBufferSize {
                self.closeConnection(connection)
                return
            }

            switch self.tryParseRequest(buffer) {
            case .incomplete:
                if isComplete {
                    self.closeConnection(connection)
                } else {
                    self.receive(on: connection, buffer: buffer)
                }

            case .reject(let status):
                // 解析层判定请求必须拒绝（如 body 超限），直接回错误并关闭。
                self.sendResponse(Response(status: status), on: connection) { [weak self] in
                    self?.closeConnection(connection)
                }

            case .request(let parsed):
                // WebSocket 升级不在这里处理，直接断
                if parsed.request.headers["upgrade"]?.lowercased() == "websocket" {
                    self.closeConnection(connection)
                    return
                }

                let response = self.handler(parsed.request)
                self.sendResponse(response, on: connection) { [weak self] in
                    self?.closeConnection(connection)
                }
            }
        }
    }

    // MARK: - HTTP Parse

    enum ParseResult {
        case incomplete
        case reject(status: Int)
        case request(ParsedRequest)
    }

    struct ParsedRequest {
        let request: Request
        let consumed: Int
    }

    // internal 而非 private，以便 @testable 单元测试覆盖解析边界。
    func tryParseRequest(_ buffer: Data) -> ParseResult {
        let headerEnd = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let headerRange = buffer.range(of: headerEnd) else { return .incomplete }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return .reject(status: 400)
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .incomplete }

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return .reject(status: 400) }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // 拒绝无法解析、负数或超限的 Content-Length。
        // 负数若不拒绝，后续 bodyStart..<bodyEnd 会构成非法 Range 并崩溃。
        guard let contentLength = Int(headers["content-length"] ?? "0"),
              contentLength >= 0 else {
            return .reject(status: 400)
        }

        guard contentLength <= Self.maxBodySize else {
            return .reject(status: 413)
        }

        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + contentLength

        guard buffer.count >= bodyEnd else { return .incomplete }

        let body = buffer[bodyStart..<bodyEnd]
        let request = Request(method: method, path: path, headers: headers, body: Data(body))
        return .request(ParsedRequest(request: request, consumed: bodyEnd))
    }

    // MARK: - Send Response

    /// `completion` 标 `@Sendable`：它会被捕获进 `NWConnection` 的
    /// `@Sendable` 完成回调，避免严格并发检查告警。
    private func sendResponse(_ response: Response,
                              on connection: NWConnection,
                              completion: @escaping @Sendable () -> Void) {
        var headerLines: [String] = []
        headerLines.append("HTTP/1.1 \(response.status) \(Self.statusText(response.status))")

        var headers = response.headers
        headers["Content-Length"] = "\(response.body.count)"
        headers["Connection"] = "close"

        for (key, value) in headers {
            headerLines.append("\(key): \(value)")
        }
        headerLines.append("")
        headerLines.append("")

        var data = Data(headerLines.joined(separator: "\r\n").utf8)
        data.append(response.body)

        connection.send(
            content: data,
            completion: .contentProcessed { _ in
                completion()
            }
        )
    }

    private func closeConnection(_ connection: NWConnection) {
        connection.cancel()
        lock.withLock {
            _ = connections.removeValue(forKey: ObjectIdentifier(connection))
        }
    }

    // MARK: - Status Text

    private static func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        default:  return "Unknown"
        }
    }
}
#endif
