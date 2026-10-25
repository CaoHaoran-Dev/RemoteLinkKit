//
//  ReconnectPolicyTests.swift
//  RemoteLinkKitTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteLinkKit

final class ReconnectPolicyTests: XCTestCase {
    func testExponentialBackoff() {
        let policy = ReconnectPolicy(initialDelay: 1, multiplier: 2, maxDelay: 30, maxAttempts: 10)
        XCTAssertEqual(policy.delay(forAttempt: 0), 1)
        XCTAssertEqual(policy.delay(forAttempt: 1), 2)
        XCTAssertEqual(policy.delay(forAttempt: 2), 4)
        XCTAssertEqual(policy.delay(forAttempt: 5), 30)   // 封顶
        XCTAssertNil(policy.delay(forAttempt: 10))        // 超次数
    }
}
