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
    /// 自定义业务消息。`type` 是业务子类型，`payload` 是序列化后的字节。
    case custom(type: String, payload: Data)

    public var frameType: FrameType {
        switch self {
        case .exec:   return .exec
        case .cancel: return .cancel
        case .ping:   return .ping
        // 复用 .handshake（双向帧类型），避免改动 FrameType 枚举。
        case .custom: return .handshake
        }
    }
}

extension ClientMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, cmd, timeout, timestamp, payload, customType
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
        case .custom(let subType, let payload):
            try c.encode("custom", forKey: .type)
            try c.encode(subType, forKey: .customType)
            try c.encode(payload.base64EncodedString(), forKey: .payload)
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
        case "custom":
            let subType = try c.decode(String.self, forKey: .customType)
            let b64 = try c.decode(String.self, forKey: .payload)
            self = .custom(type: subType, payload: Data(base64Encoded: b64) ?? Data())
        default:
            throw MessageError.unknownType(type)
        }
    }
}
