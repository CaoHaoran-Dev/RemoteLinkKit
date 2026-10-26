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

    /// 串行化发送，保证 seq 分配顺序与实际写出顺序一致。
    private var sendTail: Task<Void, Never>?

    /// 发送链上出现过的错误。一旦设置，后续发送直接失败，
    /// 避免"某个 seq 的帧没发出去、后续帧继续发"造成状态不一致。
    private var sendFailure: Error?

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
        // 发送链已损坏，直接失败，不再消耗 seq。
        if let failure = sendFailure {
            throw failure
        }

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

        do {
            try await enqueueSend(bytes)
        } catch {
            // 记录首次失败；后续发送都会抛这个错误。
            if sendFailure == nil {
                sendFailure = error
            }
            throw error
        }
    }

    /// 串行化发送：前一个发送完成后才继续，保证字节写出顺序与 seq 顺序一致。
    private func enqueueSend(_ bytes: Data) async throws {
        let previous = sendTail
        let transport = self.transport

        let task = Task<Void, Error> {
            // 等待前一个发送完成；前一个失败也已记录在 sendFailure，
            // 这里不再重复抛，只保证顺序。
            _ = await previous?.result
            try await transport.send(bytes)
        }
        sendTail = Task { _ = try? await task.value }

        try await task.value
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
            guard msg.frameType == frame.type else {
                throw MessageError.mismatchedFrameType(expected: msg.frameType, actual: frame.type)
            }
            _onServerMessage?(msg)
        } else {
            let msg = try MessageCodec.decodeClient(plaintext)
            guard msg.frameType == frame.type else {
                throw MessageError.mismatchedFrameType(expected: msg.frameType, actual: frame.type)
            }
            _onClientMessage?(msg)
        }
    }
}
