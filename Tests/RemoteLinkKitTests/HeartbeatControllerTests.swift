//
//  HeartbeatControllerTests.swift
//  RemoteLinkKitTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteLinkKit

final class HeartbeatControllerTests: XCTestCase {

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        func set() { lock.withLock { _value = true } }
        var value: Bool { lock.withLock { _value } }
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

    private var activeControllers: [HeartbeatController] = []

    override func tearDown() {
        activeControllers.forEach { $0.stop() }
        activeControllers.removeAll()
        super.tearDown()
    }

    private func makeController(interval: TimeInterval, timeout: TimeInterval) -> HeartbeatController {
        let hb = HeartbeatController(interval: interval, timeout: timeout)
        activeControllers.append(hb)
        return hb
    }

    func testPingFires() {
        let fired = Flag()
        let hb = makeController(interval: 0.1, timeout: 1.0)

        hb.onSendPing = { fired.set() }

        hb.start()
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertTrue(fired.value, "Ping should have fired")
        hb.stop()
    }

    func testTimeoutFiresWhenNoPong() {
        let fired = Flag()
        let hb = makeController(interval: 0.1, timeout: 0.2)

        hb.onSendPing = {}
        hb.onTimeout = { fired.set() }

        hb.start()
        // interval(0.1) + timeout(0.2) = 0.3，我们等 0.6 绝对稳
        Thread.sleep(forTimeInterval: 0.6)

        XCTAssertTrue(fired.value, "Timeout should have fired because no pong was received")
        hb.stop()
    }

    func testPongCancelsTimeout() {
        let fired = Flag()
        let hb = makeController(interval: 0.1, timeout: 0.2)

        hb.onSendPing = { [weak hb] in hb?.receivedPong() }
        hb.onTimeout = { fired.set() }

        hb.start()
        Thread.sleep(forTimeInterval: 0.6)

        XCTAssertFalse(fired.value, "Timeout should NOT fire because pong was received")
        hb.stop()
    }

    /// 新增：pong 在 ping 之后、timeout 之前到达，超时不应触发。
    func testLateButWithinTimeoutPongCancelsTimeout() {
        let fired = Flag()
        let hb = makeController(interval: 0.1, timeout: 0.4)

        hb.onSendPing = {
            // 延迟 0.15s 再回 pong，仍在 timeout(0.4) 内
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak hb] in
                hb?.receivedPong()
            }
        }
        hb.onTimeout = { fired.set() }

        hb.start()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertFalse(fired.value, "Timeout should NOT fire: pong arrived within timeout")
        hb.stop()
    }

    func testStopCancelsTimers() {
        let fired = Flag()
        let hb = makeController(interval: 0.1, timeout: 0.2)

        hb.onSendPing = { fired.set() }

        hb.start()
        hb.stop()

        Thread.sleep(forTimeInterval: 0.4)

        XCTAssertFalse(fired.value, "Ping should not fire after stop()")
    }

    /// 新增：stop 之后不能触发 timeout。
    func testStopCancelsTimeout() {
        let fired = Flag()
        let hb = makeController(interval: 0.1, timeout: 0.1)

        hb.onSendPing = {}
        hb.onTimeout = { fired.set() }

        hb.start()
        hb.stop()

        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertFalse(fired.value, "Timeout should not fire after stop()")
    }

    func testStartIsIdempotent() {
        let counter = Counter()
        let hb = makeController(interval: 0.1, timeout: 1.0)

        hb.onSendPing = { counter.increment() }

        hb.start()
        hb.start()
        hb.start()

        Thread.sleep(forTimeInterval: 0.4)

        XCTAssertGreaterThanOrEqual(counter.value, 1)
        XCTAssertLessThan(counter.value, 10, "Multiple start() calls should not spawn duplicate timers")
        hb.stop()
    }
}
