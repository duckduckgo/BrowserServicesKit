//
//  ContentBlockingRulesCompilationTask.swift
//  DuckDuckGo
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

import Foundation
import WebKit
import os.log
import TrackerRadarKit

extension ContentBlockerRulesManager {

    /**
     Encapsulates compilation steps for a single Task
     */
    class CompilationTask {
        typealias Completion = (_ success: Bool) -> Void
        let workQueue: DispatchQueue
        let rulesList: ContentBlockerRulesList
        let sourceManager: ContentBlockerRulesSourceManager
        let logger: OSLog

        var completed: Bool { result != nil || compilationImpossible }
        var compilationImpossible = false
        var result: (compiledRulesList: WKContentRuleList, model: ContentBlockerRulesSourceModel)?

        init(workQueue: DispatchQueue,
             rulesList: ContentBlockerRulesList,
             sourceManager: ContentBlockerRulesSourceManager,
             logger: OSLog = .disabled) {
            self.workQueue = workQueue
            self.rulesList = rulesList
            self.sourceManager = sourceManager
            self.logger = logger
        }

        func start(completionHandler: @escaping Completion) {
            self.workQueue.async {
                guard let model = self.sourceManager.makeModel() else {
                    self.compilationImpossible = true
                    completionHandler(false)
                    return
                }

                // Delegate querying to main thread - crashes were observed in background.
                DispatchQueue.main.async {
                    let identifier = model.rulesIdentifier.stringValue
                    WKContentRuleListStore.default()?.lookUpContentRuleList(forIdentifier: identifier) { ruleList, _ in
                        if let ruleList = ruleList {
                            self.compilationSucceded(with: ruleList, model: model, completionHandler: completionHandler)
                        } else {
                            self.workQueue.async {
                                self.compile(model: model, completionHandler: completionHandler)
                            }
                        }
                    }
                }
            }
        }

        private func compilationSucceded(with compiledRulesList: WKContentRuleList,
                                         model: ContentBlockerRulesSourceModel,
                                         completionHandler: @escaping Completion) {
            workQueue.async {
                self.result = (compiledRulesList, model)
                completionHandler(true)
            }
        }

        private func compilationFailed(for model: ContentBlockerRulesSourceModel,
                                       with error: Error,
                                       completionHandler: @escaping Completion) {
            workQueue.async {
                os_log("Failed to compile %{public}s rules %{public}s",
                       log: self.logger,
                       type: .error,
                       self.rulesList.name,
                       error.localizedDescription)

                // Retry after marking failed state in the source
                self.sourceManager.compilationFailed(for: model, with: error)

                if let newModel = self.sourceManager.makeModel() {
                    self.compile(model: newModel, completionHandler: completionHandler)
                } else {
                    self.compilationImpossible = true
                    completionHandler(false)
                }
            }
        }

        private func compile(model: ContentBlockerRulesSourceModel,
                             completionHandler: @escaping Completion) {
            os_log("Starting CBR compilation for %{public}s", log: logger, type: .default, rulesList.name)

            let builder = ContentBlockerRulesBuilder(trackerData: model.tds)
            let rules = builder.buildRules(withExceptions: model.unprotectedSites,
                                           andTemporaryUnprotectedDomains: model.tempList,
                                           andTrackerAllowlist: model.allowList)

            let data: Data
            do {
                data = try JSONEncoder().encode(rules)
            } catch {
                os_log("Failed to encode content blocking rules %{public}s", log: logger, type: .error, rulesList.name)
                compilationFailed(for: model, with: error, completionHandler: completionHandler)
                return
            }

            let ruleList = String(data: data, encoding: .utf8)!
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: model.rulesIdentifier.stringValue,
                                         encodedContentRuleList: ruleList) { ruleList, error in

                if let ruleList = ruleList {
                    self.compilationSucceded(with: ruleList, model: model, completionHandler: completionHandler)
                } else if let error = error {
                    self.compilationFailed(for: model, with: error, completionHandler: completionHandler)
                } else {
                    assertionFailure("Rule list has not been returned properly by the engine")
                }
            }
        }
    }

}
