//
//  KeyDerivation.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
import CryptoKit
import Security

/// 密钥派生工具
public enum KeyDerivation {

    /// HKDF 派生 32 字节对称密钥
    public static func deriveKey(sharedSecret: Data,
                                 salt: Data,
                                 info: Data,
                                 length: Int = 32) -> Data {
        let ikm = SymmetricKey(data: sharedSecret)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: info,
            outputByteCount: length
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    /// 从 seq 派生 12 字节 nonce
    public static func nonce(from seq: UInt32) -> Data {
        var d = Data(count: 12)
        d[0] = UInt8((seq >> 24) & 0xFF)
        d[1] = UInt8((seq >> 16) & 0xFF)
        d[2] = UInt8((seq >> 8) & 0xFF)
        d[3] = UInt8(seq & 0xFF)
        return d
    }

    /// 生成随机 32 字节
    public static func randomBytes(_ count: Int = 32) -> Data {
        var d = Data(count: count)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return d
    }
}
