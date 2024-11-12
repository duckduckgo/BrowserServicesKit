//
//  FeatureFlagOverrides.swift
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
import Persistence

public protocol FeatureFlagOverridesPersistor {
    func value<Flag: FeatureFlagProtocol>(for flag: Flag) -> Bool?
    func set<Flag: FeatureFlagProtocol>(_ value: Bool?, for flag: Flag)
}

public struct FeatureFlagOverridesUserDefaultsPersistor: FeatureFlagOverridesPersistor {

    public let keyValueStore: KeyValueStoring

    public func value<Flag: FeatureFlagProtocol>(for flag: Flag) -> Bool? {
        let key = key(for: flag)
        return keyValueStore.object(forKey: key) as? Bool
    }

    public func set<Flag: FeatureFlagProtocol>(_ value: Bool?, for flag: Flag) {
        let key = key(for: flag)
        keyValueStore.set(value, forKey: key)
    }

    private func key<Flag: FeatureFlagProtocol>(for flag: Flag) -> String {
        return "localOverride\(flag.rawValue.capitalizedFirstLetter)"
    }
}

private extension String {
    var capitalizedFirstLetter: String {
        return prefix(1).capitalized + dropFirst()
    }
}

public protocol FeatureFlagOverridesHandler {
    func flagDidChange<Flag: FeatureFlagProtocol>(_ featureFlag: Flag, isEnabled: Bool)
}

public final class FeatureFlagOverrides {

    private var persistor: FeatureFlagOverridesPersistor
    private var actionHandler: FeatureFlagOverridesHandler
    weak var featureFlagger: FeatureFlagger?

    public convenience init(
        keyValueStore: KeyValueStoring,
        actionHandler: FeatureFlagOverridesHandler
    ) {
        self.init(
            persistor: FeatureFlagOverridesUserDefaultsPersistor(keyValueStore: keyValueStore),
            actionHandler: actionHandler
        )
    }

    public init(
        persistor: FeatureFlagOverridesPersistor,
        actionHandler: FeatureFlagOverridesHandler
    ) {
        self.persistor = persistor
        self.actionHandler = actionHandler
    }

    public func override<Flag: FeatureFlagProtocol>(for featureFlag: Flag) -> Bool? {
        guard featureFlag.supportsLocalOverriding else {
            return nil
        }
        return persistor.value(for: featureFlag)
    }

    public func toggleOverride<Flag: FeatureFlagProtocol>(for featureFlag: Flag) {
        guard featureFlag.supportsLocalOverriding else {
            return
        }
        let currentValue = persistor.value(for: featureFlag) ?? false
        let newValue = !currentValue
        persistor.set(newValue, for: featureFlag)
        actionHandler.flagDidChange(featureFlag, isEnabled: newValue)
    }

    public func clearOverride<Flag: FeatureFlagProtocol>(for featureFlag: Flag) {
        guard let override = override(for: featureFlag) else {
            return
        }
        persistor.set(nil, for: featureFlag)
        if let defaultValue = featureFlagger?.isFeatureOn(forProvider: featureFlag), defaultValue != override {
            actionHandler.flagDidChange(featureFlag, isEnabled: defaultValue)
        }
    }

    public func clearAllOverrides<Flag: FeatureFlagProtocol>(for flagType: Flag.Type) {
        flagType.allCases.forEach { flag in
            clearOverride(for: flag)
        }
    }
}
