//
//  PairingTests.swift
//  RemoteProcessProtocolTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteProcessProtocol

final class PairingTests: XCTestCase {

    func testPairingCodeFormat() {
        let pc = PairingCode()
        XCTAssertEqual(pc.code.count, 6)
        XCTAssertTrue(pc.code.allSatisfy { $0.isNumber })
    }

    func testVerifySuccessMarksConsumed() throws {
        let pc = PairingCode()
        let code = pc.code
        try pc.verify(code)
        XCTAssertTrue(pc.isConsumed)
        XCTAssertThrowsError(try pc.verify(code))
    }

    func testVerifyWrongCodeFails() {
        let pc = PairingCode()
        let wrong = pc.code == "000000" ? "000001" : "000000"
        XCTAssertThrowsError(try pc.verify(wrong))
        XCTAssertFalse(pc.isConsumed)
    }

    func testLockAfterRepeatedFailures() {
        let pc = PairingCode()
        let wrong = pc.code == "000000" ? "000001" : "000000"
        for _ in 0..<PairingCode.maxAttemptsBeforeLock {
            _ = try? pc.verify(wrong)
        }
        XCTAssertTrue(pc.isLocked)
    }

    /// 新增：锁定过期后应清除锁标记，允许继续尝试，且正确码仍可成功。
    func testLockExpiresAndAllowsRetry() throws {
        let pc = PairingCode(validity: 600, lockDuration: 0.1)
        let wrong = pc.code == "000000" ? "000001" : "000000"

        for _ in 0..<PairingCode.maxAttemptsBeforeLock {
            _ = try? pc.verify(wrong)
        }
        XCTAssertTrue(pc.isLocked)

        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(pc.isLocked)

        let correct = pc.code
        XCTAssertNoThrow(try pc.verify(correct))
        XCTAssertTrue(pc.isConsumed)
    }

    /// 新增：累计失败达到作废阈值后，码被标记 consumed，正确码也不再可用。
    func testInvalidateAfterMaxFailures() throws {
        // 用极短 lockDuration，避免每次锁定阻塞后续失败累加。
        let pc = PairingCode(validity: 600, lockDuration: 0.01)
        let wrong = pc.code == "000000" ? "000001" : "000000"

        var totalFailures = 0
        while totalFailures < PairingCode.maxAttemptsBeforeInvalidate {
            do {
                try pc.verify(wrong)
            } catch PairingError.tooManyAttempts {
                // 锁定期跳过，等锁过期
                Thread.sleep(forTimeInterval: 0.02)
            } catch {
                totalFailures += 1
            }
            // 保险：避免死循环
            if totalFailures == 0 {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }

        XCTAssertTrue(pc.isConsumed, "Code should be invalidated after max failures")
        XCTAssertThrowsError(try pc.verify(pc.code))
    }

    func testTokenGenerateAndVerify() {
        let token = PairingToken.generate(deviceName: "iPhone")
        let hash = token.hash()
        XCTAssertTrue(PairingToken.verify(rawValue: token.rawValue, againstHash: hash))
        XCTAssertFalse(PairingToken.verify(rawValue: "wrong", againstHash: hash))
    }

    func testHandshakeProof() {
        let code = "123456"
        let serverId = "srv-1"
        let nonce = KeyDerivation.randomBytes(32)

        let pairKey = PairingHandshake.derivePairKey(code: code, serverId: serverId, nonce: nonce)
        let proof = PairingHandshake.computeProof(pairKey: pairKey, nonce: nonce)

        let serverPairKey = PairingHandshake.derivePairKey(code: code, serverId: serverId, nonce: nonce)
        XCTAssertTrue(PairingHandshake.verifyProof(pairKey: serverPairKey, nonce: nonce, proof: proof))

        let wrongKey = PairingHandshake.derivePairKey(code: "000000", serverId: serverId, nonce: nonce)
        XCTAssertFalse(PairingHandshake.verifyProof(pairKey: wrongKey, nonce: nonce, proof: proof))
    }
}
