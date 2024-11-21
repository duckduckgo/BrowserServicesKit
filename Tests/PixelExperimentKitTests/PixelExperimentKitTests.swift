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

final class PixelExperimentKitTests: XCTestCase {
    var featureJson: Data = "{}".data(using: .utf8)!
    var mockPixelStore: MockExperimentActionPixelStore!
    var mockExperimentStore: MockExperimentDataStore!
    var mockEmbeddedData: MockEmbeddedDataProvider!
    var privacyConfigurationManager: PrivacyConfigurationManager!
    var firedEvent: PixelKitEvent?
    var firedFrequency: PixelKit.Frequency?
    var firedIncludeAppVersion: Bool?

    override func setUp() {
        super.setUp()
        mockEmbeddedData = MockEmbeddedDataProvider(data: featureJson, etag: "test")
        mockPixelStore = MockExperimentActionPixelStore()
        mockExperimentStore = MockExperimentDataStore()
        privacyConfigurationManager = PrivacyConfigurationManager(fetchedETag: nil,
                                                                  fetchedData: nil,
                                                                  embeddedDataProvider: mockEmbeddedData,
                                                                  localProtection: MockDomainsProtectionStore(),
                                                                  internalUserDecider: DefaultInternalUserDecider(store: MockInternalUserStoring()),
                                                                  experimentCohortManager: ExperimentCohortsManager(store: mockExperimentStore),
                                                                  reportExperimentCohortAssignment: { _, _ in })
        PixelKit.configureExperimentKit(privacyConfigManager: privacyConfigurationManager, store: mockPixelStore, fire: { event, frequency, includeAppVersion in
            self.firedEvent = event
            self.firedFrequency = frequency
            self.firedIncludeAppVersion = includeAppVersion
        })
    }

    override func tearDown() {
        mockEmbeddedData = nil
        mockPixelStore = nil
        mockExperimentStore = nil
        privacyConfigurationManager = nil
        firedEvent = nil
        firedFrequency = nil
        firedIncludeAppVersion = nil
    }

    func testFireExperimentEnrollmentPixelSendsExpectedData() {
        // GIVEN
        let subfeatureID = "testSubfeature"
        let cohort = "A"
        let enrollmentDate = Date(timeIntervalSince1970: 0)
        let experimentData = ExperimentData(parentID: "parent", cohort: cohort, enrollmentDate: enrollmentDate)
        let expectedEventName = "experiment_enroll_\(subfeatureID)_\(cohort)"
        let expectedParameters = ["enrollmentDate": enrollmentDate.toYYYYMMDDInET()]

        // WHEN
        PixelKit.fireExperimentEnrollmentPixel(subfeatureID: subfeatureID, experiment: experimentData)

        // THEN
        XCTAssertEqual(firedEvent?.name, expectedEventName)
        XCTAssertEqual(firedEvent?.parameters, expectedParameters)
        XCTAssertEqual(firedFrequency, .uniqueIncludingParameters)
        XCTAssertFalse(firedIncludeAppVersion ?? true)
    }

