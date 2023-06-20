//
//  ClickToLoadRulesMutator.swift
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

public struct ClickToLoadOptions: OptionSet {

    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let fb = ClickToLoadOptions(rawValue: 1 << 0)
    public static let yt = ClickToLoadOptions(rawValue: 1 << 1)

    public static let all: ClickToLoadOptions = [.fb, .yt]

}

private extension KnownTracker.ActionType {

    var clickToLoadOption: ClickToLoadOptions? {
        switch self {
        case .ctlfb: return .fb
        case .ctlyt: return .yt
        case .block, .ignore: return nil
        }
    }

}

struct ClickToLoadRulesMutator {

    var trackerData: TrackerData

    public init(trackerData: TrackerData) {
        self.trackerData = trackerData
    }

    func addExceptions(forDomain domain: String,
                       for ctlOptions: ClickToLoadOptions) -> TrackerData {
        var updatedTrackers = [String: KnownTracker]()

        for (trackerName, tracker) in trackerData.trackers {
            let updatedRules = tracker.rules?.compactMap { rule in
                return addExceptions(forDomain: domain, for: ctlOptions, in: rule)
            }
            let updatedTracker = KnownTracker(domain: tracker.domain,
                                              defaultAction: tracker.defaultAction,
                                              owner: tracker.owner,
                                              prevalence: tracker.prevalence,
                                              subdomains: tracker.subdomains,
                                              categories: tracker.categories,
                                              rules: updatedRules)
            updatedTrackers[trackerName] = updatedTracker
        }

        return TrackerData(trackers: updatedTrackers,
                           entities: trackerData.entities,
                           domains: trackerData.domains,
                           cnames: trackerData.cnames)
    }

    private func addExceptions(forDomain domain: String,
                               for ctlOptions: ClickToLoadOptions,
                               in rule: KnownTracker.Rule) -> KnownTracker.Rule {
        guard let ctlOption = rule.action?.clickToLoadOption else { return rule }
        if ctlOptions.contains(ctlOption) {
            let domains = rule.exceptions?.domains ?? []
            let exceptions = KnownTracker.Rule.Matching(domains: domains + [domain],
                                                        types: rule.exceptions?.types)
            return KnownTracker.Rule(rule: rule.rule,
                                     surrogate: rule.surrogate,
                                     action: rule.action,
                                     options: rule.options,
                                     exceptions: exceptions)
        }

        return rule
    }

}
