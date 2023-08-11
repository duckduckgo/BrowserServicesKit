//
//  ClickToLoadRulesProvider.swift
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

import Foundation
import TrackerRadarKit
import Common
import os.log

public protocol ClickToLoadRulesProviding {

    var globalRules: ContentBlockerRulesManager.Rules? { get }
    func requestException(forDomain domain: String,
                          completion: @escaping (ContentBlockerRulesManager.Rules?) -> Void)

}

public class ClickToLoadRulesProvider: ClickToLoadRulesProviding {

    public enum Constants {
        public static let attributedTempRuleListName = "TemporaryAttributed"
    }

    struct CompilationTask: Equatable {

        let sourceRulesIdentifier: String
        let domain: String
        let completion: (ContentBlockerRulesManager.Rules?) -> Void

        static func == (lhs: ClickToLoadRulesProvider.CompilationTask,
                        rhs: ClickToLoadRulesProvider.CompilationTask) -> Bool {
            return lhs.domain == rhs.domain && lhs.sourceRulesIdentifier == rhs.sourceRulesIdentifier
        }
    }

    private let compiledRulesSource: CompiledRuleListsSource
    private let exceptionsSource: ContentBlockerRulesExceptionsSource

    private let lock = NSLock()
    private var tasks = [CompilationTask]()
    private var isProcessingTask = false

    private let workQueue = DispatchQueue(label: "ClickToLoad compilation queue",
                                          qos: .userInitiated)
    private let getLog: () -> OSLog
    private var log: OSLog {
        getLog()
    }

    public init(compiledRulesSource: CompiledRuleListsSource,
                exceptionsSource: ContentBlockerRulesExceptionsSource,
                log: @escaping @autoclosure () -> OSLog = .disabled) {
        self.compiledRulesSource = compiledRulesSource
        self.exceptionsSource = exceptionsSource
        self.getLog = log
    }

    public var globalRules: ContentBlockerRulesManager.Rules? {
        return compiledRulesSource.currentAttributionRules // ??
    }

    public func requestException(forDomain domain: String,
                                 completion: @escaping (ContentBlockerRulesManager.Rules?) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        os_log(.debug, log: log, "Preparing ctl rules for domain  %{private}s", domain)

        guard let globalAttributionRules = compiledRulesSource.currentAttributionRules else {
            os_log(.error, log: log, "Global ctl list does not exist")
            completion(nil)
            return
        }

        let task = CompilationTask(sourceRulesIdentifier: globalAttributionRules.identifier.stringValue,
                                   domain: domain,
                                   completion: completion)
        tasks.append(task)

        workQueue.async {
            self.popTaskAndExecute()
        }
    }

    private func popTaskAndExecute() {
        lock.lock()
        defer { lock.unlock() }

        guard !isProcessingTask, !tasks.isEmpty else { return }

        let task = tasks.removeFirst()
        isProcessingTask = true
        prepareRules(for: task)
    }

    private func prepareRules(for task: CompilationTask) {
        guard let sourceRules = compiledRulesSource.currentAttributionRules else {
            isProcessingTask = false
            workQueue.async {
                self.popTaskAndExecute()
            }
            return
        }

        os_log(.debug, log: log, "Compiling attribution rules for vendor  %{private}s", task.domain)

        let mutator = ClickToLoadRulesMutator(trackerData: sourceRules.trackerData)
        let attributedRules = mutator.addExceptions(forDomain: task.domain, for: .fb)

        let attributedDataSet = TrackerDataManager.DataSet(tds: attributedRules,
                                                           etag: sourceRules.etag)
        let attributedRulesList = ContentBlockerRulesList(name: Constants.attributedTempRuleListName,
                                                          trackerData: nil,
                                                          fallbackTrackerData: attributedDataSet)

        let log = self.log
        let sourceManager = ContentBlockerRulesSourceManager(rulesList: attributedRulesList,
                                                             exceptionsSource: exceptionsSource,
                                                             log: log)

        let compilationTask = ContentBlockerRulesManager.CompilationTask(workQueue: workQueue,
                                                                         rulesList: attributedRulesList,
                                                                         sourceManager: sourceManager)

        compilationTask.start(ignoreCache: true) { compilationTask, _ in
            self.onTaskCompleted(clickToLoadCompilationTask: task, compilationTask: compilationTask)
        }
    }

    private func onTaskCompleted(clickToLoadCompilationTask: CompilationTask,
                                 compilationTask: ContentBlockerRulesManager.CompilationTask) {
        lock.lock()
        defer { lock.unlock() }

        isProcessingTask = false

        // Take all tasks with same parameters (rules & vendor) and report completion
        // This is optimization: in case multiple tabs request same attribution at the same time, we will respond quickly.
        var matchingTasks = tasks.filter { $0 == clickToLoadCompilationTask }
        tasks.removeAll(where: { $0 == clickToLoadCompilationTask })
        matchingTasks.append(clickToLoadCompilationTask)

        os_log(.debug, log: log,
               "Returning attribution rules for vendor  %{private}s to %{public}d caller(s)",
               clickToLoadCompilationTask.domain, matchingTasks.count)

        let rules = ContentBlockerRulesManager.Rules(task: compilationTask)
        DispatchQueue.main.async {
            for task in matchingTasks {
                task.completion(rules)
            }
        }

        if rules == nil {
            errorReporting?.fire(.adAttributionCompilationFailedForAttributedRulesList)
        }

        workQueue.async {
            self.popTaskAndExecute()
        }
    }
}

