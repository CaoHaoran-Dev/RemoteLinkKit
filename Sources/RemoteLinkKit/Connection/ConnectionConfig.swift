//
//  ConnectionConfig.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 连接配置
public struct ConnectionConfig: Sendable {
    public enum Scheme: String, Sendable {
        case ws
        case wss
    }

    public var host: String
    /// WebSocket 端口
    public var port: Int
    /// HTTP 配对端口。nil 表示与 port 相同（单端口部署）
    public var pairingPort: Int?
    public var scheme: Scheme
    public var connectTimeout: TimeInterval
    public var path: String

    public init(host: String,
                port: Int,
                pairingPort: Int? = nil,
                scheme: Scheme = .ws,
                connectTimeout: TimeInterval = 10,
                path: String = "/ws") {
        self.host = host
        self.port = port
        self.pairingPort = pairingPort
        self.scheme = scheme
        self.connectTimeout = connectTimeout
        self.path = path
    }

    // MARK: - URLs

    /// WebSocket 连接 URL
    public var url: URL? {
        URL(string: "\(scheme.rawValue)://\(host):\(port)\(path)")
    }

    /// HTTP 配对 base URL。未单独指定 pairingPort 时退回 port
    public var pairingBaseURL: URL? {
        let httpScheme = (scheme == .wss) ? "https" : "http"
        let p = pairingPort ?? port
        return URL(string: "\(httpScheme)://\(host):\(p)")
    }

    /// 配对端点 URL
    public func pairingURL(path: String) -> URL? {
        pairingBaseURL?.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
    }
}
