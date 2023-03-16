//
//  FeatureFlagger.swift
//  DuckDuckGo
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

public protocol FeatureFlagSourceProviding {
    var source: FeatureFlagSource { get }
}

public enum FeatureFlagSource {
    case disabled
    case internalOnly
    case remote((PrivacyConfiguration) -> Bool)
}

public protocol FeatureFlagger {
    func isFeatureOn<F>(_ feature: F) -> Bool where F: FeatureFlagSourceProviding
 }

public class DefaultFeatureFlagger: FeatureFlagger {
    private let internalUserDecider: InternalUserDecider
    private let privacyConfig: PrivacyConfiguration

    public init(internalUserDecider: InternalUserDecider, privacyConfig: PrivacyConfiguration) {
        self.internalUserDecider = internalUserDecider
        self.privacyConfig = privacyConfig
    }

    public func isFeatureOn<F>(_ feature: F) -> Bool where F: FeatureFlagSourceProviding {
        switch feature.source {
        case .disabled:
            return false
        case .internalOnly:
            return internalUserDecider.isInternalUser
        case .remote(let configHandler):
            return configHandler(privacyConfig)
        }
    }
}
