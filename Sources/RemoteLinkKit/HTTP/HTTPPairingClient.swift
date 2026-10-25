//
//  HTTPPairingClient.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 客户端配对请求发送。只负责发和拿原始 Data，不解析业务。
public struct HTTPPairingClient: Sendable {
    public init() {}

    public func get(_ url: URL,
                    headers: [String: String] = [:]) async throws -> Data {
        try await request(url, method: "GET", headers: headers, body: nil)
    }

    public func post(_ url: URL,
                     headers: [String: String] = [:],
                     body: Data) async throws -> Data {
        try await request(url, method: "POST", headers: headers, body: body)
    }

    private func request(_ url: URL,
                         method: String,
                         headers: [String: String],
                         body: Data?) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}
