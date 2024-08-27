//
//  DefaultConfigurationManager.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import os.log
import Combine
import Common
import Persistence
import PixelKit

public extension Logger {
    static var config: Logger = { Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "Configuration") }()
}

open class DefaultConfigurationManager: NSObject {
    public enum Error: Swift.Error {

        case timeout
        case bloomFilterSpecNotFound
        case bloomFilterBinaryNotFound
        case bloomFilterPersistenceFailed
        case bloomFilterExclusionsNotFound
        case bloomFilterExclusionsPersistenceFailed

        public func withUnderlyingError(_ underlyingError: Swift.Error) -> Swift.Error {
            let nsError = self as NSError
            return NSError(domain: nsError.domain, code: nsError.code, userInfo: [NSUnderlyingErrorKey: underlyingError])
        }

    }

    public enum Constants {

        public static let downloadTimeoutSeconds = 60.0 * 5
#if DEBUG
        public static let refreshPeriodSeconds = 60.0 * 2 // 2 minutes
#else
        public static let refreshPeriodSeconds = 60.0 * 30 // 30 minutes
#endif
        public static let retryDelaySeconds = 60.0 * 60 * 1 // 1 hour delay before checking again if something went wrong last time
        public static let refreshCheckIntervalSeconds = 60.0 // check if we need a refresh every minute

        static let lastUpdateDefaultsKey = "configuration.lastUpdateTime"
    }

    private var defaults: KeyValueStoring

    public var fetcher: ConfigurationFetcher

    public init(fetcher: ConfigurationFetcher, defaults: KeyValueStoring = UserDefaults()) {
        self.fetcher = fetcher
        self.defaults = defaults
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    public static let queue: DispatchQueue = DispatchQueue(label: "Configuration Manager")
    public static let filePresenterOperationQueue = OperationQueue()

    open internal(set) var lastUpdateTime: Date {
        get {
            defaults.object(forKey: Constants.lastUpdateDefaultsKey) as? Date ?? .distantPast
        }
        set {
            defaults.set(newValue, forKey: Constants.lastUpdateDefaultsKey)
        }
    }

    private var timerCancellable: AnyCancellable?
    public var lastRefreshCheckTime: Date = Date()

    public func start() {
        Logger.config.debug("Starting configuration refresh timer")
        timerCancellable = Timer.publish(every: Constants.refreshCheckIntervalSeconds, on: .main, in: .default)
            .autoconnect()
            .receive(on: Self.queue)
            .sink(receiveValue: { _ in
                self.lastRefreshCheckTime = Date()
                self.refreshIfNeeded()
            })
        Task {
            await refreshNow()
        }
    }

    /**
     Implement this in the subclass.
     Use this method to fetch neccessary configurations and store them.
     */
    open func refreshNow(isDebug: Bool = false) async {
        fatalError("refreshNow Must be implemented by subclass")
    }

    @discardableResult
    private func refreshIfNeeded() -> Task<Void, Never>? {
        guard isReadyToRefresh else {
            Logger.config.debug("Configuration refresh is not needed at this time")
            return nil
        }
        return Task {
            await refreshNow()
        }
    }

    open var isReadyToRefresh: Bool { Date().timeIntervalSince(lastUpdateTime) > Constants.refreshPeriodSeconds }

    public func forceRefresh(isDebug: Bool = false) {
        Task {
            await refreshNow(isDebug: isDebug)
        }
    }

    /// Will try to update the config again at the regularly scheduled interval
    /// **Note:** You must call `start()` on your `ConfigurationManager` instance for this to take effect. It relies on the internal refresh loop of the
    /// `DefaultConfigurationManager` class
    public func tryAgainLater() {
        lastUpdateTime = Date()
    }

    /// Will try to update the config again after `Constants.retryDelaySeconds`
    /// **Note:** You must call `start()` on your `ConfigurationManager` instance for this to take effect. It relies on the internal refresh loop of the
    /// `DefaultConfigurationManager` class
    public func tryAgainSoon() {
        // Set the last update time to in the past so it triggers again sooner
        lastUpdateTime = Date(timeIntervalSinceNow: Constants.refreshPeriodSeconds - Constants.retryDelaySeconds)
    }
}

extension DefaultConfigurationManager: NSFilePresenter {
    open var presentedItemURL: URL? {
        return nil
    }
    
    public var presentedItemOperationQueue: OperationQueue {
        return Self.filePresenterOperationQueue
    }

    open func presentedItemDidChange() { }

}
