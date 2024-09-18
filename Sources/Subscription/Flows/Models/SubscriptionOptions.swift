//
//  SubscriptionOptions.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public struct SubscriptionOptions: Encodable, Equatable {
    let platform: String
    let options: [SubscriptionOption]
    let features: [SubscriptionFeature]
    public static var empty: SubscriptionOptions {
        let features = SubscriptionFeatureName.allCases.map { SubscriptionFeature(name: $0.rawValue) }
        let platform: SubscriptionPlatformName
#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif
        return SubscriptionOptions(platform: platform.rawValue, options: [], features: features)
    }
}

public struct SubscriptionOption: Encodable, Equatable {
    let id: String
    let cost: SubscriptionOptionCost
}

struct SubscriptionOptionCost: Encodable, Equatable {
    let displayPrice: String
    let recurrence: String
}

public struct SubscriptionFeature: Encodable, Equatable {
    let name: String
}
