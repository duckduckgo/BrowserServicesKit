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

public struct HTTPSUpgradeError: Error {}

public final class HTTPSUpgrade {
    
    private let dataReloadLock = NSLock()
    private let store: HTTPSUpgradeStore
    private let privacyManager: PrivacyConfigurationManaging
   
    private var bloomFilter: BloomFilterWrapper?
    
    public init(store: HTTPSUpgradeStore,
                privacyManager: PrivacyConfigurationManaging) {
        self.store = store
        self.privacyManager = privacyManager
    }

    @MainActor
    public func upgrade(url: URL) async -> Result<URL, HTTPSUpgradeError> {
        guard url.isHttp,
              let host = url.host,
              !shouldExcludeDomain(host),
              isFeatureEnabled(forHost: host, privacyConfig: privacyConfig) else {
                  return .failure(.init())
        }
        
        waitForAnyReloadsToComplete()
        let isUpgradable = isInUpgradeList(host: host)
        if isUpgradable, let upgradedUrl = url.toHttps() {
            return .success(upgradedUrl)
        }
        return .failure(.init())
    }
    
    private var privacyConfig: PrivacyConfiguration { privacyManager.privacyConfig }
    
    private func shouldExcludeDomain(_ host: String) -> Bool { store.hasExcludedDomain(host) }
    
    private func isFeatureEnabled(forHost host: String, privacyConfig: PrivacyConfiguration) -> Bool {
        privacyConfig.isFeature(.httpsUpgrade, enabledForDomain: host)
    }
    
    private func waitForAnyReloadsToComplete() {
        // wait for lock (by locking and unlocking) before continuing
        dataReloadLock.lock()
        dataReloadLock.unlock()
    }
    
    private func isInUpgradeList(host: String) -> Bool {
        guard let bloomFilter = bloomFilter else { return false }
        return bloomFilter.contains(host)
    }
    
    public func loadDataAsync() {
        DispatchQueue.global(qos: .background).async {
            self.loadData()
        }
    }
    
    public func loadData() {
        if !dataReloadLock.try() {
            os_log("Reload already in progress", type: .debug)
            return
        }
        bloomFilter = store.bloomFilter
        dataReloadLock.unlock()
    }
    
}
