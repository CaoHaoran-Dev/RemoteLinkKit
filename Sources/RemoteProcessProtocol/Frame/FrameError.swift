//
//  FrameError.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

public enum FrameError: Error, LocalizedError {
    case invalidVersion(UInt8)
    case invalidType(UInt8)
    case truncatedHeader(expected: Int, actual: Int)
    case truncatedPayload(expected: Int, actual: Int)
    case payloadTooLarge(Int)
    case sequenceReplayed(UInt32)

    public var errorDescription: String? {
        switch self {
        case .invalidVersion(let v):
            return "Unsupported frame version: \(v)"
        case .invalidType(let t):
            return "Unknown frame type: \(t)"
        case .truncatedHeader(let e, let a):
            return "Truncated frame header: expected \(e), got \(a)"
        case .truncatedPayload(let e, let a):
            return "Truncated frame payload: expected \(e), got \(a)"
        case .payloadTooLarge(let size):
            return "Frame payload too large: \(size) bytes"
        case .sequenceReplayed(let seq):
            return "Replayed or out-of-order sequence: \(seq)"
        }
    }
}
