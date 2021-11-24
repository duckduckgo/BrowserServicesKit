//
//  ContentBlockerRulesManager.swift
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

import Foundation
import WebKit
import os.log
import TrackerRadarKit

public protocol ContentBlockerRulesUpdating {

    func rulesManager(_ manager: ContentBlockerRulesManager,
                      didUpdateRules: ContentBlockerRulesManager.CurrentRules,
                      changes: ContentBlockerRulesIdentifier.Difference,
                      completionTokens: [ContentBlockerRulesManager.CompletionToken])
}

/**
 Manages creation of Content Blocker rules from `ContentBlockerRulesSource`.
 */
public class ContentBlockerRulesManager {
    
    public typealias CompletionToken = String
    
    enum State {
        case idle // Waiting for work
        case recompiling(currentTokens: [CompletionToken]) // Executing work
        case recompilingAndScheduled(currentTokens: [CompletionToken], pendingTokens: [CompletionToken]) // New work has been requested while one is currently being executed
    }

    /**
     Encapsulates information about the result of the compilation.
     */
    public struct CurrentRules {
        public let rulesList: WKContentRuleList
        public let trackerData: TrackerData
        public let encodedTrackerData: String
        public let etag: String
        public let identifier: ContentBlockerRulesIdentifier
    }

    private let dataSource: ContentBlockerRulesSource
    private let updateListener: ContentBlockerRulesUpdating?
    private let logger: OSLog
    public let sourceManager: ContentBlockerRulesSourceManager

    private let workQueue = DispatchQueue(label: "ContentBlockerManagerQueue", qos: .userInitiated)

    public init(source: ContentBlockerRulesSource,
                updateListener: ContentBlockerRulesUpdating? = nil,
                logger: OSLog = .disabled,
                skipInitialSetup: Bool = false) {
        dataSource = source
        self.updateListener = updateListener
        self.logger = logger
        sourceManager = ContentBlockerRulesSourceManager(dataSource: source)
        
        if !skipInitialSetup {
            requestCompilation(token: "")
        }
    }
    
    /**
     Variables protected by this lock:
      - state
      - currentRules
     */
    private let lock = NSLock()
    
    private var state = State.idle
    
