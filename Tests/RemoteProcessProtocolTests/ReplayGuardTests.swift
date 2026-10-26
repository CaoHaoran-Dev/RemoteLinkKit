//
//  ReplayGuardTests.swift
//  RemoteProcessProtocolTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteProcessProtocol

final class ReplayGuardTests: XCTestCase {

    func testMonotonicAccepted() {
        let g = ReplayGuard()
        XCTAssertTrue(g.accept(1))
        XCTAssertTrue(g.accept(2))
        XCTAssertTrue(g.accept(3))
    }

    func testDuplicateRejected() {
        let g = ReplayGuard()
        XCTAssertTrue(g.accept(5))
        XCTAssertFalse(g.accept(5))
    }

    func testOutOfOrderWithinWindowAccepted() {
        let g = ReplayGuard()
        XCTAssertTrue(g.accept(10))
        XCTAssertTrue(g.accept(8))
        XCTAssertTrue(g.accept(9))
    }

    func testTooOldRejected() {
        let g = ReplayGuard(windowSize: 4)
        XCTAssertTrue(g.accept(10))
        XCTAssertFalse(g.accept(1))
    }

    func testReset() {
        let g = ReplayGuard()
        XCTAssertTrue(g.accept(1))
        g.reset()
        XCTAssertTrue(g.accept(1))
    }
}
