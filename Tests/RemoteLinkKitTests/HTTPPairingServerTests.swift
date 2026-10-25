//
//  HTTPPairingServerTests.swift
//  RemoteLinkKitTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteLinkKit

#if canImport(Network)
import Network

final class HTTPPairingServerTests: XCTestCase {

    // MARK: - Parse Tests

    func testParseSimpleGET() {
        let raw = "GET /pair/hello HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)
        let parsed = parse(data)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.request.method, "GET")
        XCTAssertEqual(parsed?.request.path, "/pair/hello")
        XCTAssertEqual(parsed?.request.headers["host"], "localhost")
        XCTAssertEqual(parsed?.request.body, Data())
    }

    func testParsePOSTWithBody() {
        let body = Data("{\"proof\":\"abc\"}".utf8)
        var raw = "POST /pair/verify HTTP/1.1\r\n"
        raw += "Host: localhost\r\n"
        raw += "Content-Length: \(body.count)\r\n"
        raw += "\r\n"

        var data = Data(raw.utf8)
        data.append(body)

        let parsed = parse(data)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.request.method, "POST")
        XCTAssertEqual(parsed?.request.path, "/pair/verify")
        XCTAssertEqual(parsed?.request.body, body)
    }

    func testParseIncompleteReturnsNil() {
        let raw = "GET /pair/hello HTTP/1.1\r\nHost: local"
        XCTAssertNil(parse(Data(raw.utf8)))
    }

    func testParseIncompleteBodyReturnsNil() {
        var raw = "POST /pair/verify HTTP/1.1\r\n"
        raw += "Content-Length: 10\r\n\r\n"
        raw += "abc"  // 只有 3 字节

        XCTAssertNil(parse(Data(raw.utf8)))
    }

    func testParseHeaderCaseInsensitive() {
        let raw = "GET /x HTTP/1.1\r\nContent-Length: 0\r\nX-Custom: yes\r\n\r\n"
        let parsed = parse(Data(raw.utf8))
        XCTAssertEqual(parsed?.request.headers["x-custom"], "yes")
    }

    // MARK: - Helper
    //
    // 这里我们不启动真实 NWListener，只测解析逻辑。
    // tryParseRequest 是 private，所以通过一个最小的公开访问路径：
    // 通过真实 listener 端到端测（见 HTTPPairingServerE2ETests）。
    // 这里用一个反射式的包装——把解析逻辑抄成纯函数测试。
    //
    // 注意：如果后续把 tryParseRequest 改为 internal，可以直接测。

    private struct Parsed {
        let request: HTTPPairingServer.Request
        let consumed: Int
    }

    private func parse(_ data: Data) -> Parsed? {
        // 和 HTTPPairingServer.tryParseRequest 完全相同的逻辑
        let headerEnd = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let headerRange = data.range(of: headerEnd) else { return nil }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + contentLength
        guard data.count >= bodyEnd else { return nil }

        let body = data[bodyStart..<bodyEnd]
        let req = HTTPPairingServer.Request(
            method: method, path: path, headers: headers, body: Data(body)
        )
        return Parsed(request: req, consumed: bodyEnd)
    }
}
#endif