    func testFireExperimentPixel_WithValidExperimentAndConversionWindowAndValueNotNumber() {
        // GIVEN
        featureJson =
        """
        {
            "features": {
                "autofill": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": {
                        "credentialsSaving": {
                            "state": "enabled",
                            "minSupportedVersion": 2,
                             "cohorts": [
                                 {
                                     "name": "control",
                                     "weight": 1
                                 },
                                 {
                                     "name": "blue",
                                     "weight": 0
                                 }
                              ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        privacyConfigurationManager.reload(etag: "", data: featureJson)

        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-3 * 24 * 60 * 60) // 5 days ago
        print(enrollmentDate)
        let conversionWindow = 3...3
        let value = "true"
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-3",
            "value": value,
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let experimentData = ExperimentData(parentID: "autofill", cohort: cohort, enrollmentDate: enrollmentDate)
        mockExperimentStore.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertEqual(firedEvent?.name, expectedEventName)
        XCTAssertEqual(firedEvent?.parameters, expectedParameters)
        XCTAssertEqual(firedFrequency, .uniqueIncludingParameters)
        XCTAssertFalse(firedIncludeAppVersion ?? true)
    }

    func testFireExperimentPixel_WithValidExperimentAndConversionWindowAndValue1() {
        // GIVEN
        featureJson =
        """
        {
            "features": {
                "autofill": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": {
                        "credentialsSaving": {
                            "state": "enabled",
                            "minSupportedVersion": 2,
                             "cohorts": [
                                 {
                                     "name": "control",
                                     "weight": 1
                                 },
                                 {
                                     "name": "blue",
                                     "weight": 0
                                 }
                              ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        privacyConfigurationManager.reload(etag: "", data: featureJson)

        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        print(enrollmentDate)
        let conversionWindow = 3...7
        let value = "1"
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-7",
            "value": value,
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let experimentData = ExperimentData(parentID: "autofill", cohort: cohort, enrollmentDate: enrollmentDate)
        mockExperimentStore.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertEqual(firedEvent?.name, expectedEventName)
        XCTAssertEqual(firedEvent?.parameters, expectedParameters)
        XCTAssertEqual(firedFrequency, .uniqueIncludingParameters)
        XCTAssertFalse(firedIncludeAppVersion ?? true)
    }

    func testFireExperimentPixel_WithValidExperimentAndConversionWindowAndValueN() {
        // GIVEN
        featureJson =
        """
        {
            "features": {
                "autofill": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": {
                        "credentialsSaving": {
                            "state": "enabled",
                            "minSupportedVersion": 2,
                             "cohorts": [
                                 {
                                     "name": "control",
                                     "weight": 1
                                 },
                                 {
                                     "name": "blue",
                                     "weight": 0
                                 }
                              ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        privacyConfigurationManager.reload(etag: "", data: featureJson)

        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        print(enrollmentDate)
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
        let experimentData = ExperimentData(parentID: "autofill", cohort: cohort, enrollmentDate: enrollmentDate)
        mockExperimentStore.experiments = [subfeatureID: experimentData]

        // WHEN calling fire before expected number of calls
        for n in 0..<randomNumber {
            PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)
            // THEN
            XCTAssertNil(firedEvent?.name)
            XCTAssertNil(firedEvent?.parameters)
            XCTAssertNil(firedFrequency)
            XCTAssertNil(firedIncludeAppVersion)
            XCTAssertEqual(mockPixelStore.store.count, 1)
            XCTAssertEqual(mockPixelStore.store.values.first, n + 1)
        }

        // WHEN calling fire at the right number of calls
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertEqual(firedEvent?.name, expectedEventName)
        XCTAssertEqual(firedEvent?.parameters, expectedParameters)
        XCTAssertEqual(firedFrequency, .uniqueIncludingParameters)
        XCTAssertFalse(firedIncludeAppVersion ?? true)
    }

    func testFireExperimentPixel_WithInValidExperimentAndConversionWindowAndValue1() {
        // GIVEN
        featureJson =
        """
        {
            "features": {
                "autofill": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": {
                        "credentialsSaving": {
                            "state": "enabled",
                            "minSupportedVersion": 2,
                             "cohorts": [
                                 {
                                     "name": "blue",
                                     "weight": 0
                                 }
                              ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        privacyConfigurationManager.reload(etag: "", data: featureJson)

        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        print(enrollmentDate)
        let conversionWindow = 3...7
        let randomNumber = Int.random(in: 1...100)
        let value = "\(randomNumber)"
        let experimentData = ExperimentData(parentID: "autofill", cohort: cohort, enrollmentDate: enrollmentDate)
        mockExperimentStore.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertNil(firedEvent?.name)
        XCTAssertNil(firedEvent?.parameters)
        XCTAssertNil(firedFrequency)
        XCTAssertNil(firedIncludeAppVersion)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixel_WithValidExperimentAndOutsideConversionWindowAndValueN() {
        // GIVEN
        featureJson =
        """
        {
            "features": {
                "autofill": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": {
                        "credentialsSaving": {
                            "state": "enabled",
                            "minSupportedVersion": 2,
                             "cohorts": [
                                 {
                                     "name": "control",
                                     "weight": 1
                                 },
                                 {
                                     "name": "blue",
                                     "weight": 0
                                 }
                              ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        privacyConfigurationManager.reload(etag: "", data: featureJson)

        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        print(enrollmentDate)
        let conversionWindow = 8...11
        let value = "3"
        let experimentData = ExperimentData(parentID: "autofill", cohort: cohort, enrollmentDate: enrollmentDate)
        mockExperimentStore.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertNil(firedEvent?.name)
        XCTAssertNil(firedEvent?.parameters)
        XCTAssertNil(firedFrequency)
        XCTAssertNil(firedIncludeAppVersion)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixel_WithValidExperimentAndAfterConversionWindowAndValueNAfterSomeCalledHappened() {
        // GIVEN
        featureJson =
        """
        {
            "features": {
                "autofill": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": {
                        "credentialsSaving": {
                            "state": "enabled",
                            "minSupportedVersion": 2,
                             "cohorts": [
                                 {
                                     "name": "control",
                                     "weight": 1
                                 },
                                 {
                                     "name": "blue",
                                     "weight": 0
                                 }
                              ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        privacyConfigurationManager.reload(etag: "", data: featureJson)

        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-6 * 24 * 60 * 60) // 5 days ago
        print(enrollmentDate)
        let conversionWindow = 3...5
        let value = "3"
        let experimentData = ExperimentData(parentID: "autofill", cohort: cohort, enrollmentDate: enrollmentDate)
        mockExperimentStore.experiments = [subfeatureID: experimentData]
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-5",
            "value": value,
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let eventStoreKey = expectedEventName + "_" + expectedParameters.escapedString()
        print(eventStoreKey)
        mockPixelStore.store = [eventStoreKey : 2]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertNil(firedEvent?.name)
        XCTAssertNil(firedEvent?.parameters)
        XCTAssertNil(firedFrequency)
        XCTAssertNil(firedIncludeAppVersion)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireSearchExperimentPixels_WithMultipleExperiments() {
        // GIVEN
        featureJson =
        """
        {
            "features": {
                "autofill": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": {
                        "credentialsSaving": {
                            "state": "enabled",
                            "minSupportedVersion": 1,
                             "cohorts": [
                                 {
                                     "name": "control",
                                     "weight": 1
                                 }
                              ]
                        },
                        "inlineIconCredentials": {
                            "state": "enabled",
                            "minSupportedVersion": 1,
                             "cohorts": [
                                 {
                                     "name": "test",
                                     "weight": 1
                                 }
                              ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        privacyConfigurationManager.reload(etag: "", data: featureJson)

        let subfeatureID1 = "credentialsSaving"
        let cohort1 = "control"
        let enrollmentDate1 = Date().addingTimeInterval(-6 * 24 * 60 * 60) // 6 days ago
        let experimentData1 = ExperimentData(parentID: "autofill", cohort: cohort1, enrollmentDate: enrollmentDate1)

        let subfeatureID2 = "inlineIconCredentials"
        let cohort2 = "test"
        let enrollmentDate2 = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        let experimentData2 = ExperimentData(parentID: "autofill", cohort: cohort2, enrollmentDate: enrollmentDate2)

        mockExperimentStore.experiments = [
            subfeatureID1: experimentData1,
            subfeatureID2: experimentData2
        ]

        // WHEN
        PixelKit.fireSearchExperimentPixels()

        // THEN
        // Verify pixel for the first experiment
        XCTAssertEqual(firedEvent?.name, "experiment_metrics_\(subfeatureID1)_\(cohort1)")
        XCTAssertEqual(firedEvent?.parameters?[PixelKit.Constants.metricKey], PixelKit.Constants.searchMetricValue)
        XCTAssertEqual(firedEvent?.parameters?[PixelKit.Constants.conversionWindowDaysKey], "5-7")
        XCTAssertEqual(firedFrequency, .uniqueIncludingParameters)
        XCTAssertFalse(firedIncludeAppVersion ?? true)
        print(mockPixelStore.store)
//        clearFireEvents()

        // Verify no pixel fired for the second experiment (outside conversion window)
        XCTAssertNotNil(mockPixelStore.store)
        XCTAssertNil(firedEvent?.parameters?[PixelKit.Constants.conversionWindowDaysKey], "Expected conversion window outside bounds for experimentB")
    }

    func clearFireEvents() {
        firedEvent = nil
        firedFrequency = nil
        firedIncludeAppVersion = nil
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

class MockExperimentDataStore: ExperimentsDataStoring {
    var experiments: Experiments?
}

class MockEmbeddedDataProvider: EmbeddedDataProvider {
    var embeddedDataEtag: String

    var embeddedData: Data

    init(data: Data, etag: String) {
        embeddedData = data
        embeddedDataEtag = etag
    }
}

final class MockDomainsProtectionStore: DomainsProtectionStore {
    var unprotectedDomains = Set<String>()

    func disableProtection(forDomain domain: String) {
        unprotectedDomains.insert(domain)
    }

    func enableProtection(forDomain domain: String) {
        unprotectedDomains.remove(domain)
    }
}

final class MockInternalUserStoring: InternalUserStoring {
    var isInternalUser: Bool = false
}
