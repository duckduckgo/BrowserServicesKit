//
//  File.swift
//  
//
//  Created by Alexey Martemianov on 02.02.2022.
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
        // swiftlint:disable:next nesting
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

            guard let model = sourceManager.makeModel() else {
                compilationImpossible = true
                completionHandler(false)
                return
            }

            // Delegate querying to main thread - crashes were observed in background.
            DispatchQueue.main.async {
                WKContentRuleListStore.default()?.lookUpContentRuleList(forIdentifier: model.rulesIdentifier.stringValue,
                                                                        completionHandler: { ruleList, _ in
                    if let ruleList = ruleList {
                        self.compilationSucceded(with: ruleList, model: model, completionHandler: completionHandler)
                    } else {
                        self.workQueue.async {
                            self.compile(model: model, completionHandler: completionHandler)
                        }
                    }
                })
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
