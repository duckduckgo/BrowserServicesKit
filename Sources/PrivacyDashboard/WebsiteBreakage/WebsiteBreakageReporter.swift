//
//  File.swift
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
import OSLog
import Persistence

public protocol WebsiteBreakagePersistencyManaging {

    func getBreakageHistory(forDomainIdentifier domainIdentifier: String) throws -> WebsiteBreakageHistoryEntry?
    func persist(breakegeHistory: WebsiteBreakageHistoryEntry) throws
}

public enum WebsiteBreakageReporterError: Error {

    case failedToGenerateHistoryEntry
    case missingExpiryDate
}

/// Class responsible of reporting broken sites
///  The actual report is sent via Pixel from the main app, this class only persists the reports' history and prepares the models.
public class WebsiteBreakageReporter {

    /// A closure that receives the Pixel's parameters
    public typealias PixelHandler = (_ parameters: [String: String]) -> Void
    /// Pixels are sent by the main apps not by BSK, this is the closure called by the class when a pixel need to be sent
    let pixelHandler: PixelHandler
    let persistencyManager: ExpiryStorage

    public init(pixelHandler: @escaping PixelHandler, keyValueStoring: KeyValueStoringDictionaryRepresentable) {
        self.pixelHandler = pixelHandler
        self.persistencyManager = ExpiryStorage(keyValueStoring: keyValueStoring)
    }

    /// Report the site breakage
    public func report(breakage: WebsiteBreakage) throws {

        let now = Date()
        let removedCount = persistencyManager.removeExpiredItems(currentDate: now)
        if removedCount > 0 {
            os_log(.debug, "\(removedCount) breakage history record removed")
        }

        var breakage = breakage

        // Create history entry
        guard let historyEntry = WebsiteBreakageHistoryEntry(withBreakage: breakage, currentDate: now) else {
            os_log(.error, "Failed to create a history entry for breakage report")
            throw WebsiteBreakageReporterError.failedToGenerateHistoryEntry
        }

        os_log(.debug, "Reporting website breakage for \(breakage.siteUrl.absoluteString)")

        // Check if the report has been sent before
        if let storedHistoryEntry = try persistencyManager.getBreakageHistory(forDomainIdentifier: historyEntry.identifier) {
            breakage.lastSentDay = storedHistoryEntry.lastSentDayString
            os_log(.debug, "Breakage report sent on the \(breakage.lastSentDay ?? "?") for \(breakage.siteUrl.absoluteString) ID:\(historyEntry.identifier)")
        }

        let pixelParams = breakage.requestParameters

        // report the breakage
        pixelHandler(pixelParams)

        // persist history entry
        try persistencyManager.persist(breakegeHistory: historyEntry) // this overrides the previously stored entry if existed

        os_log(.debug, "Website breakage reported for \(breakage.siteUrl.absoluteString)")
    }
}

extension ExpiryStorage: WebsiteBreakagePersistencyManaging {

    public func getBreakageHistory(forDomainIdentifier domainIdentifier: String) throws -> WebsiteBreakageHistoryEntry? {

        if let savedData = value(forKey: domainIdentifier) as? String {
            return WebsiteBreakageHistoryEntry(safeDomainIdentifier: domainIdentifier, lastSentDayString: savedData)
        }
        return nil
    }

    public func persist(breakegeHistory: WebsiteBreakageHistoryEntry) throws {

        guard let expirydate = breakegeHistory.expiryDate else {
            throw WebsiteBreakageReporterError.missingExpiryDate
        }
        set(value: breakegeHistory.lastSentDayString, forKey: breakegeHistory.identifier, expiryDate: expirydate)
    }
}
