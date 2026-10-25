//
//  ChaChaPolyCipher.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
import CryptoKit

public struct ChaChaPolyCipher: CipherSuite {
    public static let identifier = "ChaCha20-Poly1305"
    public static let cipherId: UInt16 = 0x0002
    public static let keyLength = 32

    private let key: SymmetricKey

    public init(key: Data) throws {
        guard key.count == Self.keyLength else {
            throw CryptoError.invalidKeyLength(expected: Self.keyLength, actual: key.count)
        }
        self.key = SymmetricKey(data: key)
    }

    public func seal(_ plaintext: Data, nonce: Data, aad: Data) throws -> Data {
        guard nonce.count == 12 else {
            throw CryptoError.invalidNonceLength(expected: 12, actual: nonce.count)
        }
        do {
            let box = try ChaChaPoly.seal(
                plaintext,
                using: key,
                nonce: ChaChaPoly.Nonce(data: nonce),
                authenticating: aad
            )
            return box.combined
        } catch {
            throw CryptoError.sealFailed(underlying: error)
        }
    }

    public func open(_ ciphertext: Data, nonce: Data, aad: Data) throws -> Data {
        do {
            let box = try ChaChaPoly.SealedBox(combined: ciphertext)
            return try ChaChaPoly.open(box, using: key, authenticating: aad)
        } catch {
            throw CryptoError.openFailed(underlying: error)
        }
    }
}
