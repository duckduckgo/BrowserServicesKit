//
//  ContentBlockingRulesLookupTask.swift
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
import TrackerRadarKit

extension ContentBlockerRulesManager {

    final class LookupRulesTask {

        //This type has been overloaded multiple times, I'm collapsing them all into CompilationResult type
        //typealias LookupResult = (compiledRulesList: WKContentRuleList, model: ContentBlockerRulesSourceModel)

        private let sourceManagers: [ContentBlockerRulesSourceManager]

        ////todo: how to get around calling this compilation result when in lookuptask?
        public private(set) var result: [CompilationResult]?

        init(sourceManagers: [ContentBlockerRulesSourceManager]) {
            self.sourceManagers = sourceManagers
        }

        func lookupCachedRulesLists() async throws {

            var result = [CompilationResult]()
            for sourceManager in sourceManagers {
                guard let model = sourceManager.makeModel() else {
                    throw WKError(.contentRuleListStoreLookUpFailed)
                }

                guard let ruleList = try await Task(operation: { @MainActor in
                    try await WKContentRuleListStore.default().contentRuleList(forIdentifier: model.rulesIdentifier.stringValue)
                }).value else {
                    // All lists must be found for this to be considered successful
                    throw WKError(.contentRuleListStoreLookUpFailed)
                }

                result.append((ruleList, model, nil))
            }
            self.result = result
        }

    }
}
