//
//  MessageCodecTests.swift
//  RemoteProcessProtocolTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteProcessProtocol

final class MessageCodecTests: XCTestCase {

    func testClientExecRoundTrip() throws {
        let msg = ClientMessage.exec(id: "1", cmd: "ls -la", timeout: 10)
        let data = try MessageCodec.encode(msg)
        let decoded = try MessageCodec.decodeClient(data)
        XCTAssertEqual(decoded, msg)
    }

    func testClientCancelRoundTrip() throws {
        let msg = ClientMessage.cancel(id: "1")
        let data = try MessageCodec.encode(msg)
        XCTAssertEqual(try MessageCodec.decodeClient(data), msg)
    }

    func testClientPingRoundTrip() throws {
        let msg = ClientMessage.ping(timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try MessageCodec.encode(msg)
        let decoded = try MessageCodec.decodeClient(data)
        if case .ping(let ts) = decoded {
            XCTAssertEqual(ts.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
        } else {
            XCTFail("expected ping")
        }
    }

    func testServerOutputRoundTrip() throws {
        let msg = ServerMessage.output(id: "1", stream: .stdout, data: Data("hi".utf8))
        let data = try MessageCodec.encode(msg)
        XCTAssertEqual(try MessageCodec.decodeServer(data), msg)
    }

    func testServerDoneRoundTrip() throws {
        let msg = ServerMessage.done(id: "1", exit: 0, cwd: "/tmp")
        let data = try MessageCodec.encode(msg)
        XCTAssertEqual(try MessageCodec.decodeServer(data), msg)
    }

    func testServerErrorRoundTrip() throws {
        let msg = ServerMessage.error(id: "1", message: "boom")
        let data = try MessageCodec.encode(msg)
        XCTAssertEqual(try MessageCodec.decodeServer(data), msg)
    }

    func testUnknownTypeThrows() throws {
        let json = Data(#"{"type":"unknown"}"#.utf8)
        XCTAssertThrowsError(try MessageCodec.decodeClient(json))
    }
}
