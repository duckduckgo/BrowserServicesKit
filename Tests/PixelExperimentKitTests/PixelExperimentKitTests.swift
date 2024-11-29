//
//  PixelExperimentKitTests.swift
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
@testable import PixelExperimentKit
@testable import BrowserServicesKit
import PixelKit
import Combine

final class PixelExperimentKitTests: XCTestCase {
    var featureJson: Data = "{}".data(using: .utf8)!
    var mockPixelStore: MockExperimentActionPixelStore!
    var mockFeatureFlagger: MockFeatureFlagger!
    var firedEvent = [PixelKitEvent]()
    var firedFrequency = [PixelKit.Frequency]()
    var firedIncludeAppVersion = [Bool]()

    override func setUp() {
        super.setUp()
        mockPixelStore = MockExperimentActionPixelStore()
        mockFeatureFlagger = MockFeatureFlagger()
        PixelKit.configureExperimentKit(featureFlagger: mockFeatureFlagger, store: mockPixelStore, fire: { event, frequency, includeAppVersion in
            self.firedEvent.append(event)
            self.firedFrequency.append(frequency)
            self.firedIncludeAppVersion.append(includeAppVersion)
        })
    }

    override func tearDown() {
        mockPixelStore = nil
        mockFeatureFlagger = nil
        firedEvent = []
        firedFrequency = []
        firedIncludeAppVersion = []
    }

    func testFireExperimentEnrollmentPixelSendsExpectedData() {
        // GIVEN
        let subfeatureID = "testSubfeature"
        let cohort = "A"
        let enrollmentDate = Date(timeIntervalSince1970: 0)
        let experimentData = ExperimentData(parentID: "parent", cohortID: cohort, enrollmentDate: enrollmentDate)
        let expectedEventName = "experiment_enroll_\(subfeatureID)_\(cohort)"
        let expectedParameters = ["enrollmentDate": enrollmentDate.toYYYYMMDDInET()]

        // WHEN
        PixelKit.fireExperimentEnrollmentPixel(subfeatureID: subfeatureID, experiment: experimentData)

        // THEN
        XCTAssertEqual(firedEvent[0].name, expectedEventName)
        XCTAssertEqual(firedEvent[0].parameters, expectedParameters)
        XCTAssertEqual(firedFrequency[0], .uniqueIncludingParameters)
        XCTAssertFalse(firedIncludeAppVersion[0])
    }

