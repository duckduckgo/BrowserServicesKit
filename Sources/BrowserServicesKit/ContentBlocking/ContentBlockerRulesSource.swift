//
//  ContentBlockerRulesSource.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import TrackerRadarKit

/**
 Represents all sources used to build Content Blocking Rules.
 */
public protocol ContentBlockerRulesListsSource {

    var contentBlockerRulesLists: [ContentBlockerRulesList] { get }
}

/**
 Represents sources used to prepare exceptions to content blocking Rules.
 */
public protocol ContentBlockerRulesExceptionsSource {

    var tempListEtag: String { get }
    var tempList: [String] { get }
    var allowListEtag: String { get }
    var allowList: [TrackerException] { get }
    var unprotectedSites: [String] { get }
}

public struct ContentBlockerRulesList {

    public let trackerData: TrackerDataManager.DataSet?
    public let fallbackTrackerData: TrackerDataManager.DataSet

    public let name: String
    
    public init(name: String,
                trackerData: TrackerDataManager.DataSet?,
                fallbackTrackerData: TrackerDataManager.DataSet) {
        self.name = name
        self.trackerData = trackerData
        self.fallbackTrackerData = fallbackTrackerData
    }
}

open class DefaultContentBlockerRulesListsSource: ContentBlockerRulesListsSource {
    
    public struct Constants {
        public static let trackerDataSetRulesListName = "TrackerDataSet"
    }

    private let trackerDataManager: TrackerDataManager

    public init(trackerDataManager: TrackerDataManager) {
        self.trackerDataManager = trackerDataManager
    }
    
    open var contentBlockerRulesLists: [ContentBlockerRulesList] {
        return [ContentBlockerRulesList(name: Constants.trackerDataSetRulesListName,
                                        trackerData: trackerDataManager.fetchedData,
                                        fallbackTrackerData: trackerDataManager.embeddedData)]
    }
}

public class DefaultContentBlockerRulesExceptionsSource: ContentBlockerRulesExceptionsSource {

    let privacyConfigManager: PrivacyConfigurationManager

    public init(privacyConfigManager: PrivacyConfigurationManager) {
        self.privacyConfigManager = privacyConfigManager
    }

    public var tempListEtag: String {
        return privacyConfigManager.privacyConfig.identifier
    }

    public var tempList: [String] {
        let config = privacyConfigManager.privacyConfig
        var tempUnprotected = config.tempUnprotectedDomains.filter { !$0.trimmingWhitespace().isEmpty }
        tempUnprotected.append(contentsOf: config.exceptionsList(forFeature: .contentBlocking))
        return tempUnprotected
    }

    public var allowListEtag: String {
        return privacyConfigManager.privacyConfig.identifier
    }

    public var allowList: [TrackerException] {
        return Self.transform(allowList: privacyConfigManager.privacyConfig.trackerAllowlist)
    }

    public var unprotectedSites: [String] {
        return privacyConfigManager.privacyConfig.userUnprotectedDomains
    }

    public class func transform(allowList: PrivacyConfigurationData.TrackerAllowlistData) -> [TrackerException] {

        let trackerRules = allowList.values.reduce(into: []) { partialResult, next in
            partialResult.append(contentsOf: next)
        }

        return trackerRules.map { entry in
            if entry.domains.contains("<all>") {
                return TrackerException(rule: entry.rule, matching: .all)
            } else {
                return TrackerException(rule: entry.rule, matching: .domains(entry.domains.normalizedDomainsForContentBlocking()))
            }
        }
    }

}
