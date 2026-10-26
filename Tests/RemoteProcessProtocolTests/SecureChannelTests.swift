//
//  SecureChannelTests.swift
//  RemoteProcessProtocolTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteProcessProtocol
import RemoteLinkKit

final class SecureChannelTests: XCTestCase {

    // MARK: - Loopback transport

    private final class LoopbackTransport: RemoteConnection, @unchecked Sendable {
        var state: ConnectionState = .connected
        var onStateChange: (@Sendable (ConnectionState) -> Void)?
        var onReceive: (@Sendable (Data) -> Void)?

        weak var peer: LoopbackTransport?

        func connect() async throws {}
        func send(_ data: Data) async throws {
            peer?.onReceive?(data)
        }
        func close() {}
    }

    // MARK: - Failing transport

    private final class FailingAfterOneSendTransport: RemoteConnection, @unchecked Sendable {
        var state: ConnectionState = .connected
        var onStateChange: (@Sendable (ConnectionState) -> Void)?
        var onReceive: (@Sendable (Data) -> Void)?

        private let lock = NSLock()
        private var sendCount = 0
        private let failOn: Int

        init(failOn: Int) { self.failOn = failOn }

        func connect() async throws {}
        func send(_ data: Data) async throws {
            let n: Int = lock.withLock {
                sendCount += 1
                return sendCount
            }
            if n == failOn {
                throw ConnectionError.sendFailed(
                    underlying: NSError(domain: "test", code: 1)
                )
            }
        }
        func close() {}
    }

    // MARK: - Tests

    func testClientToServerExec() async throws {
        let key = Data(repeating: 0x11, count: 32)
        let cipher = try AESGCMCipher(key: key)

        let clientTransport = LoopbackTransport()
        let serverTransport = LoopbackTransport()
        clientTransport.peer = serverTransport
        serverTransport.peer = clientTransport

        let client = SecureChannel(transport: clientTransport,
                                   cipher: cipher,
                                   cipherId: AESGCMCipher.cipherId,
                                   isClient: true)
        let server = SecureChannel(transport: serverTransport,
                                   cipher: cipher,
                                   cipherId: AESGCMCipher.cipherId,
                                   isClient: false)

        let exp = expectation(description: "server received exec")
        await server.setOnClientMessage { msg in
            if case .exec(let id, let cmd, let timeout) = msg {
                XCTAssertEqual(id, "1")
                XCTAssertEqual(cmd, "ls -la")
                XCTAssertEqual(timeout, 5)
                exp.fulfill()
            }
        }

        await client.start()
        await server.start()

        try await client.send(.exec(id: "1", cmd: "ls -la", timeout: 5))
        await fulfillment(of: [exp], timeout: 2.0)
    }

    func testServerToClientDone() async throws {
        let key = Data(repeating: 0x22, count: 32)
        let cipher = try ChaChaPolyCipher(key: key)

        let clientTransport = LoopbackTransport()
        let serverTransport = LoopbackTransport()
        clientTransport.peer = serverTransport
        serverTransport.peer = clientTransport

        let client = SecureChannel(transport: clientTransport,
                                   cipher: cipher,
                                   cipherId: ChaChaPolyCipher.cipherId,
                                   isClient: true)
        let server = SecureChannel(transport: serverTransport,
                                   cipher: cipher,
                                   cipherId: ChaChaPolyCipher.cipherId,
                                   isClient: false)

        let exp = expectation(description: "client received done")
        await client.setOnServerMessage { msg in
            if case .done(let id, let exit, let cwd) = msg {
                XCTAssertEqual(id, "1")
                XCTAssertEqual(exit, 0)
                XCTAssertEqual(cwd, "/tmp")
                exp.fulfill()
            }
        }

        await client.start()
        await server.start()

        try await server.send(.done(id: "1", exit: 0, cwd: "/tmp"))
        await fulfillment(of: [exp], timeout: 2.0)
    }

