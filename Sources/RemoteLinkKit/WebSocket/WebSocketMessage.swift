//
//  WebSocketMessage.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 屏蔽 URLSession 和 NWConnection 两种底层消息类型
public enum WebSocketMessage: Sendable {
    case data(Data)
    case string(String)
}
