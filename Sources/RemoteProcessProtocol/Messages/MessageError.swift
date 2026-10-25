//
//  MessageError.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

public enum MessageError: Error, LocalizedError {
    case encodeFailed(underlying: Error)
    case decodeFailed(underlying: Error)
    case unknownType(String)
    case mismatchedFrameType(expected: FrameType, actual: FrameType)

    public var errorDescription: String? {
        switch self {
        case .encodeFailed(let e):  return "Message encode failed: \(e.localizedDescription)"
        case .decodeFailed(let e):  return "Message decode failed: \(e.localizedDescription)"
        case .unknownType(let t):   return "Unknown message type: \(t)"
        case .mismatchedFrameType(let e, let a):
            return "Mismatched frame type: expected \(e), got \(a)"
        }
    }
}
