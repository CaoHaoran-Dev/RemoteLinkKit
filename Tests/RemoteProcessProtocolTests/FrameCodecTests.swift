//
//  FrameCodecTests.swift
//  RemoteProcessProtocolTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteProcessProtocol

final class FrameCodecTests: XCTestCase {

    func testEncodeDecodeRoundTrip() throws {
        let codec = FrameCodec(cipherId: 1)
        let payload = Data("hello".utf8)
        let frame = Frame(type: .exec, cipherId: 1, seq: 7, payload: payload)

        let encoded = codec.encode(frame)
        let decoded = try codec.decode(encoded)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].type, .exec)
        XCTAssertEqual(decoded[0].seq, 7)
        XCTAssertEqual(decoded[0].payload, payload)
    }

    func testSplitAcrossChunks() throws {
        let codec = FrameCodec(cipherId: 1)
        let payload = Data("abcdef".utf8)
        let frame = Frame(type: .output, cipherId: 1, seq: 1, payload: payload)
        let encoded = codec.encode(frame)

        let half = encoded.count / 2
        XCTAssertTrue(try codec.decode(encoded.prefix(half)).isEmpty)
        let frames = try codec.decode(encoded.suffix(from: half))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].payload, payload)
    }

    func testMultipleFramesInOneChunk() throws {
        let codec = FrameCodec(cipherId: 1)
        let f1 = Frame(type: .exec, cipherId: 1, seq: 1, payload: Data("a".utf8))
        let f2 = Frame(type: .cancel, cipherId: 1, seq: 2, payload: Data("b".utf8))
        var combined = codec.encode(f1)
        combined.append(codec.encode(f2))

        let frames = try codec.decode(combined)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].type, .exec)
        XCTAssertEqual(frames[1].type, .cancel)
    }

    func testInvalidVersion() {
        let codec = FrameCodec(cipherId: 1)
        var data = Data()
        data.append(99)                       // version
        data.append(FrameType.exec.rawValue)
        data.append(contentsOf: [0, 1, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertThrowsError(try codec.decode(data))
    }

    func testEncodeNextIncrementsSeq() throws {
        let codec = FrameCodec(cipherId: 1)
        let a = codec.encodeNext(type: .exec, payload: Data())
        let b = codec.encodeNext(type: .exec, payload: Data())

        let fa = try codec.decode(a)[0]
        let fb = try codec.decode(b)[0]
        XCTAssertEqual(fa.seq, 0)
        XCTAssertEqual(fb.seq, 1)
    }
}
