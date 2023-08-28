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
import TrackerRadarKit
import Combine
import Common

// swiftlint:disable file_length type_body_length

public protocol CompiledRuleListsSource {
    
    // Represent set of all latest rules that has been compiled
    var currentRules: [ContentBlockerRulesManager.Rules] { get }
    
    // Set of core rules: TDS minus Ad Attribution rules
    var currentMainRules: ContentBlockerRulesManager.Rules? { get }
    
    // Rules related to Ad Attribution feature, extracted from TDS set.
    var currentAttributionRules: ContentBlockerRulesManager.Rules? { get }
}

public protocol ContentBlockerRulesCaching: AnyObject {
    var contentRulesCache: [String: Date] { get set }
    var contentRulesCacheInterval: TimeInterval { get }
}

/**
 Manages creation of Content Blocker rules from `ContentBlockerRulesSource`.
 */
public class ContentBlockerRulesManager: CompiledRuleListsSource {

    public typealias CompletionToken = String

    enum State {
        case idle // Waiting for work
        case recompiling(currentTokens: [CompletionToken]) // Executing work
        case recompilingAndScheduled(currentTokens: [CompletionToken],
                                     pendingTokens: [CompletionToken]) // New work has been requested while one is currently being executed
    }

    /**
     Encapsulates information about the result of the task compilation.
     */
    public struct Rules {
        public let name: String
        public let rulesList: WKContentRuleList
        public let trackerData: TrackerData
        public let encodedTrackerData: String
        public let etag: String
        public let identifier: ContentBlockerRulesIdentifier

        public init(name: String,
                    rulesList: WKContentRuleList,
                    trackerData: TrackerData,
                    encodedTrackerData: String,
                    etag: String,
                    identifier: ContentBlockerRulesIdentifier) {
            self.name = name
            self.rulesList = rulesList
            self.trackerData = trackerData
            self.encodedTrackerData = encodedTrackerData
            self.etag = etag
            self.identifier = identifier
        }
        
        internal init(compilationResult: (compiledRulesList: WKContentRuleList, model: ContentBlockerRulesSourceModel)) {
            let surrogateTDS = ContentBlockerRulesManager.extractSurrogates(from: compilationResult.model.tds)
            let encodedData = try? JSONEncoder().encode(surrogateTDS)
            let encodedTrackerData = String(data: encodedData!, encoding: .utf8)!

            self.init(name: compilationResult.model.name,
                      rulesList: compilationResult.compiledRulesList,
                      trackerData: compilationResult.model.tds,
                      encodedTrackerData: encodedTrackerData,
                      etag: compilationResult.model.tdsIdentifier,
                      identifier: compilationResult.model.rulesIdentifier)
        }
    }

    private let rulesSource: ContentBlockerRulesListsSource
    private let cache: ContentBlockerRulesCaching?
    public let exceptionsSource: ContentBlockerRulesExceptionsSource

    public struct UpdateEvent {
        public let rules: [ContentBlockerRulesManager.Rules]
        public let changes: [String: ContentBlockerRulesIdentifier.Difference]
        public let completionTokens: [ContentBlockerRulesManager.CompletionToken]

        public init(rules: [ContentBlockerRulesManager.Rules],
                    changes: [String: ContentBlockerRulesIdentifier.Difference],
                    completionTokens: [ContentBlockerRulesManager.CompletionToken]) {
            self.rules = rules
            self.changes = changes
            self.completionTokens = completionTokens
        }
    }
    private let updatesSubject = PassthroughSubject<UpdateEvent, Never>()
    public var updatesPublisher: AnyPublisher<UpdateEvent, Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    private let errorReporting: EventMapping<ContentBlockerDebugEvents>?
    private let getLog: () -> OSLog
    private var log: OSLog {
        getLog()
    }

    // Public only for tests
    public var sourceManagers = [String: ContentBlockerRulesSourceManager]()

    private var currentTasks = [CompilationTask]()
    private var compilationStartTime: TimeInterval?

    private let workQueue = DispatchQueue(label: "ContentBlockerManagerQueue", qos: .userInitiated)
    
    private let lastCompiledRulesStore: LastCompiledRulesStore?

