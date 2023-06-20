//
//  ClickToLoadRulesSplitter.swift
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

import TrackerRadarKit

struct ClickToLoadRulesSplitter {

    public enum Constant {

        public static let clickToLoadRuleListPrefix = "CTL_"

    }

    private let rulesList: ContentBlockerRulesList

    init(rulesList: ContentBlockerRulesList) {
        self.rulesList = rulesList
    }

    func split() -> (withoutBlockCTL: ContentBlockerRulesList, withBlockCTL: ContentBlockerRulesList)? {
        let splitTDS = rulesList.trackerData != nil ? split(trackerData: rulesList.trackerData!) : nil
        let splitFallbackTDS = split(trackerData: rulesList.fallbackTrackerData)

        if splitTDS != nil || splitFallbackTDS != nil {
            return (
                ContentBlockerRulesList(name: rulesList.name,
                                        trackerData: splitTDS?.withoutBlockCTL ?? rulesList.trackerData,
                                        fallbackTrackerData: splitFallbackTDS?.withoutBlockCTL ?? rulesList.fallbackTrackerData),
                ContentBlockerRulesList(name: "XD",
                                        trackerData: splitTDS?.withBlockCTL ?? rulesList.trackerData,
                                        fallbackTrackerData: splitFallbackTDS?.withBlockCTL ?? rulesList.fallbackTrackerData)
            )
        }
        return nil
    }

    private func split(trackerData: TrackerDataManager.DataSet) -> (withoutBlockCTL: TrackerDataManager.DataSet, withBlockCTL: TrackerDataManager.DataSet)? {
        let trackersWithBlockCTL = filterTrackersByBlockCTLAction(trackerData.tds.trackers, hasBlockCTL: true)

        if !trackersWithBlockCTL.isEmpty {
            let trackersWithoutBlockCTL = filterTrackersByBlockCTLAction(trackerData.tds.trackers, hasBlockCTL: false)
            let trackerDataWithoutBlockCTL = makeTrackerData(using: trackersWithoutBlockCTL)
            let trackerDataWithBlockCTL = makeTrackerData(using: trackersWithBlockCTL)

            return (
                (tds: trackerDataWithoutBlockCTL, etag: Constant.clickToLoadRuleListPrefix + trackerData.etag),
                (tds: trackerDataWithBlockCTL, etag: Constant.clickToLoadRuleListPrefix + trackerData.etag)
            )
        }
        return nil
    }

    private func makeTrackerData(using trackers: [String: KnownTracker]) -> TrackerData {
        let entities = extractEntities(for: trackers)
        let domains = extractDomains(for: entities)
        return TrackerData(trackers: trackers,
                           entities: entities,
                           domains: domains,
                           cnames: rulesList.trackerData?.tds.cnames)
    }

    private func filterTrackersByBlockCTLAction(_ trackers: [String: KnownTracker], hasBlockCTL: Bool) -> [String: KnownTracker] {
        trackers.filter { (_, tracker) in tracker.containsCTLActions == hasBlockCTL }
    }

    private func extractEntities(for trackers: [String: KnownTracker]) -> [String: Entity] {
        let trackerOwners = Set(trackers.values.compactMap { $0.owner?.name })
        let entities = rulesList.trackerData?.tds.entities.filter { trackerOwners.contains($0.key) } ?? [:]
        return entities
    }

    private func extractDomains(for entities: [String: Entity]) -> [String: String] {
        var domains = [String: String]()
        for entity in entities {
            for domain in entity.value.domains ?? [] {
                domains[domain] = entity.key
            }
        }
        return domains
    }

}

private extension KnownTracker {

    var containsCTLActions: Bool {
        if let defaultAction = defaultAction, defaultAction == .ctlfb || defaultAction == .ctlyt {
            return true
        }

        if let rules = rules {
            for rule in rules {
                if let action = rule.action, action == .ctlfb || action == .ctlyt {
                    return true
                }
            }
        }
        return false
    }

}
