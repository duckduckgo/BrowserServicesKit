//
//  ClickToLoadRulesSplitter.swift
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

import TrackerRadarKit

public struct ClickToLoadRulesSplitter {

    public enum Constants {

        public static let clickToLoadRuleListPrefix = "CTL_"
        public static let tdsRuleListPrefix = "TDS_"

    }

    private let rulesList: ContentBlockerRulesList

    public init(rulesList: ContentBlockerRulesList) {
        self.rulesList = rulesList
    }

    public func split() -> (withoutBlockCTL: ContentBlockerRulesList, withBlockCTL: ContentBlockerRulesList)? {
        var withoutBlockCTL: (tds: TrackerData, etag: String)?
        var withBlockCTL: (tds: TrackerData, etag: String)?

        if let trackerData = rulesList.trackerData {
            let splitTDS = split(trackerData: trackerData)
            guard !splitTDS.withBlockCTL.tds.trackers.isEmpty else { return nil }

            withoutBlockCTL = splitTDS.withoutBlockCTL
            withBlockCTL = splitTDS.withBlockCTL
        }

        return (
            ContentBlockerRulesList(name: rulesList.name,
                                    trackerData: withoutBlockCTL,
                                    fallbackTrackerData: split(trackerData: rulesList.fallbackTrackerData).withoutBlockCTL),
            ContentBlockerRulesList(name: DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
                                    trackerData: withBlockCTL,
                                    fallbackTrackerData: split(trackerData: rulesList.fallbackTrackerData).withBlockCTL)
        )
    }

    private func split(trackerData: TrackerDataManager.DataSet) -> (withoutBlockCTL: TrackerDataManager.DataSet, withBlockCTL: TrackerDataManager.DataSet) {
        let (mainTrackers, ctlTrackers) = processCTLActions(trackerData.tds.trackers)

        let trackerDataWithoutBlockCTL = makeTrackerData(using: mainTrackers, originalTDS: trackerData.tds)
        let trackerDataWithBlockCTL = makeTrackerData(using: ctlTrackers, originalTDS: trackerData.tds)

        return (
           (tds: trackerDataWithoutBlockCTL, etag: Constants.tdsRuleListPrefix + trackerData.etag),
           (tds: trackerDataWithBlockCTL, etag: Constants.clickToLoadRuleListPrefix + trackerData.etag)
        )
    }

    private func makeTrackerData(using trackers: [String: KnownTracker], originalTDS: TrackerData) -> TrackerData {
        let entities = originalTDS.extractEntities(for: trackers)
        let domains = extractDomains(from: entities)
        return TrackerData(trackers: trackers,
                           entities: entities,
                           domains: domains,
                           cnames: originalTDS.cnames)
    }

    private func processCTLActions(_ trackers: [String: KnownTracker]) -> (mainTrackers: [String: KnownTracker], ctlTrackers: [String: KnownTracker]) {
        var mainTDSTrackers: [String: KnownTracker] = [:]
        var ctlTrackers: [String: KnownTracker] = [:]

        for (key, tracker) in trackers {
            guard tracker.containsCTLActions, let rules = tracker.rules else {
                mainTDSTrackers[key] = tracker
                continue
            }

            // if we found some CTL rules, split out into its own list
            var mainRules: [KnownTracker.Rule] = []
            var ctlRules: [KnownTracker.Rule] = []

            for rule in rules.reversed() {
                if let action = rule.action, action == .blockCTLFB {
                    ctlRules.insert(rule, at: 0)
                } else {
                    ctlRules.insert(rule, at: 0)
                    mainRules.insert(rule, at: 0)
                }
            }

            let mainTracker = KnownTracker(domain: tracker.domain,
                                           defaultAction: tracker.defaultAction,
                                           owner: tracker.owner,
                                           prevalence: tracker.prevalence,
                                           subdomains: tracker.subdomains,
                                           categories: tracker.categories,
                                           rules: mainRules)
            let ctlTracker = KnownTracker(domain: tracker.domain,
                                          defaultAction: tracker.defaultAction,
                                          owner: tracker.owner,
                                          prevalence: tracker.prevalence,
                                          subdomains: tracker.subdomains,
                                          categories: tracker.categories,
                                          rules: ctlRules)
            mainTDSTrackers[key] = mainTracker
            ctlTrackers[key] = ctlTracker
        }

        return (mainTDSTrackers, ctlTrackers)
    }

    private func extractDomains(from entities: [String: Entity]) -> [String: String] {
        var domains = [String: String]()
        for (key, entity) in entities {
            for domain in entity.domains ?? [] {
                domains[domain] = key
            }
        }
        return domains
    }

}

private extension TrackerData {

    func extractEntities(for trackers: [String: KnownTracker]) -> [String: Entity] {
        let trackerOwners = Set(trackers.values.compactMap { $0.owner?.name })
        let entities = entities.filter { trackerOwners.contains($0.key) }
        return entities
    }

}

private extension KnownTracker {

    var containsCTLActions: Bool { rules?.first { $0.action == .blockCTLFB } != nil }

}
