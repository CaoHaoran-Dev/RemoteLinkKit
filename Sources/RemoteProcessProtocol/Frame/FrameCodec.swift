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
    /// 使用 `withUnsafeBytes` 做显式偏移读取，不依赖 `Data.startIndex` 的取值。
    public func decode(_ data: Data) throws -> [Frame] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)

        var frames: [Frame] = []

        while true {
            let result: FrameDecodeStep = buffer.withUnsafeBytes { raw -> FrameDecodeStep in
                guard raw.count >= Frame.headerSize else { return .needMore }
                guard let base = raw.baseAddress else { return .needMore }

                let p = base.assumingMemoryBound(to: UInt8.self)

                let version = p[0]
                let typeRaw = p[1]
                let cipherId = (UInt16(p[2]) << 8) | UInt16(p[3])
                let seq = (UInt32(p[4]) << 24)
                    | (UInt32(p[5]) << 16)
                    | (UInt32(p[6]) << 8)
                    | UInt32(p[7])
                let length = (Int(p[8]) << 24)
                    | (Int(p[9]) << 16)
                    | (Int(p[10]) << 8)
                    | Int(p[11])

                if version != Frame.currentVersion {
                    return .error(.invalidVersion(version))
                }
                guard let type = FrameType(rawValue: typeRaw) else {
                    return .error(.invalidType(typeRaw))
                }
                if length > Frame.maxPayloadSize {
                    return .error(.payloadTooLarge(length))
                }

                let total = Frame.headerSize + length
                if raw.count < total { return .needMore }

                let payload = Data(bytes: p + Frame.headerSize, count: length)
                return .frame(Frame(version: version,
                                    type: type,
                                    cipherId: cipherId,
                                    seq: seq,
                                    payload: payload),
                              consumed: total)
            }

            switch result {
            case .needMore:
                return frames
            case .error(let error):
                throw error
            case .frame(let frame, let consumedBytes):
                frames.append(frame)
                buffer.removeFirst(consumedBytes)
            }
        }
    }

    /// 清空缓冲区
    public func reset() {
        lock.withLock { buffer.removeAll() }
    }

    // MARK: - Decode Step

    private enum FrameDecodeStep {
        case needMore
        case error(FrameError)
        case frame(Frame, consumed: Int)
    }
}
