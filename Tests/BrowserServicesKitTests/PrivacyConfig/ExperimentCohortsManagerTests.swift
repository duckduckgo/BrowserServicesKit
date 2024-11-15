//
//  ExperimentCohortsManagerTests.swift
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
@testable import BrowserServicesKit

final class ExperimentCohortsManagerTests: XCTestCase {

    let cohort1 = PrivacyConfigurationData.Cohort(json: ["name": "Cohort1", "weight": 1])!
    let cohort2 = PrivacyConfigurationData.Cohort(json: ["name": "Cohort2", "weight": 0])!
    let cohort3 = PrivacyConfigurationData.Cohort(json: ["name": "Cohort3", "weight": 2])!
    let cohort4 = PrivacyConfigurationData.Cohort(json: ["name": "Cohort4", "weight": 0])!

    var mockStore: MockExperimentDataStore!
    var experimentCohortsManager: ExperimentCohortsManager!

    let subfeatureName1 = "TestSubfeature1"
    var experimentData1: ExperimentData!

    let subfeatureName2 = "TestSubfeature2"
    var experimentData2: ExperimentData!

    let subfeatureName3 = "TestSubfeature3"
    var experimentData3: ExperimentData!

    let subfeatureName4 = "TestSubfeature4"
    var experimentData4: ExperimentData!

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    override func setUp() {
        super.setUp()
        mockStore = MockExperimentDataStore()
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore
        )

        let expectedDate1 = Date()
        experimentData1 = ExperimentData(parentID: "TestParent", cohort: cohort1.name, enrollmentDate: expectedDate1)

        let expectedDate2 = Date().addingTimeInterval(60)
        experimentData2 = ExperimentData(parentID: "TestParent", cohort: cohort2.name, enrollmentDate: expectedDate2)

        let expectedDate3 = Date()
        experimentData3 = ExperimentData(parentID: "TestParent", cohort: cohort3.name, enrollmentDate: expectedDate3)

        let expectedDate4 = Date().addingTimeInterval(60)
        experimentData4 = ExperimentData(parentID: "TestParent", cohort: cohort4.name, enrollmentDate: expectedDate4)
    }

    override func tearDown() {
        mockStore = nil
        experimentCohortsManager = nil
        experimentData1 = nil
        experimentData2 = nil
        super.tearDown()
    }

    func testExperimentReturnAssignedExperiments() {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1, subfeatureName2: experimentData2]

        // WHEN
        let experiments = experimentCohortsManager.experiments

        // THEN
        XCTAssertEqual(experiments?.count, 2)
        XCTAssertEqual(experiments?[subfeatureName1], experimentData1)
        XCTAssertEqual(experiments?[subfeatureName2], experimentData2)
        XCTAssertNil(experiments?[subfeatureName3])
    }

    func testCohortReturnsCohortIDIfExistsForMultipleSubfeatures() {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1, subfeatureName2: experimentData2]

        // WHEN
        let result1 = experimentCohortsManager.cohort(for: ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: [cohort1, cohort2]), assignIfEnabled: false).cohortID
        let result2 = experimentCohortsManager.cohort(for: ExperimentSubfeature(parentID: experimentData2.parentID, subfeatureID: subfeatureName2, cohorts: [cohort2, cohort3]), assignIfEnabled: false).cohortID

        // THEN
        XCTAssertEqual(result1, experimentData1.cohort)
        XCTAssertEqual(result2, experimentData2.cohort)
    }

    func testCohortAssignIfEnabledWhenNoCohortExists() {
        // GIVEN
        mockStore.experiments = [:]
        let cohorts = [cohort1, cohort2]
        let experiment = ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: cohorts)

        // WHEN
        let result = experimentCohortsManager.cohort(for: experiment, assignIfEnabled: true)

        // THEN
        XCTAssertNotNil(result.cohortID)
        XCTAssertTrue(result.didAttemptAssignment)
        XCTAssertEqual(result.cohortID, experimentData1.cohort)
    }

    func testCohortDoesNotAssignIfAssignIfEnabledIsFalse() {
        // GIVEN
        mockStore.experiments = [:]
        let cohorts = [cohort1, cohort2]
        let experiment = ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: cohorts)

        // WHEN
        let result = experimentCohortsManager.cohort(for: experiment, assignIfEnabled: false)

        // THEN
        XCTAssertNil(result.cohortID)
        XCTAssertTrue(result.didAttemptAssignment)
    }

    func testCohortDoesNotAssignIfAssignIfEnabledIsTrueButNoCohortsAvailable() {
        // GIVEN
        mockStore.experiments = [:]
        let experiment = ExperimentSubfeature(parentID: "TestParent", subfeatureID: "NonExistentSubfeature", cohorts: [])

        // WHEN
        let result = experimentCohortsManager.cohort(for: experiment, assignIfEnabled: true)

        // THEN
        XCTAssertNil(result.cohortID)
        XCTAssertTrue(result.didAttemptAssignment)
    }

    func testCohortReassignsCohortIfAssignedCohortDoesNotExistAndAssignIfEnabledIsTrue() {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1]

        // WHEN
        let result1 = experimentCohortsManager.cohort(for: ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: [cohort2, cohort3]), assignIfEnabled: true).cohortID

        // THEN
        XCTAssertEqual(result1, experimentData3.cohort)
    }

    func testCohortDoesNotReassignsCohortIfAssignedCohortDoesNotExistAndAssignIfEnabledIsTrue() {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1]

        // WHEN
        let result1 = experimentCohortsManager.cohort(for: ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: [cohort2, cohort3]), assignIfEnabled: false).cohortID

        // THEN
        XCTAssertNil(result1)
    }

    func testCohortAssignsBasedOnWeight() {
        // GIVEN
        let experiment = ExperimentSubfeature(parentID: experimentData3.parentID, subfeatureID: subfeatureName3, cohorts: [cohort3, cohort4])

        let randomizer: (Range<Double>) -> Double = { range in
            return 1.5
        }

        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: randomizer
        )

        // WHEN
        let result = experimentCohortsManager.cohort(for: experiment, assignIfEnabled: true)

        // THEN
        XCTAssertEqual(result.cohortID, experimentData3.cohort)
        XCTAssertTrue(result.didAttemptAssignment)
    }
}

class MockExperimentDataStore: ExperimentsDataStoring {
    var experiments: Experiments?
}
