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
    public var port: Int
    public var scheme: Scheme
    public var connectTimeout: TimeInterval
    public var path: String

    public init(host: String,
                port: Int,
                scheme: Scheme = .ws,
                connectTimeout: TimeInterval = 10,
                path: String = "/ws") {
        self.host = host
        self.port = port
        self.scheme = scheme
        self.connectTimeout = connectTimeout
        self.path = path
    }

    public var url: URL? {
        URL(string: "\(scheme.rawValue)://\(host):\(port)\(path)")
    }
}
