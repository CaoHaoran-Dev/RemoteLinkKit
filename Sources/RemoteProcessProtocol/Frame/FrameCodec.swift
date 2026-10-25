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

    /// 分配下一个 seq 并编码
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

    /// 追加数据到缓冲区，并尝试切出所有完整帧
    public func decode(_ data: Data) throws -> [Frame] {
        lock.lock()
        buffer.append(data)
        let snapshot = buffer
        lock.unlock()

        var frames: [Frame] = []
        var offset = 0

        while snapshot.count - offset >= Frame.headerSize {
            let base = snapshot.startIndex + offset
            let version = snapshot[base]
            let typeRaw = snapshot[base + 1]
            let cipherId = (UInt16(snapshot[base + 2]) << 8) | UInt16(snapshot[base + 3])
            let seq = (UInt32(snapshot[base + 4]) << 24)
                | (UInt32(snapshot[base + 5]) << 16)
                | (UInt32(snapshot[base + 6]) << 8)
                | UInt32(snapshot[base + 7])
            let length = (Int(snapshot[base + 8]) << 24)
                | (Int(snapshot[base + 9]) << 16)
                | (Int(snapshot[base + 10]) << 8)
                | Int(snapshot[base + 11])

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
            guard snapshot.count - offset >= total else { break }

            let payloadStart = base + Frame.headerSize
            let payloadEnd = payloadStart + length
            let payload = snapshot[payloadStart..<payloadEnd]

            frames.append(Frame(version: version,
                                type: type,
                                cipherId: cipherId,
                                seq: seq,
                                payload: Data(payload)))
            offset += total
        }

        if offset > 0 {
            lock.lock()
            buffer.removeFirst(offset)
            lock.unlock()
        }

        return frames
    }

    /// 清空缓冲区
    public func reset() {
        lock.withLock { buffer.removeAll() }
    }
}
