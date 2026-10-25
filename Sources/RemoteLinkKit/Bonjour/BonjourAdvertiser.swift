//
//  BonjourAdvertiser.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
#if canImport(Network)
import Network

/// NWListener 挂 Bonjour 广播
/// TODO: 实现
public final class BonjourAdvertiser: @unchecked Sendable {
    public init(serviceName: String,
                serviceType: String = "_runprocess._tcp",
                port: Int) {
        // TODO
    }

    public func start() {}
    public func stop() {}
}
#endif
