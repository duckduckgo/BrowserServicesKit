//
//  SubscriptionFeatureMappingCache.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Networking

typealias SubscriptionFeatureMapping = [String: [SubscriptionEntitlement]]

public protocol SubscriptionFeatureMappingCache {
    func subscriptionFeatures(for subscriptionIdentifier: String) async -> [SubscriptionEntitlement]
}

public final class DefaultSubscriptionFeatureMappingCache: SubscriptionFeatureMappingCache {

    private let subscriptionEndpointService: SubscriptionEndpointService
    private let userDefaults: UserDefaults
    private var subscriptionFeatureMapping: SubscriptionFeatureMapping?

    public init(subscriptionEndpointService: SubscriptionEndpointService, userDefaults: UserDefaults) {
        self.subscriptionEndpointService = subscriptionEndpointService
        self.userDefaults = userDefaults
    }

    public func subscriptionFeatures(for subscriptionIdentifier: String) async -> [SubscriptionEntitlement] {
        Logger.subscriptionFeatureMappingCache.debug("\(#function) \(subscriptionIdentifier)")
        let features: [SubscriptionEntitlement]

        if let subscriptionFeatures = currentSubscriptionFeatureMapping[subscriptionIdentifier] {
            Logger.subscriptionFeatureMappingCache.debug("- got cached features")
            features = subscriptionFeatures
        } else if let subscriptionFeatures = await fetchRemoteFeatures(for: subscriptionIdentifier) {
            Logger.subscriptionFeatureMappingCache.debug("- fetching features from BE API")
            features = subscriptionFeatures
            updateCachedFeatureMapping(with: subscriptionFeatures, for: subscriptionIdentifier)
        } else {
            Logger.subscriptionFeatureMappingCache.error("- Error: using fallback")
            features = fallbackFeatures
        }

        return features
    }

    // MARK: - Current feature mapping

    private var currentSubscriptionFeatureMapping: SubscriptionFeatureMapping {
        Logger.subscriptionFeatureMappingCache.debug("\(#function)")
        let featureMapping: SubscriptionFeatureMapping

        if let cachedFeatureMapping {
            Logger.subscriptionFeatureMappingCache.debug("got cachedFeatureMapping")
            featureMapping = cachedFeatureMapping
        } else if let storedFeatureMapping {
            Logger.subscriptionFeatureMappingCache.debug("have to fetchStoredFeatureMapping")
            featureMapping = storedFeatureMapping
            updateCachedFeatureMapping(to: featureMapping)
        } else {
            Logger.subscriptionFeatureMappingCache.debug("creating a new one!")
            featureMapping = SubscriptionFeatureMapping()
            updateCachedFeatureMapping(to: featureMapping)
        }

        return featureMapping
    }

    // MARK: - Cached subscription feature mapping

    private var cachedFeatureMapping: SubscriptionFeatureMapping?

    private func updateCachedFeatureMapping(to featureMapping: SubscriptionFeatureMapping) {
        cachedFeatureMapping = featureMapping
    }

    private func updateCachedFeatureMapping(with features: [SubscriptionEntitlement], for subscriptionIdentifier: String) {
        var updatedFeatureMapping = cachedFeatureMapping ?? SubscriptionFeatureMapping()
        updatedFeatureMapping[subscriptionIdentifier] = features

        self.cachedFeatureMapping = updatedFeatureMapping
        self.storedFeatureMapping = updatedFeatureMapping
    }

    // MARK: - Stored subscription feature mapping

    static private let subscriptionFeatureMappingKey = "com.duckduckgo.subscription.featuremapping"
    private let subscriptionFeatureMappingQueue = DispatchQueue(label: "com.duckduckgo.subscription.featuremapping.queue")

    dynamic var storedFeatureMapping: SubscriptionFeatureMapping? {
        get {
            var result: SubscriptionFeatureMapping?
            subscriptionFeatureMappingQueue.sync {
                guard let data = userDefaults.data(forKey: Self.subscriptionFeatureMappingKey) else { return }
                do {
                    result = try JSONDecoder().decode(SubscriptionFeatureMapping?.self, from: data)
                } catch {
                    Logger.subscriptionFeatureMappingCache.fault("Errored while decoding feature mapping")
                    assertionFailure("Errored while decoding feature mapping")
                }
            }
            return result
        }

        set {
            subscriptionFeatureMappingQueue.sync {
                do {
                    let data = try JSONEncoder().encode(newValue)
                    userDefaults.set(data, forKey: Self.subscriptionFeatureMappingKey)
                } catch {
                    Logger.subscriptionFeatureMappingCache.fault("Errored while encoding feature mapping")
                    assertionFailure("Errored while encoding feature mapping")
                }
            }
        }
    }

    // MARK: - Remote subscription feature mapping

    private func fetchRemoteFeatures(for subscriptionIdentifier: String) async -> [SubscriptionEntitlement]? {
        do {
            let response = try await subscriptionEndpointService.getSubscriptionFeatures(for: subscriptionIdentifier)
            Logger.subscriptionFeatureMappingCache.debug("-- Fetched features for `\(subscriptionIdentifier)`: \(response.features)")
            return response.features
        } catch {
            return nil
        }
    }

    // MARK: - Fallback subscription feature mapping

    private let fallbackFeatures: [SubscriptionEntitlement] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration]
}
