//
//  SessionKeyContext.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 每次连接的会话密钥上下文
public struct SessionKeyContext: Sendable {
    public let clientNonce: Data
    public let serverNonce: Data
    public let cipherId: UInt16

    public init(clientNonce: Data, serverNonce: Data, cipherId: UInt16) {
        self.clientNonce = clientNonce
        self.serverNonce = serverNonce
        self.cipherId = cipherId
    }

    /// 从长期共享密钥派生会话密钥
    public func deriveSessionKey(sharedSecret: Data) -> Data {
        let salt = clientNonce + serverNonce
        return KeyDerivation.deriveKey(
            sharedSecret: sharedSecret,
            salt: salt,
            info: Data("session".utf8)
        )
    }
}
