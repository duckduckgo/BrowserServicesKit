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

public enum Configuration {
    
    case bloomFilter
    case bloomFilterSpec
    case privacyConfig
    
}

public struct ConfigurationManager {
    
    let store: ConfigurationStoring
    // provide custom url mapping <-
    
//    func fetchBloomFilter() async {
//        let fetcher = ConfigurationFetcher(store: store)
//        do {
//            try await fetcher.fetch([.init(configuration: .bloomFilter),
//                                     .init(configuration: .bloomFilterSpec)])
//            // update https upgrade!
//            try await fetcher.fetch([.init(configuration: .privacyConfig)])
//            // update privacy config!
//
//            // and so on...
//
//        } catch {
//            print(error)
//        }
//    }
    
}