    private var _currentRules: CurrentRules?
    public private(set) var currentRules: CurrentRules? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _currentRules
        }
        set {
            lock.lock()
            self._currentRules = newValue
            lock.unlock()
        }
    }

    @discardableResult
    public func scheduleCompilation() -> CompletionToken {
        let token = UUID().uuidString
        workQueue.async {
            self.requestCompilation(token: token)
        }
        return token
    }


    private func requestCompilation(token: CompletionToken) {
        os_log("Requesting compilation...", log: logger, type: .default)
        
        lock.lock()
        guard case .idle = state else {
            if case .recompiling(let tokens) = state {
                // Schedule reload
                state = .recompilingAndScheduled(currentTokens: tokens, pendingTokens: [token])
            } else if case .recompilingAndScheduled(let currentTokens, let pendingTokens) = state {
                state = .recompilingAndScheduled(currentTokens: currentTokens, pendingTokens: pendingTokens + [token])
            }
            lock.unlock()
            return
        }
        
        state = .recompiling(currentTokens: [token])
        let isInitial = _currentRules == nil
        lock.unlock()
        
        performCompilation(isInitial: isInitial)
    }

    private func performCompilation(isInitial: Bool = false) {
        let input = sourceManager.makeModel()
        
        if isInitial {
            // Delegate querying to main thread - crashes were observed in background.
            DispatchQueue.main.async {
                WKContentRuleListStore.default()?.lookUpContentRuleList(forIdentifier: input.rulesIdentifier.stringValue,
                                                                        completionHandler: { ruleList, _ in
                    if let ruleList = ruleList {
                        self.compilationSucceeded(with: ruleList, for: input)
                    } else {
                        self.workQueue.async {
                            self.compile(input: input)
                        }
                    }
                })
            }
        } else {
            compile(input: input)
        }
    }

    fileprivate func compile(input: ContentBlockerRulesSourceModel) {
        os_log("Starting CBR compilation", log: logger, type: .default)

        let builder = ContentBlockerRulesBuilder(trackerData: input.tds)
        let rules = builder.buildRules(withExceptions: input.unprotectedSites,
                                       andTemporaryUnprotectedDomains: input.tempList,
                                       andTrackerAllowlist: input.allowList)

        let data: Data
        do {
            data = try JSONEncoder().encode(rules)
        } catch {
            os_log("Failed to encode content blocking rules", log: logger, type: .error)
            compilationFailed(for: input, with: error)
            return
        }

        let ruleList = String(data: data, encoding: .utf8)!
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: input.rulesIdentifier.stringValue,
                                     encodedContentRuleList: ruleList) { ruleList, error in
            
            if let ruleList = ruleList {
                self.compilationSucceeded(with: ruleList, for: input)
            } else if let error = error {
                self.compilationFailed(for: input, with: error)
            } else {
                assertionFailure("Rule list has not been returned properly by the engine")
            }
        }

    }
    
    private func compilationFailed(for input: ContentBlockerRulesSourceModel, with error: Error) {
        os_log("Failed to compile rules %{public}s", log: logger, type: .error, error.localizedDescription)
        
        lock.lock()
                
        if case .recompilingAndScheduled(let currentTokens, let pendingTokens) = state {
            // Recompilation is scheduled - it may fix the problem
            state = .recompiling(currentTokens: currentTokens + pendingTokens)
        } else {
            sourceManager.compilationFailed(for: input, with: error)
        }
        
        workQueue.async {
            self.performCompilation()
        }

        lock.unlock()
    }
    
    static func extractSurrogates(from tds: TrackerData) -> TrackerData {
        
        let trackers = tds.trackers.filter { pair in
            return pair.value.rules?.first(where: { rule in
                rule.surrogate != nil
            }) != nil
        }
        
        var domains = [TrackerData.TrackerDomain: TrackerData.EntityName]()
        var entities = [TrackerData.EntityName: Entity]()
        for tracker in trackers {
            if let entityName = tds.domains[tracker.key] {
                domains[tracker.key] = entityName
                entities[entityName] = tds.entities[entityName]
            }
        }
        
        var cnames = [TrackerData.CnameDomain: TrackerData.TrackerDomain]()
        if let tdsCnames = tds.cnames {
            for pair in tdsCnames {
                for domain in domains.keys {
                    if pair.value.hasSuffix(domain) {
                        cnames[pair.key] = pair.value
                        break
                    }
                }
            }
        }
        
        return TrackerData(trackers: trackers, entities: entities, domains: domains, cnames: cnames)
    }
    
    private func compilationSucceeded(with ruleList: WKContentRuleList,
                                      for input: ContentBlockerRulesSourceModel) {
        os_log("Rules compiled", log: logger, type: .default)
        
        let surrogateTDS = Self.extractSurrogates(from: input.tds)
        let encodedData = try? JSONEncoder().encode(surrogateTDS)
        let encodedTrackerData = String(data: encodedData!, encoding: .utf8)!
        
        lock.lock()
        
        let diff: ContentBlockerRulesIdentifier.Difference
        if let id = _currentRules?.identifier {
            diff = id.compare(with: input.rulesIdentifier)
        } else {
            diff = input.rulesIdentifier.compare(with: ContentBlockerRulesIdentifier(tdsEtag: "",
                                                                                     tempListEtag: nil,
                                                                                     allowListEtag: nil,
                                                                                     unprotectedSitesHash: nil))
        }
        
        let newRules = CurrentRules(rulesList: ruleList,
                                     trackerData: input.tds,
                                     encodedTrackerData: encodedTrackerData,
                                     etag: input.tdsIdentifier,
                                     identifier: input.rulesIdentifier)
        _currentRules = newRules

        var completionTokens = [CompletionToken]()
        if case .recompilingAndScheduled(let currentTokens, let pendingTokens) = state {
            // New work has been scheduled - prepare for execution.
            workQueue.async {
                self.performCompilation()
            }

            completionTokens = currentTokens
            state = .recompiling(currentTokens: pendingTokens)
        } else if case .recompiling(let currentTokens) = state {
            completionTokens = currentTokens
            state = .idle
        }
        
        lock.unlock()
                
        DispatchQueue.main.async {
            self.updateListener?.rulesManager(self,
                                              didUpdateRules: newRules,
                                              changes: diff,
                                              completionTokens: completionTokens)
            
            WKContentRuleListStore.default()?.getAvailableContentRuleListIdentifiers({ ids in
                guard let ids = ids else { return }

                var idsSet = Set(ids)
                idsSet.remove(ruleList.identifier)

                for id in idsSet {
                    WKContentRuleListStore.default()?.removeContentRuleList(forIdentifier: id) { _ in }
                }
            })
        }
    }

}
