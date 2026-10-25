//
//  RemoteConnection.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 一条远程连接的抽象。只管字节收发和状态，不关心帧语义。
public protocol RemoteConnection: AnyObject, Sendable {
    var state: ConnectionState { get }
    var onStateChange: (@Sendable (ConnectionState) -> Void)? { get set }
    var onReceive: (@Sendable (Data) -> Void)? { get set }

    func connect() async throws
    func send(_ data: Data) async throws
    func close()
}
