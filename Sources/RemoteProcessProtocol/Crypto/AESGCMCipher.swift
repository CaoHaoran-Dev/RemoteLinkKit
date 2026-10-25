//
//  AESGCMCipher.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
import CryptoKit

public struct AESGCMCipher: CipherSuite {
    public static let identifier = "AES-256-GCM"
    public static let cipherId: UInt16 = 0x0001
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
            let box = try AES.GCM.seal(
                plaintext,
                using: key,
                nonce: AES.GCM.Nonce(data: nonce),
                authenticating: aad
            )
            guard let combined = box.combined else {
                throw CryptoError.sealFailed(underlying: NSError(domain: "AESGCM", code: -1))
            }
            return combined
        } catch let e as CryptoError {
            throw e
        } catch {
            throw CryptoError.sealFailed(underlying: error)
        }
    }

    public func open(_ ciphertext: Data, nonce: Data, aad: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw CryptoError.openFailed(underlying: error)
        }
    }
}
