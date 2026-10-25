//
//  ReconnectPolicy.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 指数退避策略，只给策略，不自动重连
public struct ReconnectPolicy: Sendable {
    public var initialDelay: TimeInterval
    public var multiplier: Double
    public var maxDelay: TimeInterval
    public var maxAttempts: Int

    public init(initialDelay: TimeInterval = 1,
                multiplier: Double = 2,
                maxDelay: TimeInterval = 30,
                maxAttempts: Int = 10) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt < maxAttempts else { return nil }
        let raw = initialDelay * pow(multiplier, Double(attempt))
        return min(raw, maxDelay)
    }
}
