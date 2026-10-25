//
//  ConnectionError.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

public enum ConnectionError: Error, LocalizedError {
    case invalidURL
    case notConnected
    case sendFailed(underlying: Error)
    case receiveFailed(underlying: Error)
    case timeout
    case closed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:              return "Invalid connection URL."
        case .notConnected:            return "Connection is not established."
        case .sendFailed(let e):       return "Send failed: \(e.localizedDescription)"
        case .receiveFailed(let e):    return "Receive failed: \(e.localizedDescription)"
        case .timeout:                 return "Connection timed out."
        case .closed:                  return "Connection closed."
        }
    }
}
