//
//  ToggleReportingFeature.swift
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
import Combine
import BrowserServicesKit

public struct PrivacyConfigurationToggleReportingFeature {

    let isEnabled: Bool
    let settings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings

    public init(isEnabled: Bool, settings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings) {
        self.isEnabled = isEnabled
        self.settings = settings
    }

    public init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        let privacyConfig = privacyConfigurationManager.privacyConfig
        isEnabled = privacyConfig.isEnabled(featureKey: .toggleReports)
        settings = privacyConfig.settings(for: .toggleReports)
    }

}

public protocol ToggleReporting {

    var isEnabled: Bool { get }

    var isDismissLogicEnabled: Bool { get }
    var dismissInterval: TimeInterval { get }

    var isPromptLimitLogicEnabled: Bool { get }
    var promptInterval: TimeInterval { get }
    var maxPromptCount: Int { get }

}

public final class ToggleReportingFeature: ToggleReporting {

    enum Constants {

        static let dismissLogicEnabledKey = "dismissLogicEnabled"
        static let dismissIntervalKey = "dismissInterval"

        static let promptLimitLogicEnabledKey = "promptLimitLogicEnabled"
        static let promptIntervalKey = "promptInterval"
        static let maxPromptCountKey = "maxPromptCount"

        static let defaultTimeInterval: TimeInterval = 48 * 60 * 60 // 2 days
        static let defaultPromptCount = 3

    }

    public private(set) var isEnabled: Bool = false

    public private(set) var isDismissLogicEnabled: Bool = true
    public private(set) var dismissInterval: TimeInterval = 0

    public private(set) var isPromptLimitLogicEnabled: Bool = true
    public private(set) var promptInterval: TimeInterval = 0
    public private(set) var maxPromptCount: Int = 0

    public init(privacyConfigurationToggleReportingFeature: PrivacyConfigurationToggleReportingFeature,
                currentLocale: Locale = Locale.current) {
        let isCurrentLanguageEnglish = currentLocale.languageCode == "en"
        isEnabled = privacyConfigurationToggleReportingFeature.isEnabled && isCurrentLanguageEnglish
        guard isEnabled else { return }
        let settings = privacyConfigurationToggleReportingFeature.settings
        isDismissLogicEnabled = settings[Constants.dismissLogicEnabledKey] as? Bool ?? false
        dismissInterval = settings[Constants.dismissIntervalKey] as? TimeInterval ?? Constants.defaultTimeInterval
        isPromptLimitLogicEnabled = settings[Constants.promptLimitLogicEnabledKey] as? Bool ?? false
        promptInterval = settings[Constants.promptIntervalKey] as? TimeInterval ?? Constants.defaultTimeInterval
        maxPromptCount = settings[Constants.maxPromptCountKey] as? Int ?? Constants.defaultPromptCount
    }

}
