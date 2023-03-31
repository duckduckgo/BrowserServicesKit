//
//  ContentBlockerRulesListSplitter.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

public struct ContentBlockerRulesListSplitter {

    public enum Constant {

        public static let clickToLoadRuleListPrefix = "CTL_"

    }

    private let rulesList: ContentBlockerRulesList

    // MARK: - API

    /// - Parameters:
    ///   - rulesList: Rules list to be split
    public init(rulesList: ContentBlockerRulesList) {
        self.rulesList = rulesList
    }

    static public func clickToLoadRuleListName(forListNamed name: String) -> String {
        return "\(Constant.clickToLoadRuleListPrefix)\(name)"
    }

    /// - Returns: Split rules only if the input rulesList contains rules with action "block-ctl"
    public func split() -> (ContentBlockerRulesList, ContentBlockerRulesList)? {
        guard rulesList.containsCTLActions else { return nil }

        let splitTDS = rulesList.trackerData != nil ? split(tds: rulesList.trackerData!) : nil
        let splitFallbackTDS = split(tds: rulesList.fallbackTrackerData)
        return (ContentBlockerRulesList(name: rulesList.name,
                                        trackerData: splitTDS?.0,
                                        fallbackTrackerData: splitFallbackTDS.0),
                ContentBlockerRulesList(name: Self.clickToLoadRuleListName(forListNamed: rulesList.name),
                                        trackerData: splitTDS?.1,
                                        fallbackTrackerData: splitFallbackTDS.1))
    }

    private func split(tds: TrackerDataManager.DataSet) -> (TrackerDataManager.DataSet, TrackerDataManager.DataSet) {
        let regularTrackerData = makeTrackerData(from: tds.tds, shouldBlockCTLRules: false)
        let blockCTLTrackerData = makeTrackerData(from: tds.tds, shouldBlockCTLRules: true)

        // Tweak ETag to prevent caching issues between changed lists // todo??? how will it work with attribution in such case?
        return ((tds: regularTrackerData,
                 etag: Constant.clickToLoadRuleListPrefix + tds.etag),
                (tds: blockCTLTrackerData,
                 etag: Constant.clickToLoadRuleListPrefix + tds.etag))
    }

    private func makeTrackerData(from trackerData: TrackerData, shouldBlockCTLRules: Bool) -> TrackerData { // this needs to be changed obviously
        let trackersWithBlockCTL = trackersWithBlockCTL(from: trackerData)
        let updatedTrackers = updateTrackers(trackersWithBlockCTL, shouldBlockCTLRules: shouldBlockCTLRules)
        let entities = entities(for: updatedTrackers, from: trackerData)
        let domains = domains(for: entities)
        return TrackerData(trackers: updatedTrackers,
                           entities: entities,
                           domains: domains,
                           cnames: nil)
    }

    private func trackersWithBlockCTL(from trackerData: TrackerData) -> [KnownTracker] {
        trackerData.trackers.values.filter { $0.rules?.contains { $0.action == .ctlfb } == true }
    }

    private func updateTrackers(_ trackers: [KnownTracker], shouldBlockCTLRules: Bool) -> [String: KnownTracker] {
        var updatedTrackers: [String: KnownTracker] = [:]

        for tracker in trackers {
            let updatedRules = tracker.rules!.map { rule in
                let action: KnownTracker.ActionType? = shouldBlockCTLRules ? .block : nil
                return rule.action == .ctlfb ? rule.withAction(action) : rule
            }

            let updatedTracker = tracker.withUpdatedRules(updatedRules)
            if let domain = tracker.domain {
                updatedTrackers[domain] = updatedTracker
            }
        }
        return updatedTrackers
    }

    private func entities(for updatedTrackers: [String: KnownTracker], from trackerData: TrackerData) -> [String: Entity] {
        let trackersOwners = updatedTrackers.values.compactMap { $0.owner?.name }
        var entities = [String: Entity]()
        for ownerName in trackersOwners {
            if let entity = trackerData.entities[ownerName] {
                entities[ownerName] = entity
            }
        }
        return entities
    }

    private func domains(for entities: [String: Entity]) -> [String: String] {
        var domains = [String: String]()
        for entity in entities {
            for domain in entity.value.domains ?? [] {
                domains[domain] = entity.key
            }
        }
        return domains
    }

}

private extension ContentBlockerRulesList {

    var containsCTLActions: Bool {
        trackerData?.tds.containsCTLActions ?? false || fallbackTrackerData.tds.containsCTLActions
    }

}

private extension TrackerData {

    var containsCTLActions: Bool {
        trackers.values
            .compactMap { $0.rules }
            .flatMap { $0 }
            .contains { $0.action == .ctlfb }
    }

}

private extension KnownTracker {

    func withUpdatedRules(_ rules: [KnownTracker.Rule]) -> Self {
        KnownTracker(domain: domain,
                     defaultAction: defaultAction,
                     owner: owner,
                     prevalence: prevalence,
                     subdomains: subdomains,
                     categories: categories,
                     rules: rules
        )
    }

}

private extension KnownTracker.Rule {

    func withAction(_ action: KnownTracker.ActionType?) -> Self {
        KnownTracker.Rule(rule: rule,
                          surrogate: surrogate,
                          action: action,
                          options: options,
                          exceptions: exceptions
        )
    }

}

