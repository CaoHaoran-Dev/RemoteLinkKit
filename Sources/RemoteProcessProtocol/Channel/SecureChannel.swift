//
//  SecureChannel.swift
//  RemoteProcessProtocol
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
import RemoteLinkKit

/// 协议层胶水：把 ClientMessage / ServerMessage 变成
/// 「编码 → 加密 → 封帧 → 走 transport」的字节流，反向解帧 → 解密 → 解码。
public actor SecureChannel {

    // MARK: - Callbacks

    private var _onClientMessage: (@Sendable (ClientMessage) -> Void)?
    private var _onServerMessage: (@Sendable (ServerMessage) -> Void)?
    private var _onError: (@Sendable (Error) -> Void)?

    // MARK: - Private

    private let transport: RemoteConnection
    private let codec: FrameCodec
    private let cipher: CipherSuite
    private let cipherId: UInt16
    private let replayGuard = ReplayGuard()
    private let isClient: Bool
    private var seqCounter: UInt32 = 0

    // MARK: - Init

    public init(transport: RemoteConnection,
                cipher: CipherSuite,
                cipherId: UInt16,
                isClient: Bool) {
        self.transport = transport
        self.cipher = cipher
        self.cipherId = cipherId
        self.isClient = isClient
        self.codec = FrameCodec(cipherId: cipherId)
    }

    // MARK: - Callback Setters

    public func setOnClientMessage(_ handler: (@Sendable (ClientMessage) -> Void)?) {
        _onClientMessage = handler
    }

    public func setOnServerMessage(_ handler: (@Sendable (ServerMessage) -> Void)?) {
        _onServerMessage = handler
    }

    public func setOnError(_ handler: (@Sendable (Error) -> Void)?) {
        _onError = handler
    }

    // MARK: - Start

    /// 绑定 transport 回调，开始接收
    public func start() {
        transport.onReceive = { [weak self] data in
            guard let self = self else { return }
            Task { await self.handleIncoming(data) }
        }
    }

    // MARK: - Send

    public func send(_ message: ClientMessage) async throws {
        let payload = try MessageCodec.encode(message)
        try await sendFrame(type: message.frameType, plaintext: payload)
    }

    public func send(_ message: ServerMessage) async throws {
        let payload = try MessageCodec.encode(message)
        try await sendFrame(type: message.frameType, plaintext: payload)
    }

    private func sendFrame(type: FrameType, plaintext: Data) async throws {
        let seq = nextSeq()
        let headerAAD = Frame(
            type: type,
            cipherId: cipherId,
            seq: seq,
            payload: Data()
        ).headerAAD

        let nonce = KeyDerivation.nonce(from: seq)
        let sealed = try cipher.seal(plaintext, nonce: nonce, aad: headerAAD)

        let frame = Frame(type: type, cipherId: cipherId, seq: seq, payload: sealed)
        let bytes = codec.encode(frame)
        try await transport.send(bytes)
    }

    private func nextSeq() -> UInt32 {
        let s = seqCounter
        seqCounter &+= 1
        return s
    }

    // MARK: - Receive

    private func handleIncoming(_ data: Data) async {
        do {
            let frames = try codec.decode(data)
            for frame in frames {
                try processFrame(frame)
            }
        } catch {
            _onError?(error)
        }
    }

    private func processFrame(_ frame: Frame) throws {
        guard replayGuard.accept(frame.seq) else {
            throw FrameError.sequenceReplayed(frame.seq)
        }

        let nonce = KeyDerivation.nonce(from: frame.seq)
        let plaintext = try cipher.open(frame.payload, nonce: nonce, aad: frame.headerAAD)

        if isClient {
            let msg = try MessageCodec.decodeServer(plaintext)
            _onServerMessage?(msg)
        } else {
            let msg = try MessageCodec.decodeClient(plaintext)
            _onClientMessage?(msg)
        }
    }
}
