//
//  CipherSuite.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 加密套件协议
public protocol CipherSuite: Sendable {
    static var identifier: String { get }
    static var cipherId: UInt16 { get }
    static var keyLength: Int { get }

    func seal(_ plaintext: Data, nonce: Data, aad: Data) throws -> Data
    func open(_ ciphertext: Data, nonce: Data, aad: Data) throws -> Data
}

/// 加密套件注册表
public enum CipherRegistry {
    private static let lock = NSLock()
    private static var table: [UInt16: String] = [
        AESGCMCipher.cipherId: AESGCMCipher.identifier,
        ChaChaPolyCipher.cipherId: ChaChaPolyCipher.identifier
    ]

    public static func identifier(for id: UInt16) -> String? {
        lock.withLock { table[id] }
    }

    public static func registered() -> [UInt16: String] {
        lock.withLock { table }
    }
}
