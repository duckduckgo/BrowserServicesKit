//
//  WebsiteBreakage.swift
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
//  Implementation guidelines: https://app.asana.com/0/1198207348643509/1200202563872939/f

import Foundation

/// Model containing all the info required for a report broken site submission
public struct WebsiteBreakage {

    /// The source of the broken site report
    public enum Source: String {
        /// The app menu
        case appMenu = "menu"
        /// From the privacy dashboard
        case dashboard
    }

    let siteUrl: URL
    let category: String
    let description: String?
    let osVersion: String
    let upgradedHttps: Bool
    let tdsETag: String?
    let blockedTrackerDomains: [String]
    let installedSurrogates: [String]
    let isGPCEnabled: Bool
    let ampURL: String
    let urlParametersRemoved: Bool
    let reportFlow: Source
    let protectionsState: Bool
    var lastSentDay: String?
#if os(iOS)
    let isDesktop: Bool // ?? not in documentation
    let atb: String
    let model: String
#endif

    public init(
        siteUrl: URL,
        category: String,
        description: String?,
        osVersion: String,
        upgradedHttps: Bool,
        tdsETag: String?,
        blockedTrackerDomains: [String]?,
        installedSurrogates: [String]?,
        isGPCEnabled: Bool,
        ampURL: String,
        urlParametersRemoved: Bool,
        protectionsState: Bool,
        reportFlow: Source,
        isDesktop: Bool,
        atb: String,
        model: String
    ) {
        self.siteUrl = siteUrl
        self.category = category
        self.description = description
        self.osVersion = osVersion
        self.upgradedHttps = upgradedHttps
        self.tdsETag = tdsETag
        self.blockedTrackerDomains = blockedTrackerDomains ?? []
        self.installedSurrogates = installedSurrogates ?? []
        self.isGPCEnabled = isGPCEnabled
        self.ampURL = ampURL
        self.protectionsState = protectionsState
        self.urlParametersRemoved = urlParametersRemoved
        self.reportFlow = reportFlow

#if os(iOS)
        self.isDesktop = isDesktop
        self.atb = atb
        self.model = model
#endif
    }

    /// A dictionary containing all the parameters needed from the Report Broken Site Pixel
    public var requestParameters: [String: String] {
        var result = [
            "siteUrl": siteUrl.trimmingQueryItemsAndFragment().absoluteString,
            "category": category,
            "description": description ?? "",
            "upgradedHttps": upgradedHttps ? "true" : "false",
            "tds": tdsETag?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "",
            "blockedTrackers": blockedTrackerDomains.joined(separator: ","),
            "surrogates": installedSurrogates.joined(separator: ","),
            "gpc": isGPCEnabled ? "true" : "false",
            "ampUrl": ampURL,
            "urlParametersRemoved": urlParametersRemoved ? "true" : "false",
            "os": osVersion,
            "manufacturer": "Apple",
            "reportFlow": reportFlow.rawValue,
            "protectionsState": protectionsState ? "true" : "false"
        ]

        if let lastSentDay = lastSentDay {
            result["lastSentDay"] = lastSentDay
        }

#if os(iOS)
        result["siteType"] = isDesktop ? "desktop" : "mobile"
        result["atb"] = atb
        result["model"] = model
#endif
        return result
    }
}
