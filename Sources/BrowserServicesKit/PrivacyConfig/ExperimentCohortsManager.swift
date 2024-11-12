//
//  ExperimentCohortsManager.swift
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

import Foundation

struct ExperimentSubfeature {
    let subfeatureID: SubfeatureID
    let cohorts: [PrivacyConfigurationData.Cohort]
}

typealias CohortID = String
typealias SubfeatureID = String

struct ExperimentData: Codable, Equatable {
    let cohort: String
    let enrollmentDate: Date
}

typealias Experiments = [String: ExperimentData]

protocol ExperimentCohortsManaging {
    /// Retrieves the cohort ID associated with the specified subfeature.
    /// - Parameter subfeature: The experiment subfeature for which the cohort ID is needed.
    /// - Returns: The cohort ID as a `String` if one exists; otherwise, returns `nil`.
    func cohort(for subfeatureID: SubfeatureID) async -> CohortID?

    /// Retrieves the enrollment date for the specified subfeature.
    /// - Parameter subfeatureID: The experiment subfeature for which the enrollment date is needed.
    /// - Returns: The `Date` of enrollment if one exists; otherwise, returns `nil`.
    func enrollmentDate(for subfeatureID: SubfeatureID) async -> Date?

    /// Assigns a cohort to the given subfeature based on defined weights and saves it to UserDefaults.
    /// - Parameter subfeature: The experiment subfeature to assign a cohort for.
    /// - Returns: The name of the assigned cohort, or `nil` if no cohort could be assigned.
    func assignCohort(to subfeature: ExperimentSubfeature) async -> CohortID?

    /// Removes the assigned cohort data for the specified subfeature.
    /// - Parameter subfeature: The experiment subfeature for which the cohort data should be removed.
    func removeCohort(from subfeatureID: SubfeatureID) async
}

final class ExperimentCohortsManager: ExperimentCohortsManaging {

    private var store: ExperimentsDataStoring
    private let randomizer: (Range<Double>) -> Double

    init(store: ExperimentsDataStoring = ExperimentsDataStore(), randomizer: @escaping (Range<Double>) -> Double) {
        self.store = store
        self.randomizer = randomizer
    }

    func cohort(for subfeatureID: SubfeatureID) async -> CohortID? {
        guard let experiments = await store.getExperiments() else { return nil }
        return experiments[subfeatureID]?.cohort
    }

    func enrollmentDate(for subfeatureID: SubfeatureID) async -> Date? {
        guard let experiments = await store.getExperiments() else { return nil }
        return experiments[subfeatureID]?.enrollmentDate
    }

    func assignCohort(to subfeature: ExperimentSubfeature) async -> CohortID? {
        let cohorts = subfeature.cohorts
        let totalWeight = cohorts.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }

        let randomValue = randomizer(0..<Double(totalWeight))
        var cumulativeWeight = 0.0

        for cohort in cohorts {
            cumulativeWeight += Double(cohort.weight)
            if randomValue < cumulativeWeight {
                await saveCohort(cohort.name, in: subfeature.subfeatureID)
                return cohort.name
            }
        }
        return nil
    }

    func removeCohort(from subfeatureID: SubfeatureID) async {
        guard var experiments = await store.getExperiments() else { return }
        experiments.removeValue(forKey: subfeatureID)
        await store.setExperiments(experiments)
    }

    private func saveCohort(_ cohort: CohortID, in experimentID: SubfeatureID) async {
        var experiments = await store.getExperiments() ?? Experiments()
        let experimentData = ExperimentData(cohort: cohort, enrollmentDate: Date())
        experiments[experimentID] = experimentData
        await store.setExperiments(experiments)
    }
}
