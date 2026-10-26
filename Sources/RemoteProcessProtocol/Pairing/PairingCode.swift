//
//  PairingCode.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 6 位临时配对码
///
/// - 生成时随机 6 位数字
/// - 有效期默认 10 分钟
/// - 失败 5 次锁 1 分钟（锁定期间校验直接返回 tooManyAttempts，不累加失败次数）
/// - 累计失败 10 次作废
/// - 码本身不裸传，作为 HKDF 输入 + HMAC proof
public final class PairingCode: @unchecked Sendable {

    public static let codeLength = 6
    public static let maxAttemptsBeforeLock = 5
    public static let maxAttemptsBeforeInvalidate = 10

    private let lock = NSLock()
    private var _code: String
    private var _createdAt: Date
    private var _failedAttempts = 0
    private var _lockedUntil: Date?
    private var _consumed = false

    public let validity: TimeInterval
    public let lockDuration: TimeInterval

    public init(validity: TimeInterval = 600, lockDuration: TimeInterval = 60) {
        self.validity = validity
        self.lockDuration = lockDuration
        self._code = Self.generateCode()
        self._createdAt = Date()
    }

    // MARK: - Code

    public var code: String { lock.withLock { _code } }

    public func regenerate() {
        lock.withLock {
            _code = Self.generateCode()
            _createdAt = Date()
            _failedAttempts = 0
            _lockedUntil = nil
            _consumed = false
        }
    }

    public var isExpired: Bool {
        lock.withLock { Date().timeIntervalSince(_createdAt) > validity }
    }

    public var isLocked: Bool {
        lock.withLock {
            if let until = _lockedUntil, Date() < until { return true }
            return false
        }
    }

    public var isConsumed: Bool {
        lock.withLock { _consumed }
    }

    public var remainingTime: TimeInterval {
        lock.withLock { max(0, validity - Date().timeIntervalSince(_createdAt)) }
    }

    // MARK: - Verify

    /// 校验用户输入的码。成功则标记 consumed。
    public func verify(_ input: String) throws {
        let result: Result<Void, PairingError> = lock.withLock {
            if _consumed { return .failure(.codeExpired) }
            if Date().timeIntervalSince(_createdAt) > validity {
                return .failure(.codeExpired)
            }
            if let until = _lockedUntil, Date() < until {
                return .failure(.tooManyAttempts)
            }
            // 锁已过期：清除锁标记，允许继续尝试
            if _lockedUntil != nil {
                _lockedUntil = nil
            }

            if Self.constantTimeEqual(input, _code) {
                _consumed = true
                return .success(())
            } else {
                _failedAttempts += 1
                if _failedAttempts >= Self.maxAttemptsBeforeInvalidate {
                    _consumed = true
                    return .failure(.tooManyAttempts)
                }
                if _failedAttempts % Self.maxAttemptsBeforeLock == 0 {
                    _lockedUntil = Date().addingTimeInterval(lockDuration)
                }
                return .failure(.invalidCode)
            }
        }
        try result.get()
    }

    // MARK: - Generate

    private static func generateCode() -> String {
        let n = Int.random(in: 0..<1_000_000)
        return String(format: "%06d", n)
    }

    // MARK: - Constant-time Compare

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count {
            diff |= aBytes[i] ^ bBytes[i]
        }
        return diff == 0
    }
}
