//
//  ConnectionStateTests.swift
//  RemoteLinkKitTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteLinkKit

final class ConnectionStateTests: XCTestCase {
    func testEquality() {
        XCTAssertEqual(ConnectionState.idle, .idle)
        XCTAssertNotEqual(ConnectionState.connected, .idle)
    }
}
