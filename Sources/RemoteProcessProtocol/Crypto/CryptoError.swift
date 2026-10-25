//
//  CryptoError.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

public enum CryptoError: Error, LocalizedError {
    case unsupportedCipher(String)
    case invalidKeyLength(expected: Int, actual: Int)
    case sealFailed(underlying: Error)
    case openFailed(underlying: Error)
    case invalidNonceLength(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedCipher(let id):
            return "Unsupported cipher: \(id)"
        case .invalidKeyLength(let e, let a):
            return "Invalid key length: expected \(e), got \(a)"
        case .sealFailed(let e):
            return "Encryption failed: \(e.localizedDescription)"
        case .openFailed(let e):
            return "Decryption failed: \(e.localizedDescription)"
        case .invalidNonceLength(let e, let a):
            return "Invalid nonce length: expected \(e), got \(a)"
        }
    }
}
