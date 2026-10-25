//
//  Frame.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 帧结构
///
/// 线上格式（12 字节头 + payload）：
/// ```
/// [version:1][type:1][cipherId:2][seq:4][length:4][payload:length]
/// ```
/// `payload` 是加密后的消息 JSON。
public struct Frame: Sendable, Equatable {
    public static let currentVersion: UInt8 = 1
    public static let headerSize = 12
    public static let maxPayloadSize = 16 * 1024 * 1024

    public let version: UInt8
    public let type: FrameType
    public let cipherId: UInt16
    public let seq: UInt32
    public let payload: Data

    public init(version: UInt8 = Frame.currentVersion,
                type: FrameType,
                cipherId: UInt16,
                seq: UInt32,
                payload: Data) {
        self.version = version
        self.type = type
        self.cipherId = cipherId
        self.seq = seq
        self.payload = payload
    }

    /// 帧头的 AAD（用于加密认证）
    ///
    /// 只含 `version + type + cipherId + seq`，不含 `length`。
    /// `length` 被篡改会导致帧切片错误，payload 解不出来，GCM 解密必然失败，
    /// 所以不含 length 与含 length 在安全性上等价。
    public var headerAAD: Data {
        var d = Data()
        d.append(version)
        d.append(type.rawValue)
        d.append(UInt8(cipherId >> 8))
        d.append(UInt8(cipherId & 0xFF))
        d.append(UInt8((seq >> 24) & 0xFF))
        d.append(UInt8((seq >> 16) & 0xFF))
        d.append(UInt8((seq >> 8) & 0xFF))
        d.append(UInt8(seq & 0xFF))
        return d
    }
}
