//
//  FrameCodec.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 帧编解码器
///
/// 负责把 `Frame` 序列化为字节流，以及从字节缓冲区切出完整帧。
/// 不负责加密，加密由 `CipherSuite` 在封帧前/解帧后处理。
public final class FrameCodec: @unchecked Sendable {

    private let lock = NSLock()
    private var buffer = Data()
    private var nextSeq: UInt32 = 0
    private let cipherId: UInt16

    public init(cipherId: UInt16) {
        self.cipherId = cipherId
    }

    // MARK: - Encode

    /// 把帧编码为字节流
    public func encode(_ frame: Frame) -> Data {
        var d = Data()
        d.append(frame.version)
        d.append(frame.type.rawValue)
        d.append(UInt8(frame.cipherId >> 8))
        d.append(UInt8(frame.cipherId & 0xFF))
        d.append(UInt8((frame.seq >> 24) & 0xFF))
        d.append(UInt8((frame.seq >> 16) & 0xFF))
        d.append(UInt8((frame.seq >> 8) & 0xFF))
        d.append(UInt8(frame.seq & 0xFF))
        d.append(UInt8((frame.payload.count >> 24) & 0xFF))
        d.append(UInt8((frame.payload.count >> 16) & 0xFF))
        d.append(UInt8((frame.payload.count >> 8) & 0xFF))
        d.append(UInt8(frame.payload.count & 0xFF))
        d.append(frame.payload)
        return d
    }

    /// 分配下一个 seq 并编码。
    ///
    /// 注意：`SecureChannel` 自行维护 seq 并直接构造 `Frame`，
    /// 此方法仅供单帧发送或测试使用。不要在同一个连接上与
    /// `SecureChannel` 混用，否则会导致 seq 冲突。
    public func encodeNext(type: FrameType, payload: Data) -> Data {
        let seq: UInt32 = lock.withLock {
            let s = nextSeq
            nextSeq &+= 1
            return s
        }
        let frame = Frame(type: type, cipherId: cipherId, seq: seq, payload: payload)
        return encode(frame)
    }

    // MARK: - Decode

    /// 追加数据到缓冲区，并尝试切出所有完整帧。
    ///
    /// 整个切帧过程持锁，避免并发 `decode` 之间的缓冲区竞态。
    public func decode(_ data: Data) throws -> [Frame] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)

        var frames: [Frame] = []
        var offset = 0

        while buffer.count - offset >= Frame.headerSize {
            let base = buffer.startIndex + offset
            let version = buffer[base]
            let typeRaw = buffer[base + 1]
            let cipherId = (UInt16(buffer[base + 2]) << 8) | UInt16(buffer[base + 3])
            let seq = (UInt32(buffer[base + 4]) << 24)
                | (UInt32(buffer[base + 5]) << 16)
                | (UInt32(buffer[base + 6]) << 8)
                | UInt32(buffer[base + 7])
            let length = (Int(buffer[base + 8]) << 24)
                | (Int(buffer[base + 9]) << 16)
                | (Int(buffer[base + 10]) << 8)
                | Int(buffer[base + 11])

            guard version == Frame.currentVersion else {
                throw FrameError.invalidVersion(version)
            }
            guard let type = FrameType(rawValue: typeRaw) else {
                throw FrameError.invalidType(typeRaw)
            }
            guard length <= Frame.maxPayloadSize else {
                throw FrameError.payloadTooLarge(length)
            }

            let total = Frame.headerSize + length
            guard buffer.count - offset >= total else { break }

            let payloadStart = base + Frame.headerSize
            let payloadEnd = payloadStart + length
            let payload = buffer[payloadStart..<payloadEnd]

            frames.append(Frame(version: version,
                                type: type,
                                cipherId: cipherId,
                                seq: seq,
                                payload: Data(payload)))
            offset += total
        }

        if offset > 0 {
            buffer.removeFirst(offset)
        }

        return frames
    }

    /// 清空缓冲区
    public func reset() {
        lock.withLock { buffer.removeAll() }
    }
}
