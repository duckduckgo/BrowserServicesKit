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

    public enum SiteType: String {
        case desktop
        case mobile
    }

    public enum OpenerContext: String {
        case serp
        case external
        case navigation
    }

    public static let allowedQueryReservedCharacters = CharacterSet(charactersIn: ",")

    let siteUrl: URL
    let category: String
    let description: String?
    let osVersion: String
    let manufacturer: String
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
    let errors: [Error]?
    let httpStatusCodes: [Int]?
    let openerContext: OpenerContext?
    let vpnOn: Bool
    let jsPerformance: [Double]?
    let userRefreshCount: Int
#if os(iOS)
    let siteType: SiteType // ?? not in documentation
    let atb: String
    let model: String
#endif

#if os(macOS)
    public init(
        siteUrl: URL,
        category: String,
        description: String?,
        osVersion: String,
        manufacturer: String,
        upgradedHttps: Bool,
        tdsETag: String?,
        blockedTrackerDomains: [String]?,
        installedSurrogates: [String]?,
        isGPCEnabled: Bool,
        ampURL: String,
        urlParametersRemoved: Bool,
        protectionsState: Bool,
        reportFlow: Source,
        errors: [Error]?,
        httpStatusCodes: [Int]?,
        openerContext: OpenerContext?,
        vpnOn: Bool,
        jsPerformance: [Double]?,
        userRefreshCount: Int
    ) {
        self.siteUrl = siteUrl
        self.category = category
        self.description = description
        self.osVersion = osVersion
        self.manufacturer = manufacturer
        self.upgradedHttps = upgradedHttps
        self.tdsETag = tdsETag
        self.blockedTrackerDomains = blockedTrackerDomains ?? []
        self.installedSurrogates = installedSurrogates ?? []
        self.isGPCEnabled = isGPCEnabled
        self.ampURL = ampURL
        self.protectionsState = protectionsState
        self.urlParametersRemoved = urlParametersRemoved
        self.reportFlow = reportFlow
        self.errors = errors
        self.httpStatusCodes = httpStatusCodes
        self.openerContext = openerContext
        self.vpnOn = vpnOn
        self.jsPerformance = jsPerformance
        self.userRefreshCount = userRefreshCount
    }
#endif

#if os(iOS)
    public init(
        siteUrl: URL,
        category: String,
        description: String?,
        osVersion: String,
        manufacturer: String,
        upgradedHttps: Bool,
        tdsETag: String?,
        blockedTrackerDomains: [String]?,
        installedSurrogates: [String]?,
        isGPCEnabled: Bool,
        ampURL: String,
        urlParametersRemoved: Bool,
        protectionsState: Bool,
        reportFlow: Source,
        siteType: SiteType,
        atb: String,
        model: String,
        errors: [Error]?,
        httpStatusCodes: [Int]?,
        openerContext: OpenerContext?,
        vpnOn: Bool,
        jsPerformance: [Double]?,
        userRefreshCount: Int
    ) {
        self.siteUrl = siteUrl
        self.category = category
        self.description = description
        self.osVersion = osVersion
        self.manufacturer = manufacturer
        self.upgradedHttps = upgradedHttps
        self.tdsETag = tdsETag
        self.blockedTrackerDomains = blockedTrackerDomains ?? []
        self.installedSurrogates = installedSurrogates ?? []
        self.isGPCEnabled = isGPCEnabled
        self.ampURL = ampURL
        self.protectionsState = protectionsState
        self.urlParametersRemoved = urlParametersRemoved
        self.reportFlow = reportFlow
        self.siteType = siteType
        self.atb = atb
        self.model = model
        self.errors = errors
        self.httpStatusCodes = httpStatusCodes
        self.openerContext = openerContext
        self.vpnOn = vpnOn
        self.jsPerformance = jsPerformance
        self.userRefreshCount = userRefreshCount
    }
#endif

    /// A dictionary containing all the parameters needed from the Report Broken Site Pixel
    public var requestParameters: [String: String] {
        var result: [String: String] = [
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
            "manufacturer": manufacturer,
            "reportFlow": reportFlow.rawValue,
            "protectionsState": protectionsState ? "true" : "false",
            "openerContext": openerContext?.rawValue ?? "",
            "vpnOn": vpnOn ? "true" : "false",
            "userRefreshCount": String(userRefreshCount)
        ]

        if let lastSentDay = lastSentDay {
            result["lastSentDay"] = lastSentDay
        }

        if let httpStatusCodes {
            let codes: [String] = httpStatusCodes.map { String($0) }
            result["httpErrorCodes"] = codes.joined(separator: ",")
        }

        if let errors {
            let errorDescriptions: [String] = errors.map {
                let error = $0 as NSError
                return "\(error.code) - \(error.domain):\(error.localizedDescription)"
            }
            result["errorDescriptions"] = errorDescriptions.joined(separator: ",")
        }

        if let jsPerformance {
            let perf = jsPerformance.map { String($0) }.joined(separator: ",")
            result["jsPerformance"] = perf
        }

#if os(iOS)
        result["siteType"] = siteType.rawValue
        result["atb"] = atb
        result["model"] = model
#endif
        return result
    }
}
