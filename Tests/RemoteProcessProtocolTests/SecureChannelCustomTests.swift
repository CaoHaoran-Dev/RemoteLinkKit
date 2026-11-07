//
//  SecureChannelCustomTests.swift
//  RemoteProcessProtocolTests
//
//  Created by Haoran on 2026/11/7.
//

import XCTest
@testable import RemoteProcessProtocol
import RemoteLinkKit

final class SecureChannelCustomTests: XCTestCase {

    private final class LoopbackTransport: RemoteConnection, @unchecked Sendable {
        var state: ConnectionState = .connected
        var onStateChange: (@Sendable (ConnectionState) -> Void)?
        var onReceive: (@Sendable (Data) -> Void)?
        weak var peer: LoopbackTransport?
        func connect() async throws {}
        func send(_ data: Data) async throws { peer?.onReceive?(data) }
        func close() {}
    }

    private func makePair(
        cipher: CipherSuite,
        cipherId: UInt16
    ) async -> (client: SecureChannel, server: SecureChannel) {
        let ct = LoopbackTransport()
        let st = LoopbackTransport()
        ct.peer = st
        st.peer = ct

        let client = SecureChannel(transport: ct, cipher: cipher, cipherId: cipherId, isClient: true)
        let server = SecureChannel(transport: st, cipher: cipher, cipherId: cipherId, isClient: false)
        await client.start()
        await server.start()
        return (client, server)
    }

    func testClientCustomReachesServer() async throws {
        let cipher = try AESGCMCipher(key: Data(repeating: 0x66, count: 32))
        let (client, server) = await makePair(cipher: cipher, cipherId: AESGCMCipher.cipherId)

        let exp = expectation(description: "server got custom")
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        await server.setOnClientMessage { msg in
            if case .custom(let t, let p) = msg {
                XCTAssertEqual(t, "file-chunk")
                XCTAssertEqual(p, payload)
                exp.fulfill()
            }
        }

        try await client.send(ClientMessage.custom(type: "file-chunk", payload: payload))
        await fulfillment(of: [exp], timeout: 2.0)
    }

    func testServerCustomReachesClient() async throws {
        let cipher = try ChaChaPolyCipher(key: Data(repeating: 0x77, count: 32))
        let (client, server) = await makePair(cipher: cipher, cipherId: ChaChaPolyCipher.cipherId)

        let exp = expectation(description: "client got custom")
        let payload = Data("image-bytes".utf8)
        await client.setOnServerMessage { msg in
            if case .custom(let t, let p) = msg {
                XCTAssertEqual(t, "image")
                XCTAssertEqual(p, payload)
                exp.fulfill()
            }
        }

        try await server.send(ServerMessage.custom(type: "image", payload: payload))
        await fulfillment(of: [exp], timeout: 2.0)
    }

    /// custom 与普通消息混发，seq 连续、不串扰
    func testMixedCustomAndNormalMessages() async throws {
        let cipher = try AESGCMCipher(key: Data(repeating: 0x88, count: 32))
        let (client, server) = await makePair(cipher: cipher, cipherId: AESGCMCipher.cipherId)

        let exp = expectation(description: "3 messages")
        exp.expectedFulfillmentCount = 3
        exp.assertForOverFulfill = false

        let box = LockedBox<[String]>([])
        await server.setOnClientMessage { msg in
            switch msg {
            case .exec: box.mutate { $0.append("exec") }
            case .custom(let t, _): box.mutate { $0.append("custom:\(t)") }
            default: break
            }
            exp.fulfill()
        }

        try await client.send(ClientMessage.exec(id: "1", cmd: "ls", timeout: 5))
        try await client.send(ClientMessage.custom(type: "chunk", payload: Data([1])))
        try await client.send(ClientMessage.custom(type: "done", payload: Data([2])))

        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(box.value, ["exec", "custom:chunk", "custom:done"])
    }

    /// 错误密钥下 custom 也解不开，走 error 回调
    func testCustomWithWrongKeyFails() async throws {
        let clientCipher = try AESGCMCipher(key: Data(repeating: 0xAA, count: 32))
        let serverCipher = try AESGCMCipher(key: Data(repeating: 0xBB, count: 32))

        let ct = LoopbackTransport()
        let st = LoopbackTransport()
        ct.peer = st
        st.peer = ct
        let client = SecureChannel(transport: ct, cipher: clientCipher, cipherId: AESGCMCipher.cipherId, isClient: true)
        let server = SecureChannel(transport: st, cipher: serverCipher, cipherId: AESGCMCipher.cipherId, isClient: false)
        await client.start()
        await server.start()

        let errExp = expectation(description: "server error")
        await server.setOnError { _ in errExp.fulfill() }
        await server.setOnClientMessage { _ in XCTFail("should not decrypt") }

        try await client.send(ClientMessage.custom(type: "x", payload: Data([1])))
        await fulfillment(of: [errExp], timeout: 2.0)
    }

    // MARK: - Helper

    private final class LockedBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T
        init(_ v: T) { _value = v }
        var value: T { lock.withLock { _value } }
        func mutate(_ f: (inout T) -> Void) { lock.withLock { f(&_value) } }
    }
}