    func testFireExperimentPixel_WithValidExperimentAndConversionWindowAndValueNotNumber() {
        // GIVEN

        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-3 * 24 * 60 * 60) // 5 days ago
        let conversionWindow = 3...3
        let value = "true"
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-3",
            "value": value,
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertEqual(firedEvent[0].name, expectedEventName)
        XCTAssertEqual(firedEvent[0].parameters, expectedParameters)
        XCTAssertEqual(firedFrequency[0], .uniqueIncludingParameters)
        XCTAssertFalse(firedIncludeAppVersion[0])
    }

    func testFireExperimentPixel_WithValidExperimentAndConversionWindowAndValue1() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        let conversionWindow = 3...7
        let value = "1"
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-7",
            "value": value,
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertEqual(firedEvent[0].name, expectedEventName)
        XCTAssertEqual(firedEvent[0].parameters, expectedParameters)
        XCTAssertEqual(firedFrequency[0], .uniqueIncludingParameters)
        XCTAssertFalse(firedIncludeAppVersion[0])
    }

    func testFireExperimentPixel_WithValidExperimentAndConversionWindowAndValueN() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        let conversionWindow = 3...7
        let randomNumber = Int.random(in: 1...100)
        let value = "\(randomNumber)"
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-7",
            "value": value,
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN calling fire before expected number of calls
        for n in 1..<randomNumber {
            PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)
            // THEN
            XCTAssertTrue(firedEvent.isEmpty)
            XCTAssertTrue(firedFrequency.isEmpty)
            XCTAssertTrue(firedIncludeAppVersion.isEmpty)
            XCTAssertEqual(mockPixelStore.store.count, 1)
            XCTAssertEqual(mockPixelStore.store.values.first, n)
        }

        // WHEN calling fire at the right number of calls
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertEqual(firedEvent[0].name, expectedEventName)
        XCTAssertEqual(firedEvent[0].parameters, expectedParameters)
        XCTAssertEqual(firedFrequency[0], .uniqueIncludingParameters)
        XCTAssertFalse(firedIncludeAppVersion[0])
    }

    func testFireExperimentPixel_WithInvalidExperimentAndValidConversionWindowAndValue1() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let conversionWindow = 3...7
        let randomNumber = Int.random(in: 1...100)
        let value = "\(randomNumber)"
        mockFeatureFlagger.experiments = [:]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertTrue(firedEvent.isEmpty)
        XCTAssertTrue(firedFrequency.isEmpty)
        XCTAssertTrue(firedIncludeAppVersion.isEmpty)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixel_WithValidExperimentAndOutsideConversionWindowAndValueN() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        print(enrollmentDate)
        let conversionWindow = 8...11
        let value = "3"
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertTrue(firedEvent.isEmpty)
        XCTAssertTrue(firedFrequency.isEmpty)
        XCTAssertTrue(firedIncludeAppVersion.isEmpty)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixel_WithValidExperimentAndAfterConversionWindowAndValueNAfterSomeCalledHappened() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-6 * 24 * 60 * 60) // 5 days ago
        print(enrollmentDate)
        let conversionWindow = 3...5
        let value = "3"
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-5",
            "value": value,
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let eventStoreKey = expectedEventName + "_" + expectedParameters.escapedString()
        print(eventStoreKey)
        mockPixelStore.store = [eventStoreKey: 2]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertTrue(firedEvent.isEmpty)
        XCTAssertTrue(firedFrequency.isEmpty)
        XCTAssertTrue(firedIncludeAppVersion.isEmpty)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireSearchExperimentPixels_WithMultipleExperiments() {
        // GIVEN
        let subfeatureID1 = "credentialsSaving"
        let cohort1 = "control"
        let enrollmentDate1 = Date().addingTimeInterval(-6 * 24 * 60 * 60) // 6 days ago
        let experimentData1 = ExperimentData(parentID: "autofill", cohortID: cohort1, enrollmentDate: enrollmentDate1)

        let subfeatureID2 = "inlineIconCredentials"
        let cohort2 = "test"
        let enrollmentDate2 = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        let experimentData2 = ExperimentData(parentID: "autofill", cohortID: cohort2, enrollmentDate: enrollmentDate2)

        mockFeatureFlagger.experiments = [
            subfeatureID1: experimentData1,
            subfeatureID2: experimentData2
        ]

        // WHEN
        PixelKit.fireSearchExperimentPixels()

        // THEN
        // Verify pixel for the first experiment
        XCTAssertTrue(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID1)_\(cohort1)"
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.metricKey] == PixelKit.Constants.searchMetricValue
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.conversionWindowDaysKey] == "5-7"
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.conversionWindowDaysKey] == "6-6"
            }
        )


        // Verify no pixel fired for the second experiment (outside conversion window)
        XCTAssertNotNil(mockPixelStore.store)
        XCTAssertFalse(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID2)_\(cohort2)"
            }
        )

        // Verify no pixel fired that after 4 reps second experiment pixel is sent(outside conversion window)
        PixelKit.fireSearchExperimentPixels()
        PixelKit.fireSearchExperimentPixels()
        PixelKit.fireSearchExperimentPixels()
        XCTAssertTrue(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID2)_\(cohort2)"
            }
        )
    }

    func testFireAppRetentionExperimentPixels_WithMultipleExperiments() {
        // GIVEN
        let subfeatureID1 = "credentialsSaving"
        let cohort1 = "control"
        let enrollmentDate1 = Date().addingTimeInterval(-6 * 24 * 60 * 60) // 6 days ago
        let experimentData1 = ExperimentData(parentID: "autofill", cohortID: cohort1, enrollmentDate: enrollmentDate1)

        let subfeatureID2 = "inlineIconCredentials"
        let cohort2 = "test"
        let enrollmentDate2 = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        let experimentData2 = ExperimentData(parentID: "autofill", cohortID: cohort2, enrollmentDate: enrollmentDate2)

        mockFeatureFlagger.experiments = [
            subfeatureID1: experimentData1,
            subfeatureID2: experimentData2
        ]

        // WHEN
        PixelKit.fireAppRetentionExperimentPixels()

        // THEN
        // Verify pixel for the first experiment
        XCTAssertTrue(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID1)_\(cohort1)"
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.metricKey] == PixelKit.Constants.appUseMetricValue
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.conversionWindowDaysKey] == "5-7"
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.conversionWindowDaysKey] == "6-6"
            }
        )


        // Verify no pixel fired for the second experiment (outside conversion window)
        XCTAssertNotNil(mockPixelStore.store)
        XCTAssertFalse(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID2)_\(cohort2)"
            }
        )

        // Verify no pixel fired that after 4 reps second experiment pixel is sent(outside conversion window)
        PixelKit.fireAppRetentionExperimentPixels()
        PixelKit.fireAppRetentionExperimentPixels()
        PixelKit.fireAppRetentionExperimentPixels()
        XCTAssertTrue(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID2)_\(cohort2)"
            }
        )
    }

}


class MockExperimentActionPixelStore: ExperimentActionPixelStore {
    var store: [String: Int] = [:]

    func removeObject(forKey defaultName: String) {
        store.removeValue(forKey: defaultName)
    }

    func integer(forKey defaultName: String) -> Int {
        return store[defaultName] ?? 0
    }

    func set(_ value: Int, forKey defaultName: String) {
        store[defaultName] = value
    }
}

class MockFeatureFlagger: FeatureFlagger {
    var experiments: Experiments = [:]

    var internalUserDecider: any InternalUserDecider = MockInternalUserDecider()

    var localOverrides: (any BrowserServicesKit.FeatureFlagLocalOverriding)?
    
    func getCohortIfEnabled<Flag>(for featureFlag: Flag) -> (any FlagCohort)? where Flag: FeatureFlagExperimentDescribing {
        return nil
    }
    
    func getAllActiveExperiments() -> Experiments {
        return experiments
    }

    func isFeatureOn<Flag>(for featureFlag: Flag, allowOverride: Bool) -> Bool where Flag: FeatureFlagDescribing {
        return false
    }
}

final class MockInternalUserDecider: InternalUserDecider {
    var isInternalUser: Bool = false

    var isInternalUserPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool {
        return false
    }
}
