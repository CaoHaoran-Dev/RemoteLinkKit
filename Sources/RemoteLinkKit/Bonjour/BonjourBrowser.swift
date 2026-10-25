//
//  BonjourBrowser.swift
//  RemoteLinkKit
//
//  Created by Haoran on 2026/10/25.
//

import Foundation
#if canImport(Network)
import Network

/// NWBrowser 封装，发现 _runprocess._tcp 服务
public final class BonjourBrowser: @unchecked Sendable {

    // MARK: - Service

    public struct Service: Sendable {
        public let name: String
        public let endpoint: NWEndpoint
    }

    // MARK: - Public Callbacks

    public var onFound: (@Sendable (Service) -> Void)?
    public var onLost: (@Sendable (Service) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    // MARK: - Private

    private let serviceType: String
    private let queue = DispatchQueue(label: "com.remotelinkkit.bonjour.browser")

    private let lock = NSLock()
    private var browser: NWBrowser?

    // MARK: - Init

    public init(serviceType: String = "_runprocess._tcp") {
        self.serviceType = serviceType
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    public func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                self.onError?(error)
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            _ = results
            for change in changes {
                switch change {
                case .added(let result):
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.onFound?(Service(name: name, endpoint: result.endpoint))
                    }
                case .removed(let result):
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.onLost?(Service(name: name, endpoint: result.endpoint))
                    }
                default:
                    break
                }
            }
        }

        browser.start(queue: queue)

        lock.withLock { self.browser = browser }
    }

    public func stop() {
        let browser: NWBrowser? = lock.withLock {
            let b = self.browser
            self.browser = nil
            return b
        }
        browser?.cancel()
    }

    // MARK: - Endpoint Helpers

    /// 从 NWEndpoint 提取 host 和 port
    /// 注意：NWEndpoint 不直接给 host/port，实际地址由使用方建立 NWConnection 时解析。
    public static func resolve(_ endpoint: NWEndpoint) -> (host: String, port: Int)? {
        guard case .service = endpoint else {
            return nil
        }
        return nil
    }
}
#endif
