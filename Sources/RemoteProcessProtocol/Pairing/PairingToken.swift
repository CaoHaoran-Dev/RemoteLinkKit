//
//  PairingToken.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
import CryptoKit

/// 长期配对 token
///
/// 服务端只存 `hash`，客户端存明文（Keychain）。
public struct PairingToken: Codable, Sendable {
    public let rawValue: String
    public let issuedAt: Date
    public let deviceName: String?

    public init(rawValue: String, issuedAt: Date = Date(), deviceName: String? = nil) {
        self.rawValue = rawValue
        self.issuedAt = issuedAt
        self.deviceName = deviceName
    }

    /// 生成新 token（32 字节随机，hex 编码）
    public static func generate(deviceName: String? = nil) -> PairingToken {
        let bytes = KeyDerivation.randomBytes(32)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return PairingToken(rawValue: hex, deviceName: deviceName)
    }

    /// 计算哈希（服务端存储用）
    public func hash() -> String {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 校验明文 token 是否匹配存储的 hash
    public static func verify(rawValue: String, againstHash hash: String) -> Bool {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        let computed = digest.map { String(format: "%02x", $0) }.joined()
        return computed == hash
    }
}

/// 服务端已配对设备记录
public struct PairedDevice: Codable, Sendable, Identifiable {
    public let id: String
    public let tokenHash: String
    public let deviceName: String?
    public let pairedAt: Date
    public var lastSeenAt: Date?

    public init(id: String = UUID().uuidString,
                tokenHash: String,
                deviceName: String?,
                pairedAt: Date = Date(),
                lastSeenAt: Date? = nil) {
        self.id = id
        self.tokenHash = tokenHash
        self.deviceName = deviceName
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
    }
}
