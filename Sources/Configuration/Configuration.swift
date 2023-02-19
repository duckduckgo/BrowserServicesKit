//
//  Configuration.swift
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
//import API

public enum Configuration {
    
    case bloomFilterBinary
    case bloomFilterSpec
    case bloomFilterExcludedDomains
    case privacyConfiguration
    case surrogates
    case trackerRadar
    
}

//public struct ConfigurationManager {
//
//    let store: ConfigurationStoring
//    let onDidStore: (() -> Void)?
//    let userAgent: APIHeaders.UserAgent
//
//
//
//    func fetchBloomFilter(withCustomUrls customUrls: [(configuration: Configuration, url: URL)] = []) async {
//        let tasks = mergeTasks([ConfigurationFetchTask(configuration: .bloomFilterBinary),
//                                ConfigurationFetchTask(configuration: .bloomFilterSpec)],
//                               withCustomUrls: customUrls)
//
//        let fetcher = ConfigurationFetcher(store: store, onDidStore: {}, userAgent: "")
//        do {
//            fetcher.fetch([])
//            try await fetcher.fetch(tasks)
//        } catch {
//
//        }
//    }
//
//    private func mergeTasks(_ tasks: [ConfigurationFetchTask],
//                            withCustomUrls customUrls: [(configuration: Configuration, url: URL)]) -> [ConfigurationFetchTask] {
//        return tasks.map { task in
//            let customUrl = customUrls.first(where: { $0.configuration == task.configuration })?.url
//            return ConfigurationFetchTask(configuration: task.configuration,
//                                          url: customUrl ?? task.url)
//        }
//    }
//
//}
