//
//  AppAttributeMatcherTests.swift
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

import XCTest
import Foundation
@testable import Common
@testable import BrowserServicesKit
@testable import RemoteMessaging

class AppAttributeMatcherTests: XCTestCase {

    private var matcher: AppAttributeMatcher!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let mockStatisticsStore = MockStatisticsStore()
        mockStatisticsStore.atb = "v105-2"
        mockStatisticsStore.appRetentionAtb = "v105-44"
        mockStatisticsStore.searchRetentionAtb = "v105-88"

        let manager = MockVariantManager(isSupportedReturns: true, currentVariant: MockVariant(name: "zo", weight: 44, isIncluded: { return true }, features: [.dummy]))
        matcher = AppAttributeMatcher(statisticsStore: mockStatisticsStore,
                                      variantManager: manager)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        matcher = nil
    }

    func testWhenIsInternalUserMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: IsInternalUserMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenIsInternalUserDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: IsInternalUserMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    func testWhenAppIdMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppIdMatchingAttribute(value: Bundle.main.bundleIdentifier, fallback: false)),
                       .match)
    }

    func testWhenAppIdDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppIdMatchingAttribute(value: "non-matching", fallback: false)),
                       .fail)
    }

    func testWhenAppVersionEqualOrLowerThanMaxThenReturnMatch() throws {
        let appVersionComponents = AppVersion.shared.versionAndBuildNumber.components(separatedBy: ".").map { $0 }
        let appMajorVersion = appVersionComponents[0]
        let appMinorVersion = appVersionComponents.suffix(from: 1).joined(separator: ".")

        let greaterThanMax = String(Int(appMajorVersion)! + 1)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(min: appMinorVersion, max: greaterThanMax, fallback: nil)),
                       .match)

        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(max: greaterThanMax, fallback: nil)),
                       .match)

        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(min: appMajorVersion, max: greaterThanMax, fallback: nil)),
                       .match)
    }

    func testWhenAppVersionGreaterThanMaxThenReturnFail() throws {
        let appVersionComponents = AppVersion.shared.versionAndBuildNumber.components(separatedBy: ".").map { $0 }
        let appMajorVersion = appVersionComponents[0]
        let lessThanMax = String(Int(appMajorVersion)! - 1)

        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(max: lessThanMax, fallback: nil)),
                       .fail)
    }

    func testWhenAppVersionEqualOrGreaterThanMinThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(min: AppVersion.shared.versionAndBuildNumber, fallback: nil)),
                       .match)
    }

    func testWhenAppVersionLowerThanMinThenReturnFail() throws {
        let appVersionComponents = AppVersion.shared.versionAndBuildNumber.components(separatedBy: ".").map { $0 }
        let appMajorVersion = appVersionComponents[0]
        let greaterThanMax = String(Int(appMajorVersion)! + 1)
        let greaterThanMinorVersion = Float(appVersionComponents.suffix(from: 1).joined(separator: "."))! + 0.1

        let minBumped = "\(appMajorVersion).\(greaterThanMinorVersion)"
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(min: minBumped, max: greaterThanMax, fallback: nil)),
                       .fail)
    }

    func testWhenAppVersionInRangeThenReturnMatch() throws {
        let appVersionComponents = AppVersion.shared.versionAndBuildNumber.components(separatedBy: ".").map { $0 }
        let appMajorVersion = appVersionComponents[0]
        let greaterThanMax = String(Int(appMajorVersion)! + 1)
        let lessThanMinorVersion = Float(appVersionComponents.suffix(from: 1).joined(separator: "."))! - 0.1
        let minBumped = "\(appMajorVersion).\(lessThanMinorVersion)"

        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(min: minBumped, max: greaterThanMax, fallback: nil)),
                       .match)
    }

    func testWhenAppVersionNotInRangeThenReturnFail() throws {
        let appVersionComponents = AppVersion.shared.versionAndBuildNumber.components(separatedBy: ".").map { $0 }
        let appMajorVersion = appVersionComponents[0]
        let greaterThanMax = String(Int(appMajorVersion)! + 1)

        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(min: greaterThanMax, max: greaterThanMax, fallback: nil)),
                       .fail)
    }

    func testWhenAppVersionSameAsDeviceThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(min: AppVersion.shared.versionAndBuildNumber, max: AppVersion.shared.versionAndBuildNumber, fallback: nil)),
                       .match)
    }

    func testWhenAppVersionDifferentToDeviceThenReturnFail() throws {
        let appVersionComponents = AppVersion.shared.versionAndBuildNumber.components(separatedBy: ".").map { $0 }
        let appMajorVersion = appVersionComponents[0]
        let lessThanMinorVersion = Float(appVersionComponents.suffix(from: 1).joined(separator: "."))! - 0.1
        let minBumped = "\(appMajorVersion).\(lessThanMinorVersion)"

        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppVersionMatchingAttribute(value: minBumped, fallback: nil)),
                       .fail)
    }

    func testWhenAtbMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AtbMatchingAttribute(value: "v105-2", fallback: nil)),
                       .match)
    }

    func testWhenAtbDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AtbMatchingAttribute(value: "v105-0", fallback: nil)),
                       .fail)
    }

    func testWhenAppAtbMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppAtbMatchingAttribute(value: "v105-44", fallback: nil)),
                       .match)
    }

    func testWhenAppAtbDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppAtbMatchingAttribute(value: "no-soup-for-you", fallback: nil)),
                       .fail)
    }

    func testWhenSearchAtbMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: SearchAtbMatchingAttribute(value: "v105-88", fallback: nil)),
                       .match)
    }

    func testWhenSearchAtbDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: SearchAtbMatchingAttribute(value: "no-comprehende-mi-amigo", fallback: nil)),
                       .fail)
    }

    func testWhenExpVariantMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: ExpVariantMatchingAttribute(value: "zo", fallback: nil)),
                       .match)
    }

    func testWhenExpVariantDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: ExpVariantMatchingAttribute(value: "nein-freundlich", fallback: nil)),
                       .fail)
    }

}

class MockVariant: Variant {
    var name: String

    var weight: Int

    var isIncluded: () -> Bool

    var features: [FeatureName]

    init(name: String, weight: Int, isIncluded: @escaping () -> Bool, features: [FeatureName]) {
        self.name = name
        self.weight = weight
        self.isIncluded = isIncluded
        self.features = features
    }
}
