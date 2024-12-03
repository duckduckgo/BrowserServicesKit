//
//  ContentBlockingRulesCompilationTask.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Common
import Foundation
import WebKit
import TrackerRadarKit
import os.log

extension ContentBlockerRulesManager {
    typealias CompilationResult = (compiledRulesList: WKContentRuleList, model: ContentBlockerRulesSourceModel, compilationTime: TimeInterval?)

    /**
     Encapsulates compilation steps for a single Task
     */
    internal class CompilationTask {
        typealias Completion = (_ task: CompilationTask, _ success: Bool) -> Void

        let workQueue: DispatchQueue
        let rulesList: ContentBlockerRulesList
        let sourceManager: ContentBlockerRulesSourceManager
        var isCompleted: Bool { result != nil || compilationImpossible }
        private(set) var compilationImpossible = false
        private(set) var result: CompilationResult?
        private(set) var compilationStartTime: TimeInterval?

        init(workQueue: DispatchQueue,
             rulesList: ContentBlockerRulesList,
             sourceManager: ContentBlockerRulesSourceManager) {
            self.workQueue = workQueue
            self.rulesList = rulesList
            self.sourceManager = sourceManager
        }

        func start(ignoreCache: Bool = false, completionHandler: @escaping Completion) {
            self.workQueue.async {
                guard let model = self.sourceManager.makeModel() else {
                    Logger.contentBlocking.log("❌ compilation impossible")
                    self.compilationImpossible = true
                    completionHandler(self, false)
                    return
                }

                self.compilationStartTime = CACurrentMediaTime()

                guard !ignoreCache else {
                    Logger.contentBlocking.log("❗️ ignoring cache")
                    self.workQueue.async {
                        self.compile(model: model, completionHandler: completionHandler)
                    }
                    return
                }

                // Delegate querying to main thread - crashes were observed in background.
                DispatchQueue.main.async {
                    let identifier = model.rulesIdentifier.stringValue
                    Logger.contentBlocking.debug("Lookup CBR with \(identifier, privacy: .public)")
                    // Todo: how do we exclude this case from compilation time where the result is returned from cache
                    WKContentRuleListStore.default()?.lookUpContentRuleList(forIdentifier: identifier) { ruleList, _ in
                        if let ruleList = ruleList {
                            Logger.contentBlocking.log("🟢 CBR loaded from cache: \(self.rulesList.name, privacy: .public)")
                            self.compilationSucceeded(with: ruleList, model: model, completionHandler: completionHandler)
                        } else {
                            self.workQueue.async {
                                self.compile(model: model, completionHandler: completionHandler)
                            }
                        }
                    }
                }
            }
        }

        private func compilationSucceeded(with compiledRulesList: WKContentRuleList,
                                          model: ContentBlockerRulesSourceModel,
                                          completionHandler: @escaping Completion) {
            workQueue.async {
                let compilationTime = self.compilationStartTime.map { start in CACurrentMediaTime() - start }

                self.result = (compiledRulesList, model, compilationTime)
                completionHandler(self, true)
            }
        }

        private func compilationFailed(for model: ContentBlockerRulesSourceModel,
                                       with error: Error,
                                       completionHandler: @escaping Completion) {
            workQueue.async {
                Logger.contentBlocking.error("❌ Failed to compile \(self.rulesList.name, privacy: .public) rules \(error.localizedDescription, privacy: .public)")

                // Retry after marking failed state in the source
                self.sourceManager.compilationFailed(for: model, with: error)

                if let newModel = self.sourceManager.makeModel() {
                    self.compile(model: newModel, completionHandler: completionHandler)
                } else {
                    self.compilationImpossible = true
                    completionHandler(self, false)
                }
            }
        }

        private func compile(model: ContentBlockerRulesSourceModel,
                             completionHandler: @escaping Completion) {
            Logger.contentBlocking.log("Starting CBR compilation for \(self.rulesList.name, privacy: .public)")

            let builder = ContentBlockerRulesBuilder(trackerData: model.tds)
            let rules = builder.buildRules(withExceptions: model.unprotectedSites,
                                           andTemporaryUnprotectedDomains: model.tempList,
                                           andTrackerAllowlist: model.allowList)

            let data: Data
            do {
                data = try JSONEncoder().encode(rules)
            } catch {
                Logger.contentBlocking.error("❌ Failed to encode content blocking rules \(self.rulesList.name, privacy: .public)")
                compilationFailed(for: model, with: error, completionHandler: completionHandler)
                return
            }

            let ruleList = String(data: data, encoding: .utf8)!
            DispatchQueue.main.async {
                WKContentRuleListStore.default().compileContentRuleList(forIdentifier: model.rulesIdentifier.stringValue,
                                                                        encodedContentRuleList: ruleList) { ruleList, error in

                    if let ruleList = ruleList {
                        Logger.contentBlocking.log("🟢 CBR compilation for \(self.rulesList.name, privacy: .public) succeeded")
                        self.compilationSucceeded(with: ruleList, model: model, completionHandler: completionHandler)
                    } else if let error = error {
                        self.compilationFailed(for: model, with: error, completionHandler: completionHandler)
                    } else {
                        assertionFailure("Rule list has not been returned properly by the engine")
                    }
                }
            }
        }
    }

}
