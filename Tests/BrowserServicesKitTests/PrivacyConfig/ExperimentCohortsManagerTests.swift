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

    var mockStore: MockExperimentDataStore!
    var experimentCohortsManager: ExperimentCohortsManager!

    let subfeatureName1 = "TestSubfeature1"
    var experimentData1: ExperimentData!

    let subfeatureName2 = "TestSubfeature2"
    var experimentData2: ExperimentData!

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    override func setUp() {
        super.setUp()
        mockStore = MockExperimentDataStore()
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: { _ in 50.0 }
        )

        let expectedDate1 = Date()
        experimentData1 = ExperimentData(cohort: "TestCohort1", enrollmentDate: expectedDate1)

        let expectedDate2 = Date().addingTimeInterval(60)
        experimentData2 = ExperimentData(cohort: "TestCohort2", enrollmentDate: expectedDate2)
    }

    override func tearDown() {
        mockStore = nil
        experimentCohortsManager = nil
        experimentData1 = nil
        experimentData2 = nil
        super.tearDown()
    }

    func testCohortReturnsCohortIDIfExistsForMultipleSubfeatures() async {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1, subfeatureName2: experimentData2]

        // WHEN
        let result1 = await experimentCohortsManager.cohort(for: subfeatureName1)
        let result2 = await experimentCohortsManager.cohort(for: subfeatureName2)

        // THEN
        XCTAssertEqual(result1, experimentData1.cohort)
        XCTAssertEqual(result2, experimentData2.cohort)
    }

    func testEnrollmentDateReturnsCorrectDateIfExists() async {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1]

        // WHEN
        let result1 = await experimentCohortsManager.enrollmentDate(for: subfeatureName1)
        let result2 = await experimentCohortsManager.enrollmentDate(for: subfeatureName2)

        // THEN
        let timeDifference1 = abs(experimentData1.enrollmentDate.timeIntervalSince(result1 ?? Date()))

        XCTAssertLessThanOrEqual(timeDifference1, 1.0, "Expected enrollment date for subfeatureName1 to match at the second level")
        XCTAssertNil(result2)
    }

    func testCohortReturnsNilIfCohortDoesNotExist() async {
        // GIVEN
        let subfeatureName = "TestSubfeature"

        // WHEN
        let result = await experimentCohortsManager.cohort(for: subfeatureName)

        // THEN
        XCTAssertNil(result)
    }

    func testEnrollmentDateReturnsNilIfDateDoesNotExist() async {
        // GIVEN
        let subfeatureName = "TestSubfeature"

        // WHEN
        let result = await experimentCohortsManager.enrollmentDate(for: subfeatureName)

        // THEN
        XCTAssertNil(result)
    }

    func testRemoveCohortSuccessfullyRemovesData() async throws {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1]

        // WHEN
        await experimentCohortsManager.removeCohort(from: subfeatureName1)

        // THEN
        let experiments = try XCTUnwrap(mockStore.experiments)
        XCTAssertTrue(experiments.isEmpty)
    }

    func testRemoveCohortDoesNothingIfSubfeatureDoesNotExist() async {
        // GIVEN
        let expectedExperiments: Experiments = [subfeatureName1: experimentData1, subfeatureName2: experimentData2]
        mockStore.experiments = expectedExperiments

        // WHEN
        await experimentCohortsManager.removeCohort(from: "someOtherSubfeature")

        // THEN
        XCTAssertEqual( mockStore.experiments, expectedExperiments)
    }

    func testAssignCohortReturnsNilIfNoCohorts() async {
        // GIVEN
        let subfeature = ExperimentSubfeature(subfeatureID: subfeatureName1, cohorts: [])

        // WHEN
        let result = await experimentCohortsManager.assignCohort(to: subfeature)

        // THEN
        XCTAssertNil(result)
    }

    func testAssignCohortReturnsNilIfAllWeightsAreZero() async {
        // GIVEN
        let jsonCohort1: [String: Any] = ["name": "TestCohort", "weight": 0]
        let jsonCohort2: [String: Any] = ["name": "TestCohort", "weight": 0]
        let cohorts = [
            PrivacyConfigurationData.Cohort(json: jsonCohort1)!,
            PrivacyConfigurationData.Cohort(json: jsonCohort2)!
        ]
        let subfeature = ExperimentSubfeature(subfeatureID: subfeatureName1, cohorts: cohorts)

        // WHEN
        let result = await experimentCohortsManager.assignCohort(to: subfeature)

        // THEN
        XCTAssertNil(result)
    }

    func testAssignCohortSelectsCorrectCohortBasedOnWeight() async {
        // Cohort1 has weight 1, Cohort2 has weight 3
        // Total weight is 1 + 3 = 4
        let jsonCohort1: [String: Any] = ["name": "Cohort1", "weight": 1]
        let jsonCohort2: [String: Any] = ["name": "Cohort2", "weight": 3]
        let cohorts = [
            PrivacyConfigurationData.Cohort(json: jsonCohort1)!,
            PrivacyConfigurationData.Cohort(json: jsonCohort2)!
        ]
        let subfeature = ExperimentSubfeature(subfeatureID: subfeatureName1, cohorts: cohorts)
        let expectedTotalWeight = 4.0

        // Use a custom randomizer to verify the range
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: { range in
                // Assert that the range lower bound is 0
                XCTAssertEqual(range.lowerBound, 0.0)
                // Assert that the range upper bound is the total weight
                XCTAssertEqual(range.upperBound, expectedTotalWeight)
                return 0.0
            }
        )

        // Test case where random value is at the very start of Cohort1's range (0)
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: { _ in 0.0 }
        )
        let resultStartOfCohort1 = await experimentCohortsManager.assignCohort(to: subfeature)
        XCTAssertEqual(resultStartOfCohort1, "Cohort1")

        // Test case where random value is at the end of Cohort1's range (0.9)
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: { _ in 0.9 }
        )
        let resultEndOfCohort1 = await experimentCohortsManager.assignCohort(to: subfeature)
        XCTAssertEqual(resultEndOfCohort1, "Cohort1")

        // Test case where random value is at the start of Cohort2's range (1.00 to 4)
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: { _ in 1.00 }
        )
        let resultStartOfCohort2 = await experimentCohortsManager.assignCohort(to: subfeature)
        XCTAssertEqual(resultStartOfCohort2, "Cohort2")

        // Test case where random value falls exactly within Cohort2's range (2.5)
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: { _ in 2.5 }
        )
        let resultMiddleOfCohort2 = await experimentCohortsManager.assignCohort(to: subfeature)
        XCTAssertEqual(resultMiddleOfCohort2, "Cohort2")

        // Test case where random value is at the end of Cohort2's range (4)
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: { _ in 3.9 }
        )
        let resultEndOfCohort2 = await experimentCohortsManager.assignCohort(to: subfeature)
        XCTAssertEqual(resultEndOfCohort2, "Cohort2")
    }

    func testAssignCohortWithSingleCohortAlwaysSelectsThatCohort() async throws {
        // GIVEN
        let jsonCohort1: [String: Any] = ["name": "Cohort1", "weight": 1]
        let cohorts = [
            PrivacyConfigurationData.Cohort(json: jsonCohort1)!
        ]
        let subfeature = ExperimentSubfeature(subfeatureID: subfeatureName1, cohorts: cohorts)
        let expectedTotalWeight = 1.0

        // Use a custom randomizer to verify the range
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: { range in
                // Assert that the range lower bound is 0
                XCTAssertEqual(range.lowerBound, 0.0)
                // Assert that the range upper bound is the total weight
                XCTAssertEqual(range.upperBound, expectedTotalWeight)
                return 0.0
            }
        )

        // WHEN
        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: { range in Double.random(in: range)}
        )
        let result = await experimentCohortsManager.assignCohort(to: subfeature)

        // THEN
        XCTAssertEqual(result, "Cohort1")
        XCTAssertEqual(cohorts[0].name, mockStore.experiments?[subfeature.subfeatureID]?.cohort)
    }

}

class MockExperimentDataStore: ExperimentsDataStoring {
    func getExperiments() async -> BrowserServicesKit.Experiments? {
        return experiments
    }

    func setExperiments(_ experiments: BrowserServicesKit.Experiments?) async {
        self.experiments = experiments
    }

    var experiments: Experiments?
}
