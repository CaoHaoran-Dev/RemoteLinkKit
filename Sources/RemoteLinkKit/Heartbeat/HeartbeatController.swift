//
//  HeartbeatController.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 定时 ping，超时回调。不关心 pong 的业务含义。
public final class HeartbeatController: @unchecked Sendable {
    public var interval: TimeInterval
    public var timeout: TimeInterval
    public var onSendPing: (@Sendable () -> Void)?
    public var onTimeout: (@Sendable () -> Void)?

    private var timer: Timer?

    public init(interval: TimeInterval = 30, timeout: TimeInterval = 10) {
        self.interval = interval
        self.timeout = timeout
    }

    public func start() {
        // TODO
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func receivedPong() {
        // TODO: 重置超时计时
    }
}
