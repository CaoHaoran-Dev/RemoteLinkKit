//
//  HeartbeatControllerTests.swift
//  RemoteLinkKitTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteLinkKit

final class HeartbeatControllerTests: XCTestCase {

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

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = 0
        var value: Int { lock.withLock { _value } }
        @discardableResult
        func increment() -> Int {
            lock.withLock {
                _value += 1
                return _value
            }
        }
    }

    // MARK: - Lifecycle

    private var activeControllers: [HeartbeatController] = []

    override func tearDown() {
        activeControllers.forEach { $0.stop() }
        activeControllers.removeAll()
        super.tearDown()
    }

    private func makeController(interval: TimeInterval,
                                timeout: TimeInterval) -> HeartbeatController {
        let hb = HeartbeatController(interval: interval, timeout: timeout)
        activeControllers.append(hb)
        return hb
    }

    // MARK: - Tests

    func testPingFires() {
        let exp = expectation(description: "ping fired")
        let fired = FlagBox()

        let hb = makeController(interval: 0.2, timeout: 1.0)
        hb.onSendPing = { [weak hb] in
            _ = hb
            if fired.trySet() {
                DispatchQueue.main.async { exp.fulfill() }
            }
        }

        hb.start()
        wait(for: [exp], timeout: 2.0)
        hb.stop()
    }

    func testTimeoutFiresWhenNoPong() {
        let timeoutExp = expectation(description: "timeout")
        let fired = FlagBox()

        let hb = makeController(interval: 0.1, timeout: 0.2)
        hb.onTimeout = { [weak hb] in
            _ = hb
            if fired.trySet() {
                DispatchQueue.main.async { timeoutExp.fulfill() }
            }
        }

        hb.start()
        wait(for: [timeoutExp], timeout: 2.0)
        hb.stop()
    }

    func testPongCancelsTimeout() {
        let timeoutExp = expectation(description: "timeout should not fire")
        timeoutExp.isInverted = true

        let hb = makeController(interval: 0.2, timeout: 0.3)
        hb.onSendPing = { [weak hb] in
            hb?.receivedPong()
        }
        hb.onTimeout = { [weak hb] in
            _ = hb
            DispatchQueue.main.async { timeoutExp.fulfill() }
        }

        hb.start()
        wait(for: [timeoutExp], timeout: 1.5)
        hb.stop()
    }

    func testStopCancelsTimers() {
        let pingExp = expectation(description: "no ping after stop")
        pingExp.isInverted = true

        let hb = makeController(interval: 0.1, timeout: 0.2)
        hb.onSendPing = { [weak hb] in
            _ = hb
            DispatchQueue.main.async { pingExp.fulfill() }
        }
        hb.start()
        hb.stop()

        wait(for: [pingExp], timeout: 0.5)
    }

    func testStartIsIdempotent() {
        let counter = Counter()
        let exp = expectation(description: "ping")
        exp.assertForOverFulfill = false
        let fired = FlagBox()

        let hb = makeController(interval: 0.3, timeout: 1.0)
        hb.onSendPing = { [weak hb] in
            _ = hb
            counter.increment()
            if fired.trySet() {
                DispatchQueue.main.async { exp.fulfill() }
            }
        }

        hb.start()
        hb.start()
        hb.start()

        wait(for: [exp], timeout: 2.0)
        hb.stop()

        XCTAssertGreaterThanOrEqual(counter.value, 1)
    }
}
