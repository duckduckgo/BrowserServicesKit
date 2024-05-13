//
//  SubscriptionEnvironment.swift
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

public struct SubscriptionEnvironment: Codable {

    public enum ServiceEnvironment: Codable {
        case production, staging

        public var description: String {
            switch self {
            case .production: return "Production"
            case .staging: return "Staging"
            }
        }
    }

    public enum Platform: String, Codable {
        case appStore, stripe
    }

    public var serviceEnvironment: SubscriptionEnvironment.ServiceEnvironment
    public var platform: SubscriptionEnvironment.Platform

    public init(serviceEnvironment: SubscriptionEnvironment.ServiceEnvironment,
         platform: SubscriptionEnvironment.Platform) {
        self.serviceEnvironment = serviceEnvironment
        self.platform = platform
    }

    public static var `default`: SubscriptionEnvironment {
        #if os(OSX)
#if APPSTORE || !STRIPE
        let platform: SubscriptionEnvironment.Platform = .appStore
#else
        let platform: SubscriptionEnvironment.Platform = .stripe
#endif
        #else
        let platform: SubscriptionEnvironment.Platform = .appStore
        #endif

#if ALPHA || DEBUG
        let environment: SubscriptionEnvironment.ServiceEnvironment = .staging
#else
        let environment: SubscriptionEnvironment.ServiceEnvironment = .production
#endif
        return SubscriptionEnvironment(serviceEnvironment: environment, platform: platform)
    }
}
