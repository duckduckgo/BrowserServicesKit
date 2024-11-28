//
//  FeatureFlaggerExperimentsTests.swift
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

struct CredentialsSavingFlag: FeatureFlagExperimentDescribing {

    typealias CohortType = Cohort

    var rawValue = "credentialSaving"

    var source: FeatureFlagSource = .remoteReleasable(.subfeature(AutofillSubfeature.credentialsSaving))

    enum Cohort: String, FlagCohort {
        case control
        case blue
        case red
    }
}

struct InlineIconCredentialsFlag: FeatureFlagExperimentDescribing {

    typealias CohortType = Cohort

    var rawValue = "inlineIconCredentials"

    var source: FeatureFlagSource = .remoteReleasable(.subfeature(AutofillSubfeature.inlineIconCredentials))

    enum Cohort: String, FlagCohort {
        case control
        case blue
        case green
    }
}

struct AccessCredentialManagementFlag: FeatureFlagExperimentDescribing {

    typealias CohortType = Cohort

    var rawValue = "accessCredentialManagement"

    var source: FeatureFlagSource = .remoteReleasable(.subfeature(AutofillSubfeature.accessCredentialManagement))

    enum Cohort: String, FlagCohort {
        case control
        case blue
        case green
    }
}

final class FeatureFlaggerExperimentsTests: XCTestCase {

    var featureJson: Data = "{}".data(using: .utf8)!
    var mockEmbeddedData: MockEmbeddedDataProvider!
    var mockStore: MockExperimentDataStore!
    var experimentManager: ExperimentCohortsManager!
    var manager: PrivacyConfigurationManager!
    var locale: Locale!
    var featureFlagger: FeatureFlagger!

    let subfeatureName = "credentialsSaving"

    override func setUp() {
        locale = Locale(identifier: "fr_US")
        mockEmbeddedData = MockEmbeddedDataProvider(data: featureJson, etag: "test")
        let mockInternalUserStore = MockInternalUserStoring()
        mockStore = MockExperimentDataStore()
        experimentManager = ExperimentCohortsManager(store: mockStore)
        manager = PrivacyConfigurationManager(fetchedETag: nil,
                                              fetchedData: nil,
                                              embeddedDataProvider: mockEmbeddedData,
                                              localProtection: MockDomainsProtectionStore(),
                                              internalUserDecider: DefaultInternalUserDecider(store: mockInternalUserStore),
                                              locale: locale)
        featureFlagger = DefaultFeatureFlagger(internalUserDecider: DefaultInternalUserDecider(store: mockInternalUserStore), privacyConfigManager: manager, experimentManager: experimentManager)
    }

    override func tearDown() {
        featureJson = "".data(using: .utf8)!
        mockEmbeddedData = nil
        mockStore = nil
        experimentManager = nil
        manager = nil
    }

