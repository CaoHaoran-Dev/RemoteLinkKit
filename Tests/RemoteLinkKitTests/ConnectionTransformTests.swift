//
//  ConnectionTransformTests.swift
//  RemoteLinkKitTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteLinkKit

final class ConnectionTransformTests: XCTestCase {
    func testPassthrough() throws {
        let t = PassthroughTransform()
        let data = Data([1, 2, 3])
        XCTAssertEqual(try t.encode(data), data)
        XCTAssertEqual(try t.decode(data), data)
    }
}
