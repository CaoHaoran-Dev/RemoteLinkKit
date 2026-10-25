//
//  NWTransport.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
#if canImport(Network)
import Network

/// 服务端 WebSocket 实现，基于 NWConnection + NWProtocolWebSocket
/// TODO: 实现 RemoteConnection
public final class NWTransport: RemoteConnection, @unchecked Sendable {
    public private(set) var state: ConnectionState = .idle
    public var onStateChange: (@Sendable (ConnectionState) -> Void)?
    public var onReceive: (@Sendable (Data) -> Void)?

    private let connection: NWConnection
    private let transform: ConnectionTransform

    public init(connection: NWConnection,
                transform: ConnectionTransform = PassthroughTransform()) {
        self.connection = connection
        self.transform = transform
    }

    public func connect() async throws {
        // TODO
    }

    public func send(_ data: Data) async throws {
        // TODO
    }

    public func close() {
        connection.cancel()
        state = .closed(reason: nil)
        onStateChange?(state)
    }
}
#endif
