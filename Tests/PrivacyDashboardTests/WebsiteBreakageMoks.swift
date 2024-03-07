//
//  WebsiteBreakageMoks.swift
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
import Macros
import PrivacyDashboard

struct WebsiteBreakageMoks {

    static var testBreakage: WebsiteBreakage {
        WebsiteBreakage(siteUrl: #URL("https://duckduckgo.com"),
                        category: "test",
                        description: "test",
                        osVersion: "test",
                        manufacturer: "Apple",
                        upgradedHttps: true,
                        tdsETag: "test",
                        blockedTrackerDomains: [],
                        installedSurrogates: [],
                        isGPCEnabled: true,
                        ampURL: "test",
                        urlParametersRemoved: true,
                        protectionsState: true,
                        reportFlow: .appMenu,
                        errors: nil,
                        httpStatusCodes: nil)
    }

    static var testBreakage2: WebsiteBreakage {
        WebsiteBreakage(siteUrl: #URL("https://somethingelse.zz"),
                        category: "test",
                        description: "test",
                        osVersion: "test",
                        manufacturer: "Apple",
                        upgradedHttps: true,
                        tdsETag: "test",
                        blockedTrackerDomains: [],
                        installedSurrogates: [],
                        isGPCEnabled: true,
                        ampURL: "test",
                        urlParametersRemoved: true,
                        protectionsState: true,
                        reportFlow: .appMenu,
                        errors: nil,
                        httpStatusCodes: nil)
    }

    static var testBreakage3: WebsiteBreakage {
        WebsiteBreakage(siteUrl: #URL("https://www.subdomain.example.com/some/pathname?t=param#aaa"),
                        category: "test",
                        description: "test",
                        osVersion: "test",
                        manufacturer: "Apple",
                        upgradedHttps: true,
                        tdsETag: "test",
                        blockedTrackerDomains: [],
                        installedSurrogates: [],
                        isGPCEnabled: true,
                        ampURL: "test",
                        urlParametersRemoved: true,
                        protectionsState: true,
                        reportFlow: .appMenu,
                        errors: nil,
                        httpStatusCodes: nil)
    }
}
