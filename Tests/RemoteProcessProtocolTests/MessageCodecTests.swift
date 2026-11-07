//
//  MessageCodecTests.swift
//  RemoteProcessProtocolTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteProcessProtocol

final class MessageCodecTests: XCTestCase {

    // MARK: - 原有用例

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

    // MARK: - Custom 用例

    func testClientCustomRoundTrip() throws {
        let msg = ClientMessage.custom(
            type: "file-chunk",
            payload: Data([0x00, 0x01, 0xFE, 0xFF])
        )
        let data = try MessageCodec.encode(msg)
        let decoded = try MessageCodec.decodeClient(data)
        XCTAssertEqual(decoded, msg)
    }

    func testServerCustomRoundTrip() throws {
        let msg = ServerMessage.custom(
            type: "image",
            payload: Data("binary".utf8)
        )
        let data = try MessageCodec.encode(msg)
        let decoded = try MessageCodec.decodeServer(data)
        XCTAssertEqual(decoded, msg)
    }

    func testCustomEmptyPayload() throws {
        let msg = ClientMessage.custom(type: "noop", payload: Data())
        let data = try MessageCodec.encode(msg)
        XCTAssertEqual(try MessageCodec.decodeClient(data), msg)
    }

    /// 二进制安全：全部 256 种字节值往返不变
    func testCustomPayloadBinarySafe() throws {
        let bytes = Data((0...255).map { UInt8($0) })
        let msg = ClientMessage.custom(type: "blob", payload: bytes)
        let data = try MessageCodec.encode(msg)
        let decoded = try MessageCodec.decodeClient(data)
        guard case .custom(_, let payload) = decoded else {
            return XCTFail("expected custom")
        }
        XCTAssertEqual(payload, bytes)
    }

    /// 业务子类型正确保留
    func testCustomSubtypePreserved() throws {
        let msg = ServerMessage.custom(type: "render-frame", payload: Data([1, 2, 3]))
        let decoded = try MessageCodec.decodeServer(try MessageCodec.encode(msg))
        guard case .custom(let t, _) = decoded else {
            return XCTFail("expected custom")
        }
        XCTAssertEqual(t, "render-frame")
    }

    /// JSON 里消息类型是 "custom"，业务子类型在 "customType"，两者不冲突
    func testCustomJSONShape() throws {
        let msg = ClientMessage.custom(type: "ping-custom", payload: Data([0xAB]))
        let data = try MessageCodec.encode(msg)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "custom")
        XCTAssertEqual(obj?["customType"] as? String, "ping-custom")
        XCTAssertEqual(obj?["payload"] as? String, Data([0xAB]).base64EncodedString())
    }

    /// frameType 映射到 .handshake
    func testCustomFrameType() {
        let c = ClientMessage.custom(type: "x", payload: Data())
        XCTAssertEqual(c.frameType, .handshake)
        let s = ServerMessage.custom(type: "x", payload: Data())
        XCTAssertEqual(s.frameType, .handshake)
    }

    /// 原有消息的 frameType 未被改动
    func testExistingFrameTypesUnchanged() {
        XCTAssertEqual(ClientMessage.exec(id: "1", cmd: "x", timeout: 1).frameType, .exec)
        XCTAssertEqual(ClientMessage.cancel(id: "1").frameType, .cancel)
        XCTAssertEqual(ClientMessage.ping(timestamp: Date()).frameType, .ping)
        XCTAssertEqual(ServerMessage.output(id: "1", stream: .stdout, data: Data()).frameType, .output)
        XCTAssertEqual(ServerMessage.done(id: "1", exit: 0, cwd: "/").frameType, .done)
        XCTAssertEqual(ServerMessage.error(id: nil, message: "e").frameType, .error)
        XCTAssertEqual(ServerMessage.pong(timestamp: Date()).frameType, .pong)
        XCTAssertEqual(ServerMessage.cwd(path: "/").frameType, .cwd)
    }
}
