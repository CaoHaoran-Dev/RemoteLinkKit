//
//  ServerMessage.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 服务端 → 客户端
public enum ServerMessage: Sendable, Equatable {
    case output(id: String, stream: Stream, data: Data)
    case done(id: String, exit: Int32, cwd: String)
    case error(id: String?, message: String)
    case pong(timestamp: Date)
    case cwd(path: String)
    /// 自定义业务消息。`type` 是业务子类型，`payload` 是序列化后的字节。
    case custom(type: String, payload: Data)

    public enum Stream: String, Codable, Sendable {
        case stdout
        case stderr
    }

    public var frameType: FrameType {
        switch self {
        case .output: return .output
        case .done:   return .done
        case .error:  return .error
        case .pong:   return .pong
        case .cwd:    return .cwd
        // 复用 .handshake（双向帧类型），避免改动 FrameType 枚举。
        case .custom: return .handshake
        }
    }
}

extension ServerMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, stream, data, exit, cwd, message, timestamp, path, payload, customType
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .output(let id, let stream, let data):
            try c.encode("output", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(stream, forKey: .stream)
            try c.encode(data.base64EncodedString(), forKey: .data)
        case .done(let id, let exit, let cwd):
            try c.encode("done", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(exit, forKey: .exit)
            try c.encode(cwd, forKey: .cwd)
        case .error(let id, let message):
            try c.encode("error", forKey: .type)
            try c.encodeIfPresent(id, forKey: .id)
            try c.encode(message, forKey: .message)
        case .pong(let ts):
            try c.encode("pong", forKey: .type)
            try c.encode(ts.timeIntervalSince1970, forKey: .timestamp)
        case .cwd(let path):
            try c.encode("cwd", forKey: .type)
            try c.encode(path, forKey: .path)
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
        case "output":
            let stream = try c.decode(Stream.self, forKey: .stream)
            let b64 = try c.decode(String.self, forKey: .data)
            self = .output(
                id: try c.decode(String.self, forKey: .id),
                stream: stream,
                data: Data(base64Encoded: b64) ?? Data()
            )
        case "done":
            self = .done(
                id: try c.decode(String.self, forKey: .id),
                exit: try c.decode(Int32.self, forKey: .exit),
                cwd: try c.decode(String.self, forKey: .cwd)
            )
        case "error":
            self = .error(
                id: try c.decodeIfPresent(String.self, forKey: .id),
                message: try c.decode(String.self, forKey: .message)
            )
        case "pong":
            let ts = try c.decode(TimeInterval.self, forKey: .timestamp)
            self = .pong(timestamp: Date(timeIntervalSince1970: ts))
        case "cwd":
            self = .cwd(path: try c.decode(String.self, forKey: .path))
        case "custom":
            let subType = try c.decode(String.self, forKey: .customType)
            let b64 = try c.decode(String.self, forKey: .payload)
            self = .custom(type: subType, payload: Data(base64Encoded: b64) ?? Data())
        default:
            throw MessageError.unknownType(type)
        }
    }
}