    public init(rulesSource: ContentBlockerRulesListsSource,
                exceptionsSource: ContentBlockerRulesExceptionsSource,
                lastCompiledRulesStore: LastCompiledRulesStore? = nil,
                cache: ContentBlockerRulesCaching? = nil,
                errorReporting: EventMapping<ContentBlockerDebugEvents>? = nil,
                log: @escaping @autoclosure () -> OSLog = .disabled) {
        self.rulesSource = rulesSource
        self.exceptionsSource = exceptionsSource
        self.lastCompiledRulesStore = lastCompiledRulesStore
        self.cache = cache
        self.errorReporting = errorReporting
        self.getLog = log

        workQueue.async {
            _ = self.updateCompilationState(token: "")

            if !self.lookupCompiledRules() {
                if let lastCompiledRules = lastCompiledRulesStore?.rules, !lastCompiledRules.isEmpty {
                    self.fetchLastCompiledRules(with: lastCompiledRules)
                } else {
                    self.startCompilationProcess()
                }
            }
        }
    }
    
    /**
     Variables protected by this lock:
      - state
      - currentRules
     */
    private let lock = NSRecursiveLock()

    private var state = State.idle

    private var _currentRules = [Rules]()
    public private(set) var currentRules: [Rules] {
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
    
    public var currentMainRules: Rules? {
        currentRules.first(where: { $0.name == DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName })
    }
    
    public var currentAttributionRules: Rules? {
        currentRules.first(where: {
            let tdsName = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
            return $0.name == AdClickAttributionRulesSplitter.blockingAttributionRuleListName(forListNamed: tdsName)
        })
    }

    @discardableResult
    public func scheduleCompilation() -> CompletionToken {
        let token = UUID().uuidString
        workQueue.async {
            let shouldStartCompilation = self.updateCompilationState(token: token)
            if shouldStartCompilation {
                self.startCompilationProcess()
            }
        }
        return token
    }

    /// Returns true if the compilation should be executed immediately
    private func updateCompilationState(token: CompletionToken) -> Bool {
        os_log("Requesting compilation...", log: log, type: .default)
        lock.lock()
        guard case .idle = state else {
            if case .recompiling(let tokens) = state {
                // Schedule reload
                state = .recompilingAndScheduled(currentTokens: tokens, pendingTokens: [token])
            } else if case .recompilingAndScheduled(let currentTokens, let pendingTokens) = state {
                state = .recompilingAndScheduled(currentTokens: currentTokens, pendingTokens: pendingTokens + [token])
            }
            lock.unlock()
            return false
        }

        state = .recompiling(currentTokens: [token])
        compilationStartTime = compilationStartTime ?? CACurrentMediaTime()
        lock.unlock()
        return true
    }

    /*
     Go through source managers and check if there are already compiled rules in the WebKit rule cache.
     Returns true if rules were found, false otherwise.
     */
    private func lookupCompiledRules() -> Bool {
        prepareSourceManagers()
        let initialCompilationTask = LookupRulesTask(sourceManagers: Array(sourceManagers.values))
        let mutex = DispatchSemaphore(value: 0)

        Task {
            try? await initialCompilationTask.lookupCachedRulesLists()
            mutex.signal()
        }
        // We want to confine Compilation work to WorkQueue, so we wait to come back from async Task
        mutex.wait()

        if let result = initialCompilationTask.result {
            let rules = result.map(Rules.init(compilationResult:))
            applyRules(rules)
            return true
        }
        return false
    }

    /*
     Go through source managers and check if there are already compiled rules in the WebKit rule cache.
     Returns true if rules were found, false otherwise.
     */
    private func fetchLastCompiledRules(with lastCompiledRules: [LastCompiledRules]) {
        let initialCompilationTask = LastCompiledRulesLookupTask(sourceRules: rulesSource.contentBlockerRulesLists,
                                                                 lastCompiledRules: lastCompiledRules)
        let mutex = DispatchSemaphore(value: 0)
        Task {
            try? await initialCompilationTask.fetchCachedRulesLists()
            mutex.signal()
        }
        // We want to confine Compilation work to WorkQueue, so we wait to come back from async Task
        mutex.wait()

        if let rules = initialCompilationTask.getFetchedRules() {
            applyRules(rules)
        } else {
            lock.lock()
            state = .idle
            lock.unlock()
        }

        // No matter if rules were found or not, we need to schedule recompilation, after all
        scheduleCompilation()
    }

    private func prepareSourceManagers() {
        rulesSource.contentBlockerRulesLists.forEach { rulesList in
            let sourceManager: ContentBlockerRulesSourceManager
            if let manager = self.sourceManagers[rulesList.name] {
                // Update rules list
                manager.rulesList = rulesList
                sourceManager = manager
            } else {
                let log = self.log
                sourceManager = ContentBlockerRulesSourceManager(rulesList: rulesList,
                                                                 exceptionsSource: self.exceptionsSource,
                                                                 errorReporting: self.errorReporting,
                                                                 log: log)
                self.sourceManagers[rulesList.name] = sourceManager
            }
        }
    }
    
    private func startCompilationProcess() {
        prepareSourceManagers()

        // Prepare compilation tasks based on the sources
        currentTasks = sourceManagers.values.map { sourceManager in

            return CompilationTask(workQueue: workQueue,
                                   rulesList: sourceManager.rulesList,
                                   sourceManager: sourceManager)
        }

        executeNextTask()
    }

    private func executeNextTask() {
        if let nextTask = currentTasks.first(where: { !$0.isCompleted }) {
            nextTask.start { _, _ in
                self.executeNextTask()
            }
        } else {
            compilationCompleted()
        }
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
                for domain in domains.keys where pair.value.hasSuffix(domain) {
                    cnames[pair.key] = pair.value
                    break
                }
            }
        }
        return TrackerData(trackers: trackers, entities: entities, domains: domains, cnames: cnames)
    }

    private func compilationCompleted() {

        var changes = [String: ContentBlockerRulesIdentifier.Difference]()

        lock.lock()

        let newRules: [Rules] = currentTasks.compactMap { task in
            guard let result = task.result else {
                os_log("Failed to complete task %{public}s ", log: self.log, type: .error, task.rulesList.name)
                return nil
            }
            let rules = Rules(compilationResult: result)

            let diff: ContentBlockerRulesIdentifier.Difference
            if let id = _currentRules.first(where: {$0.name == task.rulesList.name })?.identifier {
                diff = id.compare(with: result.model.rulesIdentifier)
            } else {
                diff = result.model.rulesIdentifier.compare(with: ContentBlockerRulesIdentifier(name: task.rulesList.name,
                                                                                                tdsEtag: "",
                                                                                                tempListId: nil,
                                                                                                allowListId: nil,
                                                                                                unprotectedSitesHash: nil))
            }

            changes[task.rulesList.name] = diff
            return rules
        }

        lastCompiledRulesStore?.update(with: newRules)
        applyRules(newRules, changes: changes)

        lock.unlock()
    }
    
    private func applyRules(_ rules: [Rules], changes: [String: ContentBlockerRulesIdentifier.Difference] = [:]) {
        lock.lock()
        
        _currentRules = rules

        let completionTokens: [CompletionToken]
        let compilationTime = compilationStartTime.map { start in CACurrentMediaTime() - start }
        switch state {
        case .recompilingAndScheduled(let currentTokens, let pendingTokens):
            // New work has been scheduled - prepare for execution.
            workQueue.async {
                self.startCompilationProcess()
            }

            completionTokens = currentTokens
            state = .recompiling(currentTokens: pendingTokens)
            compilationStartTime = CACurrentMediaTime()

        case .recompiling(let currentTokens):
            completionTokens = currentTokens
            state = .idle
            compilationStartTime = nil

        case .idle:
            assertionFailure("Unexpected state")
            completionTokens = []
        }
        
        lock.unlock()
        
        let currentIdentifiers: [String] = rules.map { $0.identifier.stringValue }
        updatesSubject.send(UpdateEvent(rules: rules, changes: changes, completionTokens: completionTokens))

        DispatchQueue.main.async {
            if let compilationTime = compilationTime {
                self.errorReporting?.fire(.contentBlockingCompilationTime, parameters: ["compilationTime": String(compilationTime)])
            }

            self.cleanup(currentIdentifiers: currentIdentifiers)
        }
    }

    private func cleanup(currentIdentifiers: [String]) {
        dispatchPrecondition(condition: .onQueue(.main))

        WKContentRuleListStore.default()?.getAvailableContentRuleListIdentifiers { ids in
            let availableIds = Set(ids ?? [])
            var cachedRules = self.cache?.contentRulesCache ?? [:]
            let now = Date()
            let cacheInterval = self.cache?.contentRulesCacheInterval ?? 0
            // cleanup not available or outdated lists from cache
            cachedRules = cachedRules.filter { id, lastUsed in
                availableIds.contains(id) && now.timeIntervalSince(lastUsed) < cacheInterval && lastUsed < now
            }
            // touch current rules
            for id in currentIdentifiers {
                cachedRules[id] = now
            }
            self.cache?.contentRulesCache = cachedRules

            let idsToRemove = availableIds.subtracting(cachedRules.keys)
            for id in idsToRemove {
                WKContentRuleListStore.default()?.removeContentRuleList(forIdentifier: id) { _ in }
            }
        }
    }

}

// swiftlint:enable file_length type_body_length
