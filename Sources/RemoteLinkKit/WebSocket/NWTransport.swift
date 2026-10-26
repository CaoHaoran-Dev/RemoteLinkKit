//
//  NWTransport.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
#if canImport(Network)
import Network

/// 服务端 WebSocket 实现，基于 NWConnection + NWProtocolWebSocket
public final class NWTransport: RemoteConnection, @unchecked Sendable {

    // MARK: - Public State

    public var onStateChange: (@Sendable (ConnectionState) -> Void)?
    public var onReceive: (@Sendable (Data) -> Void)?

    public var state: ConnectionState {
        lock.withLock { _state }
    }

    // MARK: - Private

    private let connection: NWConnection
    private let transform: ConnectionTransform
    private let queue = DispatchQueue(label: "com.remotelinkkit.nwtransport")

    private let lock = NSLock()
    private var _state: ConnectionState = .idle
    private var isClosedByUser = false
    private var isClosed = false

    // MARK: - Init

    public init(connection: NWConnection,
                transform: ConnectionTransform = PassthroughTransform()) {
        self.connection = connection
        self.transform = transform
    }

    // MARK: - Connect

    public func connect() async throws {
        transition(.connecting)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.connection.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let error):
                    self.connection.stateUpdateHandler = nil
                    cont.resume(throwing: ConnectionError.receiveFailed(underlying: error))
                case .cancelled:
                    self.connection.stateUpdateHandler = nil
                    cont.resume(throwing: ConnectionError.closed)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        transition(.connected)
        receiveLoop()
    }

    // MARK: - Send

    public func send(_ data: Data) async throws {
        if lock.withLock({ isClosed }) {
            throw ConnectionError.closed
        }

        let payload = try transform.encode(data)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(
                identifier: "ws.binary",
                metadata: [metadata]
            )

            connection.send(
                content: payload,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error = error {
                        cont.resume(throwing: ConnectionError.sendFailed(underlying: error))
                    } else {
                        cont.resume()
                    }
                }
            )
        }
    }

    // MARK: - Close

    public func close() {
        let shouldClose = lock.withLock { () -> Bool in
            if isClosed { return false }
            isClosed = true
            isClosedByUser = true
            return true
        }
        guard shouldClose else { return }

        // 发关闭帧。用局部 connection 强捕获，避免 transport 先释放导致
        // cancel 不执行、NWConnection 泄漏。
        let conn = self.connection

        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        let context = NWConnection.ContentContext(
            identifier: "ws.close",
            metadata: [metadata]
        )
        conn.send(
            content: nil,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in
                conn.cancel()
            }
        )

        transition(.closed(reason: nil))
    }

    // MARK: - Receive

    private func receiveLoop() {
        let closed = lock.withLock { isClosed }
        guard !closed else { return }

        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self = self else { return }

            if let error = error {
                self.handleDisconnect(error: error)
                return
            }

            let closedNow = self.lock.withLock { self.isClosed }
            if closedNow { return }

            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata {

                switch metadata.opcode {
                case .binary, .text:
                    if let data = data, !data.isEmpty,
                       let decoded = try? self.transform.decode(data) {
                        self.onReceive?(decoded)
                    }
                case .close:
                    self.handleDisconnect(error: ConnectionError.closed)
                    return
                case .ping:
                    self.replyPong(data: data)
                case .pong:
                    break
                default:
                    break
                }
            }

            self.receiveLoop()
        }
    }

    private func replyPong(data: Data?) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .pong)
        let context = NWConnection.ContentContext(
            identifier: "ws.pong",
            metadata: [metadata]
        )
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    // MARK: - Disconnect

    private func handleDisconnect(error: Error) {
        let alreadyClosed = lock.withLock { () -> Bool in
            if isClosed { return true }
            isClosed = true
            return false
        }
        connection.cancel()

        if alreadyClosed { return }
        transition(.closed(reason: error.localizedDescription))
    }

    // MARK: - State

    private func transition(_ newState: ConnectionState) {
        let handler: (@Sendable (ConnectionState) -> Void)? = lock.withLock {
            _state = newState
            return onStateChange
        }
        handler?(newState)
    }
}
#endif
