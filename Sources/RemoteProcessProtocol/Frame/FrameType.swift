//
//  FrameType.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 帧类型
public enum FrameType: UInt8, Sendable {
    /// 客户端 → 服务端：执行命令
    case exec = 0x01
    /// 客户端 → 服务端：取消执行
    case cancel = 0x02
    /// 客户端 → 服务端 / 服务端 → 客户端：心跳
    case ping = 0x03
    /// 服务端 → 客户端：心跳回应
    case pong = 0x04
    /// 服务端 → 客户端：命令输出
    case output = 0x05
    /// 服务端 → 客户端：命令完成
    case done = 0x06
    /// 服务端 → 客户端：错误
    case error = 0x07
    /// 服务端 → 客户端：cwd 变更通知
    case cwd = 0x08
    /// 双向：握手 / 密钥协商
    case handshake = 0x09
    /// 双向：认证
    case auth = 0x0A
}
