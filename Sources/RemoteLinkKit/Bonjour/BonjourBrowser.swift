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

    // MARK: - Endpoint Resolution

    /// 解析 Bonjour endpoint 为 host + port。
    ///
    /// `NWEndpoint` 不直接暴露 host/port，需要建立 `NWConnection` 后读取
    /// `currentPath?.remoteEndpoint`。连接会立即取消，仅用于解析。
    public static func resolve(_ endpoint: NWEndpoint,
                               timeout: TimeInterval = 5) async throws -> (host: String, port: Int) {
        guard case .service = endpoint else {
            throw NWError.posix(.EINVAL)
        }

        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: params)

        return try await withThrowingTaskGroup(of: (String, Int).self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(String, Int), Error>) in
                    let resumed = LockedFlag()

                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            guard let remote = connection.currentPath?.remoteEndpoint else {
                                if resumed.trySet() {
                                    cont.resume(throwing: NWError.posix(.EADDRNOTAVAIL))
                                }
                                connection.cancel()
                                return
                            }
                            if case .hostPort(let host, let port) = remote {
                                if resumed.trySet() {
                                    cont.resume(returning: ("\(host)", Int(port.rawValue)))
                                }
                            } else {
                                if resumed.trySet() {
                                    cont.resume(throwing: NWError.posix(.EADDRNOTAVAIL))
                                }
                            }
                            connection.cancel()
                        case .failed(let error):
                            if resumed.trySet() { cont.resume(throwing: error) }
                            connection.cancel()
                        case .cancelled:
                            if resumed.trySet() { cont.resume(throwing: NWError.posix(.ECANCELED)) }
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global())
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NWError.posix(.ETIMEDOUT)
            }

            defer { group.cancelAll() }
            let result = try await group.next()!
            return result
        }
    }

    /// 简单的一次性标志，避免 continuation 被 resume 两次。
    private final class LockedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func trySet() -> Bool {
            lock.withLock {
                if value { return false }
                value = true
                return true
            }
        }
    }
}
#endif
