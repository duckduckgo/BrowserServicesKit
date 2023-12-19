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

        typealias LookupResult = (compiledRulesList: WKContentRuleList, model: ContentBlockerRulesSourceModel)

        private let sourceManagers: [ContentBlockerRulesSourceManager]

        public private(set) var result: [LookupResult]?

        init(sourceManagers: [ContentBlockerRulesSourceManager]) {
            self.sourceManagers = sourceManagers
        }

        func lookupCachedRulesLists() async throws {

            var result = [LookupResult]()
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

                result.append((ruleList, model))
            }
            self.result = result
        }

    }
}
