//
//  HeartbeatController.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 定时 ping，超时回调。不关心 pong 的业务含义。
public final class HeartbeatController: @unchecked Sendable {

    // MARK: - Config

    public var interval: TimeInterval
    public var timeout: TimeInterval

    public var onSendPing: (@Sendable () -> Void)?
    public var onTimeout: (@Sendable () -> Void)?

    // MARK: - Private

    private let queue = DispatchQueue(label: "com.remotelinkkit.heartbeat")
    private let lock = NSLock()

    private var pingTimer: DispatchSourceTimer?
    private var timeoutTimer: DispatchSourceTimer?
    private var isRunning = false

    // MARK: - Init

    public init(interval: TimeInterval = 30, timeout: TimeInterval = 10) {
        self.interval = interval
        self.timeout = timeout
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    public func start() {
        lock.withLock {
            guard !isRunning else { return }
            isRunning = true
        }

        schedulePingTimer()
    }

    public func stop() {
        let (ping, timeout): (DispatchSourceTimer?, DispatchSourceTimer?) = lock.withLock {
            let p = pingTimer
            let t = timeoutTimer
            pingTimer = nil
            timeoutTimer = nil
            isRunning = false
            return (p, t)
        }

        ping?.cancel()
        timeout?.cancel()
    }

    // MARK: - Pong

    public func receivedPong() {
        cancelTimeoutTimer()
    }

    // MARK: - Ping Timer

    private func schedulePingTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval,
                       repeating: interval,
                       leeway: .milliseconds(100))

        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            let running = self.lock.withLock { self.isRunning }
            guard running else { return }

            self.onSendPing?()
            self.scheduleTimeoutTimer()
        }

        timer.resume()

        lock.withLock { pingTimer = timer }
    }

    // MARK: - Timeout Timer

    private func scheduleTimeoutTimer() {
        cancelTimeoutTimer()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeout)

        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            let running = self.lock.withLock { self.isRunning }
            guard running else { return }

            self.onTimeout?()
        }

        timer.resume()

        lock.withLock { timeoutTimer = timer }
    }

    private func cancelTimeoutTimer() {
        let timer: DispatchSourceTimer? = lock.withLock {
            let t = timeoutTimer
            timeoutTimer = nil
            return t
        }
        timer?.cancel()
    }
}
