//
//  PairingHandshake.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
import CryptoKit

/// 配对握手模型
public enum PairingHandshake {

    // MARK: - Hello

    public struct HelloResponse: Codable, Sendable {
        public let serverId: String
        public let nonce: String          // hex
        public let supportedCiphers: [UInt16]
        public let serverName: String?

        public init(serverId: String,
                    nonce: String,
                    supportedCiphers: [UInt16],
                    serverName: String? = nil) {
            self.serverId = serverId
            self.nonce = nonce
            self.supportedCiphers = supportedCiphers
            self.serverName = serverName
        }
    }

    // MARK: - Verify

    public struct VerifyRequest: Codable, Sendable {
        public let proof: String          // hex HMAC
        public let cipherId: UInt16
        public let deviceName: String?

        public init(proof: String, cipherId: UInt16, deviceName: String? = nil) {
            self.proof = proof
            self.cipherId = cipherId
            self.deviceName = deviceName
        }
    }

    public struct VerifyResponse: Codable, Sendable {
        public let token: String
        public let serverPublicKey: String?
        public let deviceId: String

        public init(token: String, serverPublicKey: String? = nil, deviceId: String) {
            self.token = token
            self.serverPublicKey = serverPublicKey
            self.deviceId = deviceId
        }
    }

    public struct ErrorResponse: Codable, Sendable {
        public let error: String
        public let retryAfter: Int?

        public init(error: String, retryAfter: Int? = nil) {
            self.error = error
            self.retryAfter = retryAfter
        }
    }

    // MARK: - Proof

    /// 从 6 位码派生配对密钥
    public static func derivePairKey(code: String,
                                     serverId: String,
                                     nonce: Data) -> Data {
        let ikm = Data((code + serverId).utf8)
        return KeyDerivation.deriveKey(sharedSecret: ikm, salt: nonce, info: Data("pair".utf8))
    }

    /// 计算 HMAC proof
    public static func computeProof(pairKey: Data, nonce: Data) -> Data {
        let key = SymmetricKey(data: pairKey)
        let mac = HMAC<SHA256>.authenticationCode(for: nonce, using: key)
        return Data(mac)
    }

    /// 验证 proof
    public static func verifyProof(pairKey: Data, nonce: Data, proof: Data) -> Bool {
        let expected = computeProof(pairKey: pairKey, nonce: nonce)
        return constantTimeEqual(expected, proof)
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }
}