    func testMultipleMessagesInOrder() async throws {
        let key = Data(repeating: 0x33, count: 32)
        let cipher = try AESGCMCipher(key: key)

        let clientTransport = LoopbackTransport()
        let serverTransport = LoopbackTransport()
        clientTransport.peer = serverTransport
        serverTransport.peer = clientTransport

        let client = SecureChannel(transport: clientTransport,
                                   cipher: cipher,
                                   cipherId: AESGCMCipher.cipherId,
                                   isClient: true)
        let server = SecureChannel(transport: serverTransport,
                                   cipher: cipher,
                                   cipherId: AESGCMCipher.cipherId,
                                   isClient: false)

        let exp = expectation(description: "two messages")
        exp.expectedFulfillmentCount = 2
        exp.assertForOverFulfill = false
        await server.setOnClientMessage { _ in exp.fulfill() }

        await client.start()
        await server.start()

        try await client.send(.ping(timestamp: Date()))
        try await client.send(.cancel(id: "abc"))
        await fulfillment(of: [exp], timeout: 2.0)
    }

    func testOutputMessage() async throws {
        let key = Data(repeating: 0x44, count: 32)
        let cipher = try AESGCMCipher(key: key)

        let clientTransport = LoopbackTransport()
        let serverTransport = LoopbackTransport()
        clientTransport.peer = serverTransport
        serverTransport.peer = clientTransport

        let client = SecureChannel(transport: clientTransport,
                                   cipher: cipher,
                                   cipherId: AESGCMCipher.cipherId,
                                   isClient: true)
        let server = SecureChannel(transport: serverTransport,
                                   cipher: cipher,
                                   cipherId: AESGCMCipher.cipherId,
                                   isClient: false)

        let exp = expectation(description: "client received output")
        await client.setOnServerMessage { msg in
            if case .output(let id, let stream, let data) = msg {
                XCTAssertEqual(id, "1")
                XCTAssertEqual(stream, .stdout)
                XCTAssertEqual(String(data: data, encoding: .utf8), "hello world")
                exp.fulfill()
            }
        }

        await client.start()
        await server.start()

        try await server.send(.output(id: "1", stream: .stdout, data: Data("hello world".utf8)))
        await fulfillment(of: [exp], timeout: 2.0)
    }

    func testWrongCipherFailsToDecrypt() async throws {
        let clientKey = Data(repeating: 0xAA, count: 32)
        let serverKey = Data(repeating: 0xBB, count: 32)
        let clientCipher = try AESGCMCipher(key: clientKey)
        let serverCipher = try AESGCMCipher(key: serverKey)

        let clientTransport = LoopbackTransport()
        let serverTransport = LoopbackTransport()
        clientTransport.peer = serverTransport
        serverTransport.peer = clientTransport

        let client = SecureChannel(transport: clientTransport,
                                   cipher: clientCipher,
                                   cipherId: AESGCMCipher.cipherId,
                                   isClient: true)
        let server = SecureChannel(transport: serverTransport,
                                   cipher: serverCipher,
                                   cipherId: AESGCMCipher.cipherId,
                                   isClient: false)

        let errExp = expectation(description: "server got error")
        await server.setOnError { _ in errExp.fulfill() }
        await server.setOnClientMessage { _ in
            XCTFail("should not decode with wrong key")
        }

        await client.start()
        await server.start()

        try await client.send(.ping(timestamp: Date()))
        await fulfillment(of: [errExp], timeout: 2.0)
    }

    // MARK: - Send Failure Stickiness

    /// 回归保护：一次发送失败后，channel 应进入粘滞失败态，
    /// 后续发送直接抛错，不再消耗 seq / 尝试 transport。
    func testSendFailureSticksAndBlocksSubsequentSends() async throws {
        let key = Data(repeating: 0x55, count: 32)
        let cipher = try AESGCMCipher(key: key)
        let transport = FailingAfterOneSendTransport(failOn: 2)

        let channel = SecureChannel(transport: transport,
                                    cipher: cipher,
                                    cipherId: AESGCMCipher.cipherId,
                                    isClient: true)

        // 第一次发送成功
        try await channel.send(.ping(timestamp: Date()))

        // 第二次发送失败
        do {
            try await channel.send(.cancel(id: "x"))
            XCTFail("second send should throw")
        } catch {
            // expected
        }

        // 第三次发送应直接失败，不再尝试 transport
        do {
            try await channel.send(.cancel(id: "y"))
            XCTFail("third send should throw")
        } catch {
            // expected
        }
    }
}
