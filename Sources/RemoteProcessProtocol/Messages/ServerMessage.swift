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
        }
    }
}

extension ServerMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, stream, data, exit, cwd, message, timestamp, path
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .output(let id, let stream, let data):
            try c.encode("output", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(stream.rawValue, forKey: .stream)
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
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "output":
            let raw = try c.decode(String.self, forKey: .stream)
            guard let stream = Stream(rawValue: raw) else {
                throw MessageError.unknownType(raw)
            }
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
        default:
            throw MessageError.unknownType(type)
        }
    }
}
