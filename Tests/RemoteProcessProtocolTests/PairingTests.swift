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
