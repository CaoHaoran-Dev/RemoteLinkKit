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

        // NWListener.newConnectionHandler 拿到的 NWConnection 可能已经 .ready。
        // 此时再设 stateUpdateHandler 会错过 .ready 事件，continuation 永不 resume。
        switch connection.state {
        case .ready:
            transition(.connected)
            receiveLoop()
            return
        case .failed(let error):
            throw ConnectionError.receiveFailed(underlying: error)
        case .cancelled:
            throw ConnectionError.closed
        default:
            break
        }

        // NWConnection 不保证 stateUpdateHandler 一定触发 .ready。
        // 如果 NWListener 内部已经对 connection 调过 start，再调 start
        // 可能不会重新触发 .ready，continuation 会永久挂起。
        // 用 3 秒超时兜底：超时后不抛错，直接进入 connected 并启动接收循环。
        // 如果连接实际不可用，receiveLoop 的 receiveMessage 会报错并走 handleDisconnect。
        let ready: Bool = await withTaskGroup(of: Bool.self) { group in
            group.addTask { [weak self] in
                guard let self = self else { return false }
                do {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        let resumed = LockedFlag()
                        self.connection.stateUpdateHandler = { [weak self] state in
                            guard let self = self else { return }
                            switch state {
                            case .ready:
                                if resumed.trySet() {
                                    self.connection.stateUpdateHandler = nil
                                    cont.resume()
                                }
                            case .failed(let error):
                                if resumed.trySet() {
                                    self.connection.stateUpdateHandler = nil
                                    cont.resume(throwing: ConnectionError.receiveFailed(underlying: error))
                                }
                            case .cancelled:
                                if resumed.trySet() {
                                    self.connection.stateUpdateHandler = nil
                                    cont.resume(throwing: ConnectionError.closed)
                                }
                            default:
                                break
                            }
                        }
                        self.connection.start(queue: self.queue)
                    }
                    return true
                } catch {
                    return false
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        // 无论是否等到 .ready，都继续启动接收循环。
        // 连接实际可用时 receiveMessage 正常工作；不可用时立刻报错。
        _ = ready
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

// MARK: - Helpers

/// 只允许 set 一次，避免 continuation 被 resume 两次。
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func trySet() -> Bool {
        lock.withLock {
            if value { return false }
            value = true
            return true
        }
    }
}

#endif
