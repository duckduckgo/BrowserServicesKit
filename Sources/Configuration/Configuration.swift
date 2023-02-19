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
    
    case bloomFilterBinary
    case bloomFilterSpec
    case bloomFilterExcludedDomains
    case privacyConfiguration
    case surrogates
    case trackerRadar
    
    var defaultURL: URL {
        switch self {
        case .bloomFilterBinary: return URL(string: "https://staticcdn.duckduckgo.com/https/https-mobile-v2-bloom.bin")!
        case .bloomFilterSpec: return URL(string: "https://staticcdn.duckduckgo.com/https/https-mobile-v2-bloom-spec.json")!
        case .bloomFilterExcludedDomains: return URL(string: "")!
        case .privacyConfiguration: return URL(string: "whatever")!
        case .surrogates: return URL(string: "")!
        case .trackerRadar: return URL(string: "")!
        }
    }
    
    var url: URL {
        if let customURL = Configuration.customURLs[self] {
            return customURL
        }
        return defaultURL
    }
    
    static func setCustomURL(_ url: URL, for configuration: Configuration) {
        Configuration.customURLs[configuration] = url
    }
    
    private static var customURLs: [Configuration: URL] = [:]
    
}
