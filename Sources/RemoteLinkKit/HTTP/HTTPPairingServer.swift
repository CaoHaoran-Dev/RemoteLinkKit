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
/// TODO: 实现解析和分发
public final class HTTPPairingServer: @unchecked Sendable {
    public struct Request: Sendable {
        public let method: String
        public let path: String
        public let headers: [String: String]
        public let body: Data
    }

    public typealias Handler = @Sendable (Request) -> (status: Int, body: Data)

    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }
}
#endif
