//
//  ContentBlockerRulesSourceManager.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import TrackerRadarKit

/**
 Encapsulates revision of the Content Blocker Rules source - id/etag of each of the resources used for compilation.
 */
public class ContentBlockerRulesSourceIdentifiers {

    public let name: String
    public let tdsIdentifier: String

    public internal(set) var tempListIdentifier: String?

    public internal(set) var allowListIdentifier: String?

    public internal(set) var unprotectedSitesIdentifier: String?

    init(name: String, tdsIdentfier: String) {
        self.name = name
        self.tdsIdentifier = tdsIdentfier
    }

    public var rulesIdentifier: ContentBlockerRulesIdentifier {
        ContentBlockerRulesIdentifier(name: name,
                                      tdsEtag: tdsIdentifier,
                                      tempListEtag: tempListIdentifier,
                                      allowListEtag: allowListIdentifier,
                                      unprotectedSitesHash: unprotectedSitesIdentifier)
    }
}

/**
 Model used to compile Content Blocking Rules along with Identifiers.
 */
public class ContentBlockerRulesSourceModel: ContentBlockerRulesSourceIdentifiers {

    let tds: TrackerData

    var tempList = [String]()

    var allowList = [TrackerException]()

    var unprotectedSites = [String]()

    init(name: String, tdsIdentfier: String, tds: TrackerData) {
        self.tds = tds
        super.init(name: name, tdsIdentfier: tdsIdentfier)
    }
}

/**
 Manages sources that are used to compile Content Blocking Rules, handles possible broken state by filtering out sources that are potentially corrupted.
 */
public class ContentBlockerRulesSourceManager {

    /**
     Data source for all of the exception info used during compilation.
     */
    private let exceptionsSource: ContentBlockerRulesExceptionsSource

    var rulesList: ContentBlockerRulesList

    /**
     Identifiers of sources that have caused compilation process to fail.
     */
    public private(set) var brokenSources: ContentBlockerRulesSourceIdentifiers?

    private let errorReporting: EventMapping<ContentBlockerDebugEvents>?

    init(rulesList: ContentBlockerRulesList,
         exceptionsSource: ContentBlockerRulesExceptionsSource,
         errorReporting: EventMapping<ContentBlockerDebugEvents>? = nil) {
        self.rulesList = rulesList
        self.exceptionsSource = exceptionsSource
        self.errorReporting = errorReporting
    }

    /**
     Create Source Model based on data source and known broken sources.

     This method takes into account changes to `dataSource` that could fix previously corrupted data set - in such case `brokenSources` state is updated.
     */
    func makeModel() -> ContentBlockerRulesSourceModel {

        // Fetch identifiers up-front
        let tempListIdentifier = exceptionsSource.tempListEtag
        let allowListIdentifier = exceptionsSource.allowListEtag
        let unprotectedSites = exceptionsSource.unprotectedSites
        let unprotectedSitesIdentifier = ContentBlockerRulesIdentifier.hash(domains: unprotectedSites)

        // In case of any broken input that has been changed, reset the broken state and retry full compilation
        if (brokenSources?.tempListIdentifier != nil && brokenSources?.tempListIdentifier != tempListIdentifier) ||
            brokenSources?.unprotectedSitesIdentifier != nil && brokenSources?.unprotectedSitesIdentifier != unprotectedSitesIdentifier ||
            brokenSources?.allowListIdentifier != nil && brokenSources?.allowListIdentifier != allowListIdentifier {
            brokenSources = nil
        }

        // Check which Tracker Data Set to use - fallback to embedded one in case of any issues.
        let result: ContentBlockerRulesSourceModel
        if let trackerData = rulesList.trackerData,
           trackerData.etag != brokenSources?.tdsIdentifier {
            result = ContentBlockerRulesSourceModel(name: rulesList.name,
                                                    tdsIdentfier: trackerData.etag,
                                                    tds: trackerData.tds)
        } else {
            result = ContentBlockerRulesSourceModel(name: rulesList.name,
                                                    tdsIdentfier: rulesList.fallbackTrackerData.etag,
                                                    tds: rulesList.fallbackTrackerData.tds)
        }

        if tempListIdentifier != brokenSources?.tempListIdentifier {
            let tempListDomains = exceptionsSource.tempList
            if !tempListDomains.isEmpty {
                result.tempListIdentifier = tempListIdentifier
                result.tempList = tempListDomains
            }
        }

        if allowListIdentifier != brokenSources?.allowListIdentifier {
            let allowList = exceptionsSource.allowList
            if !allowList.isEmpty {
                result.allowListIdentifier = allowListIdentifier
                result.allowList = allowList
            }
        }

        if unprotectedSitesIdentifier != brokenSources?.unprotectedSitesIdentifier {
            if !unprotectedSites.isEmpty {
                result.unprotectedSitesIdentifier = unprotectedSitesIdentifier
                result.unprotectedSites = unprotectedSites
            }
        }

        return result
    }

    /**
     Process information about last failed compilation in order to update `brokenSources` state.
     */
    func compilationFailed(for input: ContentBlockerRulesSourceIdentifiers, with error: Error) {
        
        if input.tdsIdentifier != rulesList.fallbackTrackerData.etag {
            // We failed compilation for non-embedded TDS, marking it as broken.
            brokenSources = ContentBlockerRulesSourceIdentifiers(name: rulesList.name,
                                                                 tdsIdentfier: input.tdsIdentifier)
            
            errorReporting?.fire(.contentBlockingTDSCompilationFailed,
                                 scope: input.name,
                                 error: error,
                                 parameters: [ContentBlockerDebugEvents.Parameters.etag: input.tdsIdentifier])
        } else if input.tempListIdentifier != nil {
            brokenSources?.tempListIdentifier = input.tempListIdentifier
            errorReporting?.fire(.contentBlockingTempListCompilationFailed,
                                 scope: input.name,
                                 error: error,
                                 parameters: [ContentBlockerDebugEvents.Parameters.etag: input.tempListIdentifier ?? "empty"])
        } else if input.allowListIdentifier != nil {
            brokenSources?.allowListIdentifier = input.allowListIdentifier
            errorReporting?.fire(.contentBlockingAllowListCompilationFailed,
                                 scope: input.name,
                                 error: error,
                                 parameters: [ContentBlockerDebugEvents.Parameters.etag: input.allowListIdentifier ?? "empty"])
        } else if input.unprotectedSitesIdentifier != nil {
            brokenSources?.unprotectedSitesIdentifier = input.unprotectedSitesIdentifier
            errorReporting?.fire(.contentBlockingUnpSitesCompilationFailed,
                                 scope: input.name,
                                 error: error)
        } else {
            // We failed for embedded data, this is unlikely.
            // Include description - why built-in version of the TDS has failed to compile?
            let error = error as NSError
            let errorDesc = (error.userInfo[NSHelpAnchorErrorKey] as? String) ?? "missing"
            let params = [ContentBlockerDebugEvents.Parameters.errorDescription: errorDesc.isEmpty ? "empty" : errorDesc]

            errorReporting?.fire(.contentBlockingFallbackCompilationFailed,
                                 scope: input.name,
                                 error: error,
                                 parameters: params,
                                 onComplete: { _ in
                if input.name == DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName {
                    fatalError("Could not compile embedded rules list")
                }
            })
        }
    }
}
