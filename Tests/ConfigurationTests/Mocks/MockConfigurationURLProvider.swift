//
//  MockConfigurationURLProvider.swift
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
import Configuration

struct MockConfigurationURLProvider: ConfigurationURLProviding {

    func url(for configuration: Configuration) -> URL {
        switch configuration {
        case .bloomFilterBinary:
            return URL(string: "a")!
        case .bloomFilterSpec:
            return URL(string: "b")!
        case .bloomFilterExcludedDomains:
            return URL(string: "c")!
        case .privacyConfiguration:
            return URL(string: "d")!
        case .surrogates:
            return URL(string: "e")!
        case .trackerDataSet:
            return URL(string: "f")!
        case .FBConfig:
            return URL(string: "g")!
        case .remoteMessagingConfig:
            return URL(string: "h")!
        }
    }

}
