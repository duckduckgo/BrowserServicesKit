//
//  TDSOverrideExperimentMetricsTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import PixelExperimentKit
import BrowserServicesKit
import Configuration
import PixelKit

final class TDSOverrideExperimentMetricsTests: XCTestCase {

    var mockFeatureFlagger: MockFeatureFlagger!
    var pixelCalls: [(SubfeatureID, String, ClosedRange<Int>, String)] = []
    var debugCalls: [[String: String]] = []

    override func setUpWithError() throws {
        mockFeatureFlagger = MockFeatureFlagger()
        PixelKit.configureExperimentKit(featureFlagger: mockFeatureFlagger, eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()), fire: { _, _, _ in })
        TDSOverrideExperimentMetrics.configureTDSOverrideExperimentMetrics { subfeatureID, metric, conversionWindow, value in
            self.pixelCalls.append((subfeatureID, metric, conversionWindow, value))
        }
    }

    override func tearDownWithError() throws {
        mockFeatureFlagger = nil
    }

    func test_OnfireTdsExperimentMetricPrivacyToggleUsed_WhenExperimentActive_ThenCorrectPixelFunctionsCalled() {
        // GIVEN
        mockFeatureFlagger.experiments = [
            TdsExperimentType.allCases[3].subfeature.rawValue: ExperimentData(parentID: "someParentID", cohortID: "testCohort", enrollmentDate: Date())
        ]

        // WHEN
        TDSOverrideExperimentMetrics.fireTdsExperimentMetric(metricType: .privacyToggleUsed, etag: "testEtag") { parameters in
            self.debugCalls.append(parameters)
        }

        // THEN
        XCTAssertEqual(pixelCalls.count, TdsExperimentType.allCases.count * 6, "firePixelExperiment should be called for each experiment and each conversionWindow 0...5.")
        XCTAssertEqual(pixelCalls.first?.0, TdsExperimentType.allCases[0].subfeature.rawValue, "expected SubfeatureID should be passed as parameter")
        XCTAssertEqual(pixelCalls.first?.1, "privacyToggleUsed", "expected metric should be passed as parameter")
        XCTAssertEqual(pixelCalls.first?.2, 0...0, "expected Conversion Window should be passed as parameter")
        XCTAssertEqual(pixelCalls.first?.3, "1", "expected Value should be passed as parameter")
        XCTAssertEqual(debugCalls.count, 6, "fireDebugExperiment should be called for each conversionWindow on one experiment.")
        XCTAssertEqual(debugCalls.first?["tdsEtag"], "testEtag")
        XCTAssertEqual(debugCalls.first?["experiment"], "\(TdsExperimentType.allCases[3].experiment.rawValue)testCohort")
    }

    func test_OnfireTdsExperimentMetricPrivacyToggleUsed_WhenNoExperimentActive_ThenCorrectPixelFunctionsCalled() {
        // WHEN
        TDSOverrideExperimentMetrics.fireTdsExperimentMetric(metricType: .privacyToggleUsed, etag: "testEtag") { parameters in
            self.debugCalls.append(parameters)
        }

        // THEN
        XCTAssertEqual(pixelCalls.count, TdsExperimentType.allCases.count * 6, "firePixelExperiment should be called for each experiment and each conversionWindow 0...5.")
        XCTAssertEqual(pixelCalls.first?.0, TdsExperimentType.allCases[0].subfeature.rawValue, "expected SubfeatureID should be passed as parameter")
        XCTAssertEqual(pixelCalls.first?.1, "privacyToggleUsed", "expected metric should be passed as parameter")
        XCTAssertEqual(pixelCalls.first?.2, 0...0, "expected Conversion Window should be passed as parameter")
        XCTAssertEqual(pixelCalls.first?.3, "1", "expected Value should be passed as parameter")
        XCTAssertTrue(debugCalls.isEmpty)
    }

    func test_OnGetActiveTDSExperimentNameWithCohort_WhenExperimentActive_ThenCorrectExperimentNameReturned() {
        // GIVEN
        mockFeatureFlagger.experiments = [
            TdsExperimentType.allCases[3].subfeature.rawValue: ExperimentData(parentID: "someParentID", cohortID: "testCohort", enrollmentDate: Date())
        ]

        // WHEN
        let experimentName = TDSOverrideExperimentMetrics.activeTDSExperimentNameWithCohort

        // THEN
        XCTAssertEqual(experimentName, "\(TdsExperimentType.allCases[3].subfeature.rawValue)_testCohort")
    }

    func test_OnGetActiveTDSExperimentNameWithCohort_WhenNoExperimentActive_ThenCorrectExperimentNameReturned() {
        // WHEN
        let experimentName = TDSOverrideExperimentMetrics.activeTDSExperimentNameWithCohort

        // THEN
        XCTAssertNil(experimentName)
    }

}
