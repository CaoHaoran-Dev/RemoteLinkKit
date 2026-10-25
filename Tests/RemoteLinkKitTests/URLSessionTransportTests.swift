//
//  URLSessionTransportTests.swift
//  RemoteLinkKitTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteLinkKit

#if canImport(Network)
import Network

final class URLSessionTransportTests: XCTestCase {

    private var listener: NWListener?

    override func tearDown() {
        listener?.cancel()
        listener = nil
        super.tearDown()
    }

    // MARK: - Thread-safe boxes

    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T
        init(_ value: T) { self._value = value }
        var value: T {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

    private final class ArrayBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _items: [T] = []
        func append(_ item: T) { lock.withLock { _items.append(item) } }
        var snapshot: [T] { lock.withLock { _items } }
    }

    private final class FlagBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        func trySet() -> Bool {
            lock.withLock {
                if _value { return false }
                _value = true
                return true
            }
        }
    }

    // MARK: - Echo server

    private func startEchoServer() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let listener = try NWListener(using: params, on: .any)
        let resumed = FlagBox()

        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let p = listener.port?.rawValue, p != 0, resumed.trySet() {
                        cont.resume(returning: p)
                    }
                case .failed(let error):
                    if resumed.trySet() {
                        cont.resume(throwing: error)
                    }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { conn in
                Self.echoLoop(conn)
            }
            listener.start(queue: .global())
        }

        self.listener = listener
        return port
    }

    private static func echoLoop(_ conn: NWConnection) {
        conn.start(queue: .global())
        func receive() {
            conn.receiveMessage { data, context, _, error in
                guard error == nil else { conn.cancel(); return }
                if let data = data, !data.isEmpty,
                   let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
                   meta.opcode == .binary {
                    let replyMeta = NWProtocolWebSocket.Metadata(opcode: .binary)
                    let ctx = NWConnection.ContentContext(identifier: "echo", metadata: [replyMeta])
                    conn.send(content: data, contentContext: ctx, isComplete: true,
                              completion: .contentProcessed { _ in })
                }
                receive()
            }
        }
        receive()
    }

    // MARK: - Tests

    func testConnectSendReceive() async throws {
        let port = try await startEchoServer()
        let config = ConnectionConfig(host: "127.0.0.1", port: Int(port))
        let transport = URLSessionTransport(config: config)

        let received = expectation(description: "received echo")
        let echoed = Box<Data?>(nil)

        transport.onReceive = { data in
            echoed.value = data
            received.fulfill()
        }

        try await transport.connect()

        let payload = Data("hello".utf8)
        try await transport.send(payload)

        await fulfillment(of: [received], timeout: 3.0)
        XCTAssertEqual(echoed.value, payload)

        transport.close()
    }

    func testConnectTimesOut() async {
        let config = ConnectionConfig(host: "127.0.0.1", port: 1, connectTimeout: 0.5)
        let transport = URLSessionTransport(config: config)

        do {
            try await transport.connect()
            XCTFail("should have timed out or failed")
        } catch {
            // 预期失败
        }
    }

    func testTransformEncodeDecode() async throws {
        let port = try await startEchoServer()
        let config = ConnectionConfig(host: "127.0.0.1", port: Int(port))

        struct XORTransform: ConnectionTransform {
            let key: UInt8
            func encode(_ data: Data) throws -> Data {
                Data(data.map { $0 ^ key })
            }
            func decode(_ data: Data) throws -> Data {
                Data(data.map { $0 ^ key })
            }
        }

        let transport = URLSessionTransport(config: config, transform: XORTransform(key: 0xAB))

        let received = expectation(description: "received")
        let echoed = Box<Data?>(nil)
        transport.onReceive = { data in
            echoed.value = data
            received.fulfill()
        }

        try await transport.connect()
        let payload = Data("transform".utf8)
        try await transport.send(payload)

        await fulfillment(of: [received], timeout: 3.0)
        XCTAssertEqual(echoed.value, payload)

        transport.close()
    }

    func testStateTransitions() async throws {
        let port = try await startEchoServer()
        let config = ConnectionConfig(host: "127.0.0.1", port: Int(port))
        let transport = URLSessionTransport(config: config)

        let states = ArrayBox<String>()
        transport.onStateChange = { state in
            states.append("\(state)")
        }

        try await transport.connect()
        transport.close()

        let snapshot = states.snapshot
        XCTAssertTrue(snapshot.contains(where: { $0.contains("connecting") }))
        XCTAssertTrue(snapshot.contains(where: { $0.contains("connected") }))
        XCTAssertTrue(snapshot.contains(where: { $0.contains("closed") }))
    }
}
#endif
