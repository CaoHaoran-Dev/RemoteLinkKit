//
//  ReplayGuard.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 防重放：维护已见 seq 窗口
public final class ReplayGuard: @unchecked Sendable {

    private let lock = NSLock()
    private var highestSeq: UInt32 = 0
    private var seen: Set<UInt32> = []
    private let windowSize: Int

    public init(windowSize: Int = 1024) {
        self.windowSize = windowSize
    }

    /// 校验并记录 seq。重复或过期返回 false。
    public func accept(_ seq: UInt32) -> Bool {
        lock.withLock {
            if seen.contains(seq) { return false }

            if seq > highestSeq {
                highestSeq = seq
                seen.insert(seq)
                prune()
                return true
            }

            if highestSeq - seq > UInt32(windowSize) {
                return false
            }

            seen.insert(seq)
            prune()
            return true
        }
    }

    private func prune() {
        guard highestSeq > UInt32(windowSize) else { return }
        let cutoff = highestSeq - UInt32(windowSize)
        seen = seen.filter { $0 > cutoff }
    }

    public func reset() {
        lock.withLock {
            highestSeq = 0
            seen.removeAll()
        }
    }
}
