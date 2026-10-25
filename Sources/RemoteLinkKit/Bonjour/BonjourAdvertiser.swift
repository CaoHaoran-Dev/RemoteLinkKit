//
//  BonjourAdvertiser.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
#if canImport(Network)
import Network

/// 通过 NWListener 挂 Bonjour 广播
public final class BonjourAdvertiser: @unchecked Sendable {

    // MARK: - Public Callbacks

    public var onReady: (@Sendable (Int) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    // MARK: - Private

    private let serviceName: String
    private let serviceType: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.remotelinkkit.bonjour.advertiser")

    private let lock = NSLock()
    private var listener: NWListener?

    // MARK: - Init

    public init(serviceName: String,
                serviceType: String = "_runprocess._tcp",
                port: UInt16) {
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.port = port
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    public func start() {
        guard NWEndpoint.Port(rawValue: port) != nil else {
            onError?(NWError.posix(.EINVAL))
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = true

            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            let txt = NWTXTRecord([
                "version": "1",
                "name": serviceName
            ])
            listener.service = NWListener.Service(
                name: serviceName,
                type: serviceType,
                domain: nil,
                txtRecord: txt
            )

            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let p = listener.port?.rawValue {
                        self.onReady?(Int(p))
                    }
                case .failed(let error):
                    self.onError?(error)
                default:
                    break
                }
            }

            listener.start(queue: queue)

            lock.withLock { self.listener = listener }
        } catch {
            onError?(error)
        }
    }

    public func stop() {
        let listener: NWListener? = lock.withLock {
            let l = self.listener
            self.listener = nil
            return l
        }
        listener?.cancel()
    }
}
#endif
