//
//  ConnectionTransform.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 发送前 / 接收后的字节变换。加密层、帧编解码都从这里注入。
public protocol ConnectionTransform: Sendable {
    func encode(_ data: Data) throws -> Data
    func decode(_ data: Data) throws -> Data
}

/// 直通，不做任何变换
public struct PassthroughTransform: ConnectionTransform {
    public init() {}
    public func encode(_ data: Data) throws -> Data { data }
    public func decode(_ data: Data) throws -> Data { data }
}
