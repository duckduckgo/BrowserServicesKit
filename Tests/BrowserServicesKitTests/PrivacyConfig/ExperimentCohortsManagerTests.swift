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

    var mockUserDefaults: UserDefaults!
    var experimentCohortsManager: ExperimentCohortsManager!

    let subfeatureName1 = "TestSubfeature1"
    var expectedDate1: Date!
    var experimentData1: ExperimentData!

    let subfeatureName2 = "TestSubfeature2"
    var expectedDate2: Date!
    var experimentData2: ExperimentData!

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    override func setUp() {
        super.setUp()
        mockUserDefaults = UserDefaults(suiteName: "com.test.ExperimentCohortsManagerTests")
        mockUserDefaults.removePersistentDomain(forName: "com.test.ExperimentCohortsManagerTests")

        experimentCohortsManager = ExperimentCohortsManager(
            userDefaults: mockUserDefaults,
            randomizer: { _ in 50.0 }
        )

        expectedDate1 = Date()
        experimentData1 = ExperimentData(cohort: "TestCohort1", enrollmentDate: expectedDate1)

        expectedDate2 = Date().addingTimeInterval(60) // Second subfeature with a different date
        experimentData2 = ExperimentData(cohort: "TestCohort2", enrollmentDate: expectedDate2)
    }

    override func tearDown() {
        mockUserDefaults.removePersistentDomain(forName: "com.test.ExperimentCohortsManagerTests")
        mockUserDefaults = nil
        experimentCohortsManager = nil
        expectedDate1 = nil
        experimentData1 = nil
        expectedDate2 = nil
        experimentData2 = nil
        super.tearDown()
    }

    private func saveExperimentData(_ data: [String: ExperimentData]) {
        if let encodedData = try? encoder.encode(data) {
            mockUserDefaults.set(encodedData, forKey: "ExperimentsData")
        }
    }

    func testCohortReturnsCohortIDIfExistsForMultipleSubfeatures() {
        // GIVEN
        saveExperimentData([subfeatureName1: experimentData1, subfeatureName2: experimentData2])

        // WHEN
        let result1 = experimentCohortsManager.cohort(for: subfeatureName1)
        let result2 = experimentCohortsManager.cohort(for: subfeatureName2)

        // THEN
        XCTAssertEqual(result1, experimentData1.cohort)
        XCTAssertEqual(result2, experimentData2.cohort)
    }

    func testEnrolmentDateReturnsCorrectDateIfExists() {
        // GIVEN
        saveExperimentData([subfeatureName1: experimentData1])

        // WHEN
        let result1 = experimentCohortsManager.enrolmentDate(for: subfeatureName1)
        let result2 = experimentCohortsManager.enrolmentDate(for: subfeatureName2)

        // THEN
        let timeDifference1 = abs(expectedDate1.timeIntervalSince(result1 ?? Date()))

        XCTAssertLessThanOrEqual(timeDifference1, 1.0, "Expected enrollment date for subfeatureName1 to match at the second level")
        XCTAssertNil(result2)
    }

    func testCohortReturnsNilIfCohortDoesNotExist() {
        // GIVEN
        let subfeatureName = "TestSubfeature"

        // WHEN
        let result = experimentCohortsManager.cohort(for: subfeatureName)

        // THEN
        XCTAssertNil(result)
    }

    func testEnrolmentDateReturnsNilIfDateDoesNotExist() {
        // GIVEN
        let subfeatureName = "TestSubfeature"

        // WHEN
        let result = experimentCohortsManager.enrolmentDate(for: subfeatureName)

        // THEN
        XCTAssertNil(result)
    }

    func testRemoveCohortSuccessfullyRemovesData() {
        // GIVEN
        saveExperimentData([subfeatureName1: experimentData1])
        let initialData = mockUserDefaults.data(forKey: "ExperimentsData")
        XCTAssertNotNil(initialData, "Expected initial data to be saved in UserDefaults.")

        // WHEN
        experimentCohortsManager.removeCohort(for: subfeatureName1)

        // THEN
        if let remainingData = mockUserDefaults.data(forKey: "ExperimentsData") {
            let decoder = JSONDecoder()
            let experiments = try? decoder.decode(Experiments.self, from: remainingData)
            XCTAssertNil(experiments?[subfeatureName1])
        }
    }

    func testRemoveCohortDoesNothingIfSubfeatureDoesNotExist() {
        // GIVEN
        saveExperimentData([subfeatureName1: experimentData1, subfeatureName2: experimentData2])
        let initialData = mockUserDefaults.data(forKey: "ExperimentsData")
        XCTAssertNotNil(initialData, "Expected initial data to be saved in UserDefaults.")

        // WHEN
        experimentCohortsManager.removeCohort(for: "someOtherSubfeature")

        // THEN
        if let remainingData = mockUserDefaults.data(forKey: "ExperimentsData") {
            let decoder = JSONDecoder()
            let experiments = try? decoder.decode(Experiments.self, from: remainingData)
            XCTAssertNotNil(experiments?[subfeatureName1])
            XCTAssertNotNil(experiments?[subfeatureName2])
        }
    }

    func testAssignCohortReturnsNilIfNoCohorts() {
        // GIVEN
        let subfeature = ExperimentSubfeature(subfeatureID: subfeatureName1, cohorts: [])

        // WHEN
        let result = experimentCohortsManager.assignCohort(for: subfeature)

        // THEN
        XCTAssertNil(result)
    }

    func testAssignCohortReturnsNilIfAllWeightsAreZero() {
        // GIVEN
        let jsonCohort1: [String: Any] = ["name": "TestCohort", "weight": 0]
        let jsonCohort2: [String: Any] = ["name": "TestCohort", "weight": 0]
        let cohorts = [
            PrivacyConfigurationData.Cohort(json: jsonCohort1)!,
            PrivacyConfigurationData.Cohort(json: jsonCohort2)!
        ]
        let subfeature = ExperimentSubfeature(subfeatureID: subfeatureName1, cohorts: cohorts)

        // WHEN
        let result = experimentCohortsManager.assignCohort(for: subfeature)

        // THEN
        XCTAssertNil(result)
    }

    func testAssignCohortSelectsCorrectCohortBasedOnWeight() {
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
            userDefaults: mockUserDefaults,
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
            userDefaults: mockUserDefaults,
            randomizer: { _ in 0.0 }
        )
        let resultStartOfCohort1 = experimentCohortsManager.assignCohort(for: subfeature)
        XCTAssertEqual(resultStartOfCohort1, "Cohort1")

        // Test case where random value is at the end of Cohort1's range (0.9)
        experimentCohortsManager = ExperimentCohortsManager(
            userDefaults: mockUserDefaults,
            randomizer: { _ in 0.9 }
        )
        let resultEndOfCohort1 = experimentCohortsManager.assignCohort(for: subfeature)
        XCTAssertEqual(resultEndOfCohort1, "Cohort1")

        // Test case where random value is at the start of Cohort2's range (1.00 to 4)
        experimentCohortsManager = ExperimentCohortsManager(
            userDefaults: mockUserDefaults,
            randomizer: { _ in 1.00 }
        )
        let resultStartOfCohort2 = experimentCohortsManager.assignCohort(for: subfeature)
        XCTAssertEqual(resultStartOfCohort2, "Cohort2")

        // Test case where random value falls exactly within Cohort2's range (2.5)
        experimentCohortsManager = ExperimentCohortsManager(
            userDefaults: mockUserDefaults,
            randomizer: { _ in 2.5 }
        )
        let resultMiddleOfCohort2 = experimentCohortsManager.assignCohort(for: subfeature)
        XCTAssertEqual(resultMiddleOfCohort2, "Cohort2")

        // Test case where random value is at the end of Cohort2's range (4)
        experimentCohortsManager = ExperimentCohortsManager(
            userDefaults: mockUserDefaults,
            randomizer: { _ in 3.9 }
        )
        let resultEndOfCohort2 = experimentCohortsManager.assignCohort(for: subfeature)
        XCTAssertEqual(resultEndOfCohort2, "Cohort2")
    }

    func testAssignCohortWithSingleCohortAlwaysSelectsThatCohort() {
        // GIVEN
        let jsonCohort1: [String: Any] = ["name": "Cohort1", "weight": 1]
        let cohorts = [
            PrivacyConfigurationData.Cohort(json: jsonCohort1)!
        ]
        let subfeature = ExperimentSubfeature(subfeatureID: subfeatureName1, cohorts: cohorts)
        let expectedTotalWeight = 1.0

        // Use a custom randomizer to verify the range
        experimentCohortsManager = ExperimentCohortsManager(
            userDefaults: mockUserDefaults,
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
            userDefaults: mockUserDefaults,
            randomizer: { range in Double.random(in: range)}
        )
        let result = experimentCohortsManager.assignCohort(for: subfeature)

        // THEN
        XCTAssertEqual(result, "Cohort1")
    }

}
