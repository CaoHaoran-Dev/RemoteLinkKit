//
//  HeartbeatController.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

public final class HeartbeatController: @unchecked Sendable {

    public var interval: TimeInterval
    public var timeout: TimeInterval

    public var onSendPing: (@Sendable () -> Void)?
    public var onTimeout: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "com.remotelinkkit.heartbeat")
    private let lock = NSLock()

    private var pingTimer: DispatchSourceTimer?
    private var timeoutTimer: DispatchSourceTimer?
    private var isRunning = false
    private var lastPongTime: Date?
    private var hasPendingPing = false

    public init(interval: TimeInterval = 30, timeout: TimeInterval = 10) {
        self.interval = interval
        self.timeout = timeout
    }

    deinit {
        stop()
    }

    public func start() {
        lock.withLock {
            guard !isRunning else { return }
            isRunning = true
            lastPongTime = Date()
            hasPendingPing = false
        }
        schedulePingTimer()
        scheduleTimeoutCheckTimer()
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

    public func receivedPong() {
        lock.withLock {
            lastPongTime = Date()
            hasPendingPing = false
        }
    }

    // MARK: - Ping Timer

    private func schedulePingTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))

        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let running = self.lock.withLock { self.isRunning }
            guard running else { return }

            self.lock.withLock { self.hasPendingPing = true }
            self.onSendPing?()
        }

        timer.resume()
        lock.withLock { pingTimer = timer }
    }

    // MARK: - Timeout Check Timer

    private func scheduleTimeoutCheckTimer() {
        let checkInterval = min(interval, timeout) / 2
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + checkInterval, repeating: checkInterval, leeway: .milliseconds(50))

        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            let (running, shouldTimeout): (Bool, Bool) = self.lock.withLock {
                guard self.isRunning else { return (false, false) }
                guard self.hasPendingPing, let last = self.lastPongTime else { return (true, false) }
                return (true, Date().timeIntervalSince(last) >= self.timeout)
            }

            guard running, shouldTimeout else { return }

            self.lock.withLock { self.hasPendingPing = false }
            self.onTimeout?()
        }

        timer.resume()
        lock.withLock { timeoutTimer = timer }
    }
}