    func testCohortOnlyAssignedWhenCallingStateForSubfeature() {
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
        manager.reload(etag: "", data: featureJson)
        let config = manager.privacyConfig

        // we haven't called getCohortIfEnabled yet, so cohorts should not be yet assigned
        XCTAssertNil(mockStore.experiments)
        XCTAssertNil(experimentManager.cohort(for: subfeatureName))

        // we call isSubfeatureEnabled() hould not be assigned either
        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving))
        XCTAssertEqual(config.stateFor(AutofillSubfeature.credentialsSaving), .enabled)
        XCTAssertNil(mockStore.experiments)
        XCTAssertNil(experimentManager.cohort(for: subfeatureName))

        // we call getCohortIfEnabled(cohort), then we should assign cohort
        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")
    }

    func testRemoveAllCohortsRemotelyRemovesAssignedCohort() {
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
        manager.reload(etag: "", data: featureJson)
        var config = manager.privacyConfig

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // remove blue cohort
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
                                 }
                              ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        manager.reload(etag: "", data: featureJson)
        config = manager.privacyConfig

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // remove all remaining cohorts
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
                            "minSupportedVersion": 2
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        manager.reload(etag: "", data: featureJson)
        config = manager.privacyConfig

        XCTAssertNil(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag()))
        XCTAssertTrue(mockStore.experiments?.isEmpty ?? false)
        XCTAssertNil(experimentManager.cohort(for: subfeatureName))
        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving))
    }

    func testRemoveAssignedCohortsRemotelyRemovesAssignedCohortAndTriesToReassign() {
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
        manager.reload(etag: "2", data: featureJson)

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // remove blue cohort
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
                                    "name": "red",
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
        manager.reload(etag: "2", data: featureJson)

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.red.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "red")
    }

    func testDisablingFeatureDisablesCohort() {
        // Initially subfeature for both cohorts is disabled
        XCTAssertNil(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag()))
        XCTAssertNil(mockStore.experiments)
        XCTAssertNil(experimentManager.cohort(for: subfeatureName))

        // When features with cohort the cohort with weight 1 is enabled
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
        manager.reload(etag: "", data: featureJson)

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // If the subfeature is then disabled isSubfeatureEnabled should return false
        featureJson =
        """
        {
            "features": {
                "autofill": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": {
                        "credentialsSaving": {
                            "state": "disabled",
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
        manager.reload(etag: "", data: featureJson)

        XCTAssertNil(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag()))
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // If the subfeature is parent feature disabled isSubfeatureEnabled should return false
        featureJson =
        """
        {
            "features": {
                "autofill": {
                    "state": "disabled",
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
        manager.reload(etag: "", data: featureJson)

        XCTAssertNil(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag()))
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")
    }

    func testCohortsAndTargetsInteraction() {
        func featureJson(country: String, language: String) -> Data {
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
                                "targets": [
                                    {
                                        "localeLanguage": "\(language)",
                                        "localeCountry": "\(country)"
                                    }
                                ],
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
        }
        manager.reload(etag: "", data: featureJson(country: "FR", language: "fr"))

        XCTAssertNil(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag()))
        XCTAssertNil(mockStore.experiments)
        XCTAssertNil(experimentManager.cohort(for: subfeatureName))

        manager.reload(etag: "", data: featureJson(country: "US", language: "en"))
        XCTAssertNil(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag()))
        XCTAssertNil(mockStore.experiments)
        XCTAssertNil(experimentManager.cohort(for: subfeatureName))

        manager.reload(etag: "", data: featureJson(country: "US", language: "fr"))
        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // once cohort is assigned, changing targets shall not affect feature state
        manager.reload(etag: "", data: featureJson(country: "IT", language: "it"))
        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        let featureJson2 =
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
                            "targets": [
                                {
                                    "localeCountry": "FR"
                                }
                            ],
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        manager.reload(etag: "", data: featureJson2)

        XCTAssertNil(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag()))
        XCTAssertTrue(mockStore.experiments?.isEmpty ?? false)
        XCTAssertNil(experimentManager.cohort(for: subfeatureName))

        // re-populate experiment to re-assign new cohort, should not be assigned as it has wrong targets
        manager.reload(etag: "", data: featureJson(country: "IT", language: "it"))
        XCTAssertNil(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag()))
        XCTAssertTrue(mockStore.experiments?.isEmpty ?? false)
        XCTAssertNil(experimentManager.cohort(for: subfeatureName))
    }

    func testChangeRemoteCohortsAfterAssignmentShouldNoop() {
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
                            "targets": [
                                {
                                    "localeCountry": "US"
                                }
                            ],
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
        manager.reload(etag: "", data: featureJson)

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // changing targets should not change cohort assignment
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
                            "targets": [
                                {
                                    "localeCountry": "IT"
                                }
                            ],
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
        manager.reload(etag: "", data: featureJson)

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // changing cohort weight should not change current assignment
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
                            "targets": [
                                {
                                    "localeCountry": "US"
                                }
                            ],
                            "cohorts": [
                                {
                                    "name": "control",
                                    "weight": 0
                                },
                                {
                                    "name": "blue",
                                    "weight": 1
                                }
                            ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        manager.reload(etag: "", data: featureJson)

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // adding cohorts should not change current assignment
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
                            "targets": [
                                {
                                    "localeCountry": "US"
                                }
                            ],
                            "cohorts": [
                                {
                                    "name": "control",
                                    "weight": 1
                                },
                                {
                                    "name": "blue",
                                    "weight": 1
                                },
                                {
                                    "name": "red",
                                    "weight": 1
                                }
                            ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        manager.reload(etag: "", data: featureJson)

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

    }

    func testEnrollmentDate() {
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
                            "targets": [
                                {
                                    "localeCountry": "US"
                                }
                            ],
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
        manager.reload(etag: "", data: featureJson)
        let config = manager.privacyConfig

        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving))
        XCTAssertTrue(mockStore.experiments?.isEmpty ?? true)
        XCTAssertNil(experimentManager.cohort(for: subfeatureName), "control")

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        let currentTime = Date().timeIntervalSince1970
        let enrollmentTime = mockStore.experiments?[subfeatureName]?.enrollmentDate.timeIntervalSince1970

        XCTAssertNotNil(enrollmentTime)
        if let enrollmentTime = enrollmentTime {
            let tolerance: TimeInterval = 60 // 1 minute in seconds
            XCTAssertEqual(currentTime, enrollmentTime, accuracy: tolerance)
        }
    }

    func testRollbackCohortExperiments() {
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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
                                "rollout": {
                                    "steps": [
                                        {
                                            "percent": 100
                                        }
                                    ]
                                },
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
        manager.reload(etag: "foo", data: featureJson)
        var config = manager.privacyConfig
        clearRolloutData(feature: "autofill", subFeature: "credentialsSaving")

        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving))
        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
                                "rollout": {
                                    "steps": [
                                        {
                                            "percent": 0
                                        }
                                    ]
                                },
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
        manager.reload(etag: "foo", data: featureJson)
        config = manager.privacyConfig

        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving))
        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

    }

    func testCohortEnabledAndStopEnrollmentAndRhenRollBack() {
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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
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
        manager.reload(etag: "foo", data: featureJson)
        var config = manager.privacyConfig

        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving))
        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // Stop enrollment, should keep assigned cohorts
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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "control",
                                        "weight": 0
                                    },
                                    {
                                        "name": "blue",
                                        "weight": 1
                                    }
                                ]
                            }
                        }
                    }
                }
            }
            """.data(using: .utf8)!
        manager.reload(etag: "foo", data: featureJson)
        config = manager.privacyConfig

        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving))
        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.control.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "control")

        // remove control, should re-allocate to blue
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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "blue",
                                        "weight": 1
                                    }
                                ]
                            }
                        }
                    }
                }
            }
            """.data(using: .utf8)!
        manager.reload(etag: "foo", data: featureJson)
        config = manager.privacyConfig

        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving))
        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.CohortType.blue.rawValue)
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: subfeatureName), "blue")
    }

    private func clearRolloutData(feature: String, subFeature: String) {
        UserDefaults().set(nil, forKey: "config.\(feature).\(subFeature).enabled")
        UserDefaults().set(nil, forKey: "config.\(feature).\(subFeature).lastRolloutCount")
    }

    func testAllActiveExperimentsEmptyIfNoAssignedExperiment() {
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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
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
        manager.reload(etag: "foo", data: featureJson)

        let activeExperiments = featureFlagger.getAllActiveExperiments()
        XCTAssertTrue(activeExperiments.isEmpty)
        XCTAssertNil(mockStore.experiments)
    }

    func testAllActiveExperimentsReturnsOnlyActiveExperiments() {
        var featureJson =
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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
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
                            },
                            "inlineIconCredentials": {
                                "state": "enabled",
                                "minSupportedVersion": 1,
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "control",
                                        "weight": 0
                                    },
                                    {
                                        "name": "green",
                                        "weight": 1
                                    }
                                ]
                            },
                            "accessCredentialManagement": {
                                "state": "enabled",
                                "minSupportedVersion": 3,
                                "targets": [
                                    {
                                        "localeCountry": "CA"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "control",
                                        "weight": 1
                                    },
                                    {
                                        "name": "green",
                                        "weight": 0
                                    }
                                ]
                            }
                        }
                    }
                }
            }
            """.data(using: .utf8)!

        manager.reload(etag: "foo", data: featureJson)

        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: CredentialsSavingFlag())?.rawValue, CredentialsSavingFlag.Cohort.control.rawValue)
        XCTAssertEqual(featureFlagger.getCohortIfEnabled(for: InlineIconCredentialsFlag())?.rawValue, InlineIconCredentialsFlag.Cohort.green.rawValue)
        XCTAssertNil(featureFlagger.getCohortIfEnabled(for: AccessCredentialManagementFlag()))

        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)
        XCTAssertEqual(experimentManager.cohort(for: AutofillSubfeature.credentialsSaving.rawValue), "control")
        XCTAssertEqual(experimentManager.cohort(for: AutofillSubfeature.inlineIconCredentials.rawValue), "green")
        XCTAssertNil(experimentManager.cohort(for: AutofillSubfeature.accessCredentialManagement.rawValue))
        XCTAssertFalse(mockStore.experiments?.isEmpty ?? true)

        var activeExperiments = featureFlagger.getAllActiveExperiments()
        XCTAssertEqual(activeExperiments.count, 2)
        XCTAssertEqual(activeExperiments[AutofillSubfeature.credentialsSaving.rawValue]?.cohortID, "control")
        XCTAssertEqual(activeExperiments[AutofillSubfeature.inlineIconCredentials.rawValue]?.cohortID, "green")
        XCTAssertNil(activeExperiments[AutofillSubfeature.accessCredentialManagement.rawValue])

        // When an assigned cohort is removed it's not part of active experiments
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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "blue",
                                        "weight": 1
                                    }
                                ]
                            },
                            "inlineIconCredentials": {
                                "state": "enabled",
                                "minSupportedVersion": 1,
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "control",
                                        "weight": 0
                                    },
                                    {
                                        "name": "green",
                                        "weight": 1
                                    }
                                ]
                            },
                            "accessCredentialManagement": {
                                "state": "enabled",
                                "minSupportedVersion": 3,
                                "targets": [
                                    {
                                        "localeCountry": "CA"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "control",
                                        "weight": 1
                                    },
                                    {
                                        "name": "green",
                                        "weight": 0
                                    }
                                ]
                            }
                        }
                    }
                }
            }
            """.data(using: .utf8)!

        manager.reload(etag: "foo", data: featureJson)

        activeExperiments = featureFlagger.getAllActiveExperiments()
        XCTAssertEqual(activeExperiments.count, 1)
        XCTAssertNil(activeExperiments[AutofillSubfeature.credentialsSaving.rawValue])
        XCTAssertEqual(activeExperiments[AutofillSubfeature.inlineIconCredentials.rawValue]?.cohortID, "green")
        XCTAssertNil(activeExperiments[AutofillSubfeature.accessCredentialManagement.rawValue])

        // When feature disabled an assigned cohort it's not part of active experiments
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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "blue",
                                        "weight": 1
                                    }
                                ]
                            },
                            "inlineIconCredentials": {
                                "state": "disabled",
                                "minSupportedVersion": 1,
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "control",
                                        "weight": 0
                                    },
                                    {
                                        "name": "green",
                                        "weight": 1
                                    }
                                ]
                            },
                            "accessCredentialManagement": {
                                "state": "enabled",
                                "minSupportedVersion": 3,
                                "targets": [
                                    {
                                        "localeCountry": "CA"
                                    }
                                ],
                                "cohorts": [
                                    {
                                        "name": "control",
                                        "weight": 1
                                    },
                                    {
                                        "name": "green",
                                        "weight": 0
                                    }
                                ]
                            }
                        }
                    }
                }
            }
            """.data(using: .utf8)!

        manager.reload(etag: "foo", data: featureJson)

        activeExperiments = featureFlagger.getAllActiveExperiments()
        XCTAssertTrue(activeExperiments.isEmpty)
    }

    func testOnAssignmentReportAssignmentFunctionCalled() {
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
                                "targets": [
                                    {
                                        "localeCountry": "US"
                                    }
                                ],
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
        manager.reload(etag: "foo", data: featureJson)
        let config = manager.privacyConfig

        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, cohortID: "control"))
        XCTAssertEqual(self.assignedCohort, "control")
        XCTAssertEqual(self.assignedExperiment, "credentialsSaving")
    }
}
