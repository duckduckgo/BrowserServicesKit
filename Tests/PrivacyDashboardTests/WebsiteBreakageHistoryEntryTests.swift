//
//  WebsiteBreakageHistoryEntryTests.swift
//  DuckDuckGo
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

import XCTest
@testable import PrivacyDashboard

final class WebsiteBreakageHistoryEntryTests: XCTestCase {

    func testDates() throws {
        let testDate = Date(timeIntervalSince1970: 1704795829)
        let breakageHistory = WebsiteBreakageHistoryEntry(withBreakage: WebsiteBreakageMoks.testBreakage, currentDate: testDate)

        XCTAssertNotNil(breakageHistory)
        XCTAssertEqual("2024-01-09", breakageHistory?.lastSentDayString)
        XCTAssertEqual(1704795829 + (86400*30), breakageHistory?.expiryDate?.timeIntervalSince1970)
    }

    func testUniqueIdentifier() throws {
        let testDate = Date(timeIntervalSince1970: 1704795829)
        let breakageHistory = WebsiteBreakageHistoryEntry(withBreakage: WebsiteBreakageMoks.testBreakage, currentDate: testDate)
        let breakageHistory2 = WebsiteBreakageHistoryEntry(withBreakage: WebsiteBreakageMoks.testBreakage2, currentDate: testDate)
        let breakageHistory3 = WebsiteBreakageHistoryEntry(withBreakage: WebsiteBreakageMoks.testBreakage, currentDate: testDate)

        XCTAssertEqual(breakageHistory?.identifier, breakageHistory3?.identifier)
        XCTAssertNotEqual(breakageHistory?.identifier, breakageHistory2?.identifier)
    }
}
