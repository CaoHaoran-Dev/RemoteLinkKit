//
//  BonjourBrowser.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
#if canImport(Network)
import Network

/// NWBrowser 封装，发现 _runprocess._tcp
/// TODO: 实现
public final class BonjourBrowser: @unchecked Sendable {
    public struct Service: Sendable {
        public let name: String
        public let endpoint: NWEndpoint
    }

    public var onFound: (@Sendable (Service) -> Void)?
    public var onLost: (@Sendable (Service) -> Void)?

    public init(serviceType: String = "_runprocess._tcp") {
        // TODO
    }

    public func start() {}
    public func stop() {}
}
#endif
