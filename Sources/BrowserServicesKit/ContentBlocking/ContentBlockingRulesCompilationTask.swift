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
    
    internal struct CompilationResult {
        let compiledRulesList: WKContentRuleList
        let model: ContentBlockerRulesSourceModel
        let resultType: ResultType
        let performanceInfo: PerformanceInfo?

        struct PerformanceInfo {
            let compilationTime: TimeInterval
            let iterationCount: Int

            // if none of the sources are broken, we do a minimum of one iteration which should be successful
            init(compilationTime: TimeInterval, iterationCount: Int = 1) {
                   self.compilationTime = compilationTime
                   self.iterationCount = iterationCount
               }
        }
        
        enum ResultType {
            case cacheLookup
            case rulesCompilation
        }
    }
    
    
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
                            self.compilationSucceeded(with: ruleList,
                                                      model: model,
                                                      resultType: .cacheLookup,
                                                      completionHandler: completionHandler)
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
                                          resultType: CompilationResult.ResultType,
                                          completionHandler: @escaping Completion) {
            
            self.result = self.getCompilationResult(ruleList: compiledRulesList,
                                                    model: model,
                                                    resultType: resultType)
            
            workQueue.async {
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
                        self.compilationSucceeded(with: ruleList,
                                                  model: model,
                                                  resultType: .rulesCompilation,
                                                  completionHandler: completionHandler)
                    } else if let error = error {
                        self.compilationFailed(for: model, with: error, completionHandler: completionHandler)
                    } else {
                        assertionFailure("Rule list has not been returned properly by the engine")
                    }
                }
            }
        }
        
        func getCompilationResult(ruleList: WKContentRuleList,
                                  model: ContentBlockerRulesSourceModel,
                                  resultType: CompilationResult.ResultType) -> CompilationResult {
            let compilationTime = self.compilationStartTime.map { CACurrentMediaTime() - $0 }

            let perfInfo = compilationTime.map {
                CompilationResult.PerformanceInfo(compilationTime: $0,
                                                  iterationCount: getCompilationRetryCount())
            }

            return CompilationResult(compiledRulesList: ruleList,
                                            model: model,
                                            resultType: resultType,
                                     performanceInfo: perfInfo)
            
        }

        func getCompilationRetryCount() -> Int {
            guard let brokenSources = sourceManager.brokenSources else {
                // if none of the sources are broken, we do a minimum of one iteration which should be successful
                return 1
            }
                
            let identifiers = [
                brokenSources.allowListIdentifier,
                brokenSources.tempListIdentifier,
                brokenSources.unprotectedSitesIdentifier,
                brokenSources.tdsIdentifier
            ]

            // add 1 to account for the first iteration before we retry with any broken sources
            return (identifiers.compactMap { $0 }.count) + 1
        }

    }

}
