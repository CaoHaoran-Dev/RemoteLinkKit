//
//  MessageCodec.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 消息编解码
public enum MessageCodec {

    public static func encode(_ message: ClientMessage) throws -> Data {
        do {
            return try JSONEncoder().encode(message)
        } catch {
            throw MessageError.encodeFailed(underlying: error)
        }
    }

    public static func encode(_ message: ServerMessage) throws -> Data {
        do {
            return try JSONEncoder().encode(message)
        } catch {
            throw MessageError.encodeFailed(underlying: error)
        }
    }

    public static func decodeClient(_ data: Data) throws -> ClientMessage {
        do {
            return try JSONDecoder().decode(ClientMessage.self, from: data)
        } catch {
            throw MessageError.decodeFailed(underlying: error)
        }
    }

    public static func decodeServer(_ data: Data) throws -> ServerMessage {
        do {
            return try JSONDecoder().decode(ServerMessage.self, from: data)
        } catch {
            throw MessageError.decodeFailed(underlying: error)
        }
    }
}
