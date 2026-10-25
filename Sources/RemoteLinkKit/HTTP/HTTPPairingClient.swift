//
//  HTTPPairingClient.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 客户端配对请求发送。只负责发和拿原始 Data，不解析业务。
public struct HTTPPairingClient: Sendable {

    public let config: ConnectionConfig
    private let session: URLSession

    public init(config: ConnectionConfig,
                session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Pairing Endpoints

    /// GET /pair/hello
    public func hello() async throws -> Data {
        guard let url = config.pairingURL(path: "/pair/hello") else {
            throw ConnectionError.invalidURL
        }
        return try await get(url)
    }

    /// POST /pair/verify
    public func verify(body: Data) async throws -> Data {
        guard let url = config.pairingURL(path: "/pair/verify") else {
            throw ConnectionError.invalidURL
        }
        return try await post(url, body: body)
    }

    // MARK: - Generic

    public func get(_ url: URL,
                    headers: [String: String] = [:]) async throws -> Data {
        try await request(url, method: "GET", headers: headers, body: nil)
    }

    public func post(_ url: URL,
                     headers: [String: String] = [:],
                     body: Data) async throws -> Data {
        try await request(url, method: "POST", headers: headers, body: body)
    }

    // MARK: - Request

    private func request(_ url: URL,
                         method: String,
                         headers: [String: String],
                         body: Data?) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = config.connectTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        req.httpBody = body

        do {
            let (data, response) = try await session.data(for: req)

            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw ConnectionError.sendFailed(
                    underlying: NSError(
                        domain: "RemoteLinkKit.HTTPPairing",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
                    )
                )
            }
            return data
        } catch let e as ConnectionError {
            throw e
        } catch {
            throw ConnectionError.sendFailed(underlying: error)
        }
    }
}
