//
//  ContentBlockerDebugEvents.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import BloomFilterWrapper

public enum HTTPSUpgradeError: Error {
    case badUrl
    case nonHttp
    case domainExcluded
    case featureDisabled
    case nonUpgradable
    case bloomFilterTaskNotSet
    case noBloomFilter
}

public final class HTTPSUpgrade {

    @MainActor
    private var dataReloadTask: Task<BloomFilterWrapper?, Never>?
    private let store: HTTPSUpgradeStore
    private let privacyManager: PrivacyConfigurationManaging

    @MainActor
    private var bloomFilter: BloomFilterWrapper?

    public init(store: HTTPSUpgradeStore,
                privacyManager: PrivacyConfigurationManaging) {
        self.store = store
        self.privacyManager = privacyManager
    }

    @MainActor
    public func upgrade(url: URL) async -> Result<URL, HTTPSUpgradeError> {
        guard url.isHttp else { return .failure(.nonHttp) }
        guard let host = url.host else { return .failure(.badUrl) }
        guard shouldExcludeDomain(host) == false else { return .failure(.domainExcluded) }
        guard isFeatureEnabled(forHost: host, privacyConfig: privacyConfig) else { return .failure(.featureDisabled) }

        switch await self.isDomainInUpgradeList(host) {
        case .success(true):
            guard let upgradedUrl = url.toHttps() else { return .failure(.badUrl) }
            return .success(upgradedUrl)

        case .success(false):
            return .failure(.nonUpgradable)

        case .failure(let error):
            return .failure(error)
        }
    }


    private var privacyConfig: PrivacyConfiguration { privacyManager.privacyConfig }

    private func shouldExcludeDomain(_ host: String) -> Bool { store.hasExcludedDomain(host) }

    private func isFeatureEnabled(forHost host: String, privacyConfig: PrivacyConfiguration) -> Bool {
        privacyConfig.isFeature(.httpsUpgrade, enabledForDomain: host)
    }

    @MainActor
    private func isDomainInUpgradeList(_ host: String) async -> Result<Bool, HTTPSUpgradeError> {
        let bloomFilter: BloomFilterWrapper
        if let bf = self.bloomFilter {
            bloomFilter = bf
        } else if let dataReloadTask {
            guard let bf = await dataReloadTask.value else {
                return .failure(.noBloomFilter)
            }
            bloomFilter = bf
        } else {
            return .failure(.bloomFilterTaskNotSet)
        }

        let result = bloomFilter.contains(host)
        return .success(result)
    }

    public func loadDataAsync() {
        Task {
            await self.loadData()
        }
    }

    @MainActor
    public func loadData() async {
        guard dataReloadTask == nil else {
            os_log("Reload already in progress", type: .debug)
            return
        }
        dataReloadTask = Task.detached { [store] in
            return store.bloomFilter
        }
        self.bloomFilter = await dataReloadTask!.value
        self.dataReloadTask = nil
    }

}

