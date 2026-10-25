//
//  ClientMessage.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 客户端 → 服务端
public enum ClientMessage: Sendable, Equatable {
    case exec(id: String, cmd: String, timeout: TimeInterval)
    case cancel(id: String)
    case ping(timestamp: Date)

    public var frameType: FrameType {
        switch self {
        case .exec:   return .exec
        case .cancel: return .cancel
        case .ping:   return .ping
        }
    }
}

extension ClientMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, cmd, timeout, timestamp
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .exec(let id, let cmd, let timeout):
            try c.encode("exec", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(cmd, forKey: .cmd)
            try c.encode(timeout, forKey: .timeout)
        case .cancel(let id):
            try c.encode("cancel", forKey: .type)
            try c.encode(id, forKey: .id)
        case .ping(let ts):
            try c.encode("ping", forKey: .type)
            try c.encode(ts.timeIntervalSince1970, forKey: .timestamp)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "exec":
            self = .exec(
                id: try c.decode(String.self, forKey: .id),
                cmd: try c.decode(String.self, forKey: .cmd),
                timeout: try c.decode(TimeInterval.self, forKey: .timeout)
            )
        case "cancel":
            self = .cancel(id: try c.decode(String.self, forKey: .id))
        case "ping":
            let ts = try c.decode(TimeInterval.self, forKey: .timestamp)
            self = .ping(timestamp: Date(timeIntervalSince1970: ts))
        default:
            throw MessageError.unknownType(type)
        }
    }
}
