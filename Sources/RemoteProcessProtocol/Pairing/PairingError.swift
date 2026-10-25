//
//  PairingError.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

public enum PairingError: Error, LocalizedError {
    case invalidCode
    case codeExpired
    case tooManyAttempts
    case proofMismatch
    case tokenInvalid
    case tokenRevoked

    public var errorDescription: String? {
        switch self {
        case .invalidCode:      return "Invalid pairing code."
        case .codeExpired:      return "Pairing code expired."
        case .tooManyAttempts:  return "Too many failed attempts."
        case .proofMismatch:    return "Pairing proof mismatch."
        case .tokenInvalid:     return "Token is invalid."
        case .tokenRevoked:     return "Token has been revoked."
        }
    }
}
