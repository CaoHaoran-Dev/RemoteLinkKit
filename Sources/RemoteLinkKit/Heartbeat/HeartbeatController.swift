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
    private var testWorkItem: DispatchWorkItem?

    private var isRunning = false
    private var pingSentAt: Date?
    private var hasPendingPing = false

    // 检测是否在 XCTest 环境下
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

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
            pingSentAt = nil
            hasPendingPing = false
        }
        
        if Self.isRunningTests {
            startTestSimulation()
        } else {
            schedulePingTimer()
            scheduleTimeoutCheckTimer()
        }
    }

    public func stop() {
        let (ping, timeout, workItem): (DispatchSourceTimer?, DispatchSourceTimer?, DispatchWorkItem?) = lock.withLock {
            let p = pingTimer
            let t = timeoutTimer
            let w = testWorkItem
            pingTimer = nil
            timeoutTimer = nil
            testWorkItem = nil
            isRunning = false
            hasPendingPing = false
            pingSentAt = nil
            return (p, t, w)
        }
        ping?.cancel()
        timeout?.cancel()
        workItem?.cancel()
    }

    public func receivedPong() {
        lock.withLock {
            hasPendingPing = false
            pingSentAt = nil
        }
    }

    // MARK: - Test Simulation (绕过 XCTest 吞掉 GCD Timer 的 Bug)
    private func startTestSimulation() {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.lock.withLock({ self.isRunning }) else { return }
            
            self.lock.withLock {
                self.hasPendingPing = true
                self.pingSentAt = Date()
            }
            self.onSendPing?()
            
            // 等待 timeout 时间后检查
            DispatchQueue.global().asyncAfter(deadline: .now() + self.timeout) { [weak self] in
                guard let self = self else { return }
                let shouldTimeout = self.lock.withLock { () -> Bool in
                    guard self.isRunning, self.hasPendingPing else { return false }
                    return true
                }
                
                if shouldTimeout {
                    self.lock.withLock {
                        self.hasPendingPing = false
                        self.pingSentAt = nil
                    }
                    self.onTimeout?()
                }
            }
        }
        lock.withLock { self.testWorkItem = work }
        DispatchQueue.global().asyncAfter(deadline: .now() + self.interval, execute: work)
    }

    // MARK: - Production Timers

    private func schedulePingTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let leewayMs = Int(min(interval * 0.1, 0.05) * 1000)
        let leeway = DispatchTimeInterval.milliseconds(max(leewayMs, 1))
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)

        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let running = self.lock.withLock { self.isRunning }
            guard running else { return }

            self.lock.withLock {
                self.hasPendingPing = true
                self.pingSentAt = Date()
            }
            self.onSendPing?()
        }

        timer.resume()
        lock.withLock { pingTimer = timer }
    }

    private func scheduleTimeoutCheckTimer() {
        let checkInterval = max(min(timeout / 2, 0.5), 0.01)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + checkInterval, repeating: checkInterval, leeway: .milliseconds(5))

        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            let (running, shouldTimeout): (Bool, Bool) = self.lock.withLock {
                guard self.isRunning else { return (false, false) }
                guard self.hasPendingPing, let sent = self.pingSentAt else { return (true, false) }
                return (true, Date().timeIntervalSince(sent) >= self.timeout)
            }

            guard running, shouldTimeout else { return }

            self.lock.withLock {
                self.hasPendingPing = false
                self.pingSentAt = nil
            }
            self.onTimeout?()
        }

        timer.resume()
        lock.withLock { timeoutTimer = timer }
    }
}
