//
//  TrackerResolver.swift
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
import Common
import ContentBlocking

public class TrackerResolver {
    
    let tds: TrackerData
    let unprotectedSites: [String]
    let tempList: [String]
    let tld: TLD
    let adClickAttributionVendor: String?
    
    public init(tds: TrackerData,
                unprotectedSites: [String],
                tempList: [String],
                tld: TLD,
                adClickAttributionVendor: String? = nil) {
        self.tds = tds
        self.unprotectedSites = unprotectedSites
        self.tempList = tempList
        self.tld = tld
        self.adClickAttributionVendor = adClickAttributionVendor
    }
    
    public func trackerFromUrl(_ trackerUrlString: String,
                               pageUrlString: String,
                               resourceType: String,
                               potentiallyBlocked: Bool) -> DetectedRequest? {
        var trackerUrlString = trackerUrlString
        let tracker: KnownTracker
        if let regularTracker = tds.findTracker(forUrl: trackerUrlString) {
            tracker = regularTracker
        } else if let cnamedTracker = tds.findTrackerByCname(forUrl: trackerUrlString),
                  let originalTrackerURL = URL(string: trackerUrlString),
                  let cnamedTrackerURL = originalTrackerURL.replacing(host: cnamedTracker.domain) {
            tracker = cnamedTracker
            trackerUrlString = cnamedTrackerURL.absoluteString
        } else {
            return nil
        }
        
        guard let entity = tds.findEntity(byName: tracker.owner?.name ?? "") else {
            return nil
        }
        
        if isPageAffiliatedWithTrackerEntity(pageUrlString: pageUrlString, trackerEntity: entity) {
            return DetectedRequest(url: trackerUrlString,
                                   eTLDplus1: tld.eTLDplus1(forStringURL: trackerUrlString),
                                   knownTracker: tracker,
                                   entity: entity,
                                   state: .allowed(reason: .ownedByFirstParty),
                                   pageUrl: pageUrlString)
        }
        
        let blockingState = calculateBlockingState(tracker: tracker,
                                                   trackerUrlString: trackerUrlString,
                                                   resourceType: resourceType,
                                                   potentiallyBlocked: potentiallyBlocked,
                                                   pageUrlString: pageUrlString)

        return DetectedRequest(url: trackerUrlString,
                               eTLDplus1: tld.eTLDplus1(forStringURL: trackerUrlString),
                               knownTracker: tracker,
                               entity: entity,
                               state: blockingState,
                               pageUrl: pageUrlString)
    }
    
    private func isPageAffiliatedWithTrackerEntity(pageUrlString: String, trackerEntity: Entity) -> Bool {
        guard let pageHost = URL(string: pageUrlString)?.host,
              let pageEntity = tds.findEntity(forHost: pageHost)
        else { return false }
           
        return pageEntity.displayName == trackerEntity.displayName
    }
    
    private func calculateBlockingState(tracker: KnownTracker,
                                        trackerUrlString: String,
                                        resourceType: String,
                                        potentiallyBlocked: Bool,
                                        pageUrlString: String) -> BlockingState {

        let blockingState: BlockingState
        
        if isPageOnUnprotectedSitesOrTempList(pageUrlString) {
            blockingState = .allowed(reason: .protectionDisabled) // maybe we should not differentiate
        } else {
            // Check for custom rules
            let rule = tracker.matchingRuleForTrackerURL(trackerUrlString)
            let ruleAction = rule?.action(type: resourceType,
                                          pageUrlString: pageUrlString) ?? .none

            switch ruleAction {
            case .none:
                if tracker.defaultAction == .block {
                    blockingState = potentiallyBlocked ? .blocked : .allowed(reason: .ruleException)
                } else /* if tracker.defaultAction == .ignore */ {
                    blockingState = .allowed(reason: .ruleException)
                }
            case .allowRequest:
                if let vendor = adClickAttributionVendor,
                   isVendorMatchingCurrentPage(vendor: vendor, pageUrlString: pageUrlString),
                   isVendorOnExceptionsList(vendor: vendor, exceptions: rule?.exceptions) {
                    blockingState = .allowed(reason: .adClickAttribution)
                } else {
                    blockingState = .allowed(reason: .ruleException)
                }
            case .blockRequest:
                blockingState = potentiallyBlocked ? .blocked : .allowed(reason: .ruleException)
            }
        }
        
        return blockingState
    }
    
    private func isPageOnUnprotectedSitesOrTempList(_ pageUrlString: String) -> Bool {
        guard let pageHost = URL(string: pageUrlString)?.host else { return false }
        
        return unprotectedSites.contains(pageHost) || tempList.contains(pageHost)
    }
    
    private func isVendorMatchingCurrentPage(vendor: String, pageUrlString: String) -> Bool {
        vendor == URL(string: pageUrlString)?.host?.droppingWwwPrefix()
    }
    
    private func isVendorOnExceptionsList(vendor: String, exceptions: KnownTracker.Rule.Matching?) -> Bool {
        guard let domains = exceptions?.domains else { return false }
        
        return domains.contains(vendor)
    }

    enum RuleAction {
        case none
        case allowRequest
        case blockRequest
    }

    static public func isMatching(_ option: KnownTracker.Rule.Matching, host: String, resourceType: String) -> Bool {

        var isEmpty = true // Require either domains or types to be specified
        var matching = true

        if let requiredDomains = option.domains, !requiredDomains.isEmpty {
            isEmpty = false
            matching = requiredDomains.contains(where: { domain in
                guard domain != host else { return true }
                return host.hasSuffix(".\(domain)")
            })
        }

        if let requiredTypes = option.types, !requiredTypes.isEmpty {
            isEmpty = false
            matching = matching && requiredTypes.contains(resourceType)
        }

        return !isEmpty && matching
    }
}

fileprivate extension KnownTracker {

    func matchingRuleForTrackerURL(_ urlString: String) -> KnownTracker.Rule? {

        let range = NSRange(location: 0, length: urlString.utf16.count)
        
        for rule in rules ?? [] {
            guard let pattern = rule.rule,
                  let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }

            if regex.firstMatch(in: urlString, options: [], range: range) != nil {
                return rule
            }
        }

        return nil
    }
}

fileprivate extension KnownTracker.Rule {
    
    func action(type: String,
                pageUrlString: String) -> TrackerResolver.RuleAction {
        
        guard let host = URL(string: pageUrlString)?.host else { return .none }

        // If there is a rule its default action is always block
        var resultAction = action ?? .block
        
        // If there are matching exceptions toggle the action
        if let exceptions = exceptions, TrackerResolver.isMatching(exceptions, host: host, resourceType: type) {
            resultAction = resultAction.toggle()
        }
        
        return resultAction.toTrackerResolverRuleAction()
    }
}

private extension KnownTracker.ActionType {
    
    func toTrackerResolverRuleAction() -> TrackerResolver.RuleAction {
        self == .block ? .blockRequest : .allowRequest
    }
    
    func toggle() -> Self {
        self == .ignore ? .block : .ignore
    }
}
