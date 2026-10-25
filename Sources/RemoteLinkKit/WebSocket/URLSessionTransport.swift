//
//  URLSessionTransport.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation

/// 客户端 WebSocket 实现，基于 URLSessionWebSocketTask
public final class URLSessionTransport: RemoteConnection, @unchecked Sendable {
    public private(set) var state: ConnectionState = .idle
    public var onStateChange: (@Sendable (ConnectionState) -> Void)?
    public var onReceive: (@Sendable (Data) -> Void)?

    private let config: ConnectionConfig
    private let transform: ConnectionTransform
    private var task: URLSessionWebSocketTask?

    public init(config: ConnectionConfig,
                transform: ConnectionTransform = PassthroughTransform()) {
        self.config = config
        self.transform = transform
    }

    public func connect() async throws {
        guard let url = config.url else {
            throw ConnectionError.invalidURL
        }
        transition(.connecting)

        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        self.task = task
        transition(.connected)
        receiveLoop()
    }

    public func send(_ data: Data) async throws {
        guard let task = task else { throw ConnectionError.notConnected }
        let payload = try transform.encode(data)
        do {
            try await task.send(.data(payload))
        } catch {
            throw ConnectionError.sendFailed(underlying: error)
        }
    }

    public func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        transition(.closed(reason: nil))
    }

    private func receiveLoop() {
        guard let task = task else { return }
        task.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    if let decoded = try? self.transform.decode(data) {
                        self.onReceive?(decoded)
                    }
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let decoded = try? self.transform.decode(data) {
                        self.onReceive?(decoded)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure:
                self.transition(.closed(reason: "receive failed"))
            }
        }
    }

    private func transition(_ newState: ConnectionState) {
        state = newState
        onStateChange?(newState)
    }
}
