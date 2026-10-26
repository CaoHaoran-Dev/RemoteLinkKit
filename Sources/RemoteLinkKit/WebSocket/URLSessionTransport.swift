//
//  URLSessionTransport.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 客户端 WebSocket 实现，基于 URLSessionWebSocketTask
public final class URLSessionTransport: RemoteConnection, @unchecked Sendable {

    // MARK: - Public State

    public var onStateChange: (@Sendable (ConnectionState) -> Void)?
    public var onReceive: (@Sendable (Data) -> Void)?

    public var state: ConnectionState {
        lock.withLock { _state }
    }

    // MARK: - Private

    private let config: ConnectionConfig
    private let transform: ConnectionTransform
    private let reconnectPolicy: ReconnectPolicy?

    private let lock = NSLock()
    private var _state: ConnectionState = .idle
    private var task: URLSessionWebSocketTask?
    private var reconnectAttempt = 0
    private var isClosedByUser = false

    /// 发送串行化
    private let sendQueue = DispatchQueue(label: "com.remotelinkkit.send")

    /// 允许的最大连接超时（秒）。`Task.sleep` 的纳秒参数是 `UInt64`，
    /// 超过约 9.2e9 秒会溢出。这里钳到一个远大于任何合理配置、但不会溢出的值。
    private static let maxConnectTimeout: TimeInterval = 24 * 60 * 60   // 1 day

    // MARK: - Init

    public init(config: ConnectionConfig,
                transform: ConnectionTransform = PassthroughTransform(),
                reconnectPolicy: ReconnectPolicy? = nil) {
        self.config = config
        self.transform = transform
        self.reconnectPolicy = reconnectPolicy
    }

    // MARK: - Connect

    public func connect() async throws {
        guard let url = config.url else {
            throw ConnectionError.invalidURL
        }

        lock.withLock { isClosedByUser = false }

        transition(.connecting)

        try await openTask(url: url)
        transition(.connected)

        reconnectAttempt = 0
        receiveLoop()
    }

    /// 打开 WebSocket 并等待就绪。
    ///
    /// 不能用 `withThrowingTaskGroup` 包 `sendPing`：`sendPing` 的回调没有取消机制，
    /// 超时结束后回调仍可能触发，导致 continuation 双重 resume（崩溃）。
    /// 这里用一把锁 + 单次 resume 出口保证安全。
    ///
    /// 超时看门狗用 `Task` 实现，并且只捕获 Sendable 值（nanos / resumeOnce / cont），
    /// 不捕获 `self`，避免严格并发检查告警。
    private func openTask(url: URL) async throws {
        // 防御非法超时配置：非有限、非正数视为错误；
        // 过大的值钳到上界，避免 Double -> UInt64 纳秒转换 trap。
        let rawTimeout = config.connectTimeout
        guard rawTimeout.isFinite, rawTimeout > 0 else {
            throw ConnectionError.timeout
        }
        let timeout = min(rawTimeout, Self.maxConnectTimeout)

        let task = URLSession.shared.webSocketTask(with: url)

        lock.withLock { self.task = task }

        task.resume()

        let resumeOnce = ResumeOnce()
        let nanos = UInt64(timeout * 1_000_000_000)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // 超时看门狗
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    // 被取消：ping 先完成，什么都不做
                    return
                }
                if resumeOnce.tryResume() {
                    cont.resume(throwing: ConnectionError.timeout)
                }
            }

            // 连接就绪探测：发一个 ping
            task.sendPing { error in
                // 先取消看门狗，避免超时后再 resume
                timeoutTask.cancel()
                guard resumeOnce.tryResume() else { return }
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    // MARK: - Send

    public func send(_ data: Data) async throws {
        let payload = try transform.encode(data)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sendQueue.async { [weak self] in
                guard let self = self else {
                    cont.resume(throwing: ConnectionError.closed)
                    return
                }

                let task = self.lock.withLock { self.task }

                guard let task = task else {
                    cont.resume(throwing: ConnectionError.notConnected)
                    return
                }

                task.send(.data(payload)) { error in
                    if let error = error {
                        cont.resume(throwing: ConnectionError.sendFailed(underlying: error))
                    } else {
                        cont.resume()
                    }
                }
            }
        }
    }

    // MARK: - Close

    public func close() {
        let task: URLSessionWebSocketTask? = lock.withLock {
            isClosedByUser = true
            let t = self.task
            self.task = nil
            return t
        }

        task?.cancel(with: .normalClosure, reason: nil)
        transition(.closed(reason: nil))
    }

    // MARK: - Receive

    private func receiveLoop() {
        let task = lock.withLock { self.task }

        guard let task = task else { return }

        task.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    if let decoded = try? self.transform.decode(data) {
                        self.onReceive?(decoded)
                    }
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let decoded = try? self.transform.decode(data) {
                        self.onReceive?(decoded)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()

            case .failure(let error):
                self.handleDisconnect(error: error)
            }
        }
    }

    // MARK: - Reconnect

    private func handleDisconnect(error: Error) {
        let (closedByUser, stillHasTask): (Bool, Bool) = lock.withLock {
            let c = isClosedByUser
            let had = self.task != nil
            self.task = nil
            return (c, had)
        }

        // 如果 task 已经被置空（close 或重复回调），避免重复处理
        guard stillHasTask else {
            if !closedByUser {
                transition(.closed(reason: error.localizedDescription))
            }
            return
        }

        guard !closedByUser else {
            transition(.closed(reason: error.localizedDescription))
            return
        }

        guard let policy = reconnectPolicy else {
            transition(.closed(reason: error.localizedDescription))
            return
        }

        guard let url = config.url else {
            transition(.closed(reason: "invalid url"))
            return
        }

        let attempt = reconnectAttempt
        guard let delay = policy.delay(forAttempt: attempt) else {
            transition(.closed(reason: "reconnect attempts exhausted"))
            return
        }

        reconnectAttempt += 1
        transition(.reconnecting(attempt: attempt + 1))

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }

            let userClosed = self.lock.withLock { self.isClosedByUser }
            guard !userClosed else { return }

            Task {
                do {
                    try await self.openTask(url: url)
                    self.transition(.connected)
                    self.reconnectAttempt = 0
                    self.receiveLoop()
                } catch {
                    self.handleDisconnect(error: error)
                }
            }
        }
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

// MARK: - ResumeOnce

/// 单次 resume 保护：并发环境下只有一个调用方能把 continuation resume 掉。
/// 用于 `sendPing` 回调与超时看门狗之间的竞速。
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    /// 返回 true 表示本次调用赢得了 resume 权。
    func tryResume() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}
