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

public struct ExperimentSubfeature {
    let parentID: ParentFeatureID
    let subfeatureID: SubfeatureID
    let cohorts: [PrivacyConfigurationData.Cohort]
}

public typealias CohortID = String
public typealias SubfeatureID = String
public typealias ParentFeatureID = String

public struct ExperimentData: Codable, Equatable {
    public let parentID: String
    public let cohort: String
    public let enrollmentDate: Date
}

public typealias Experiments = [String: ExperimentData]

public protocol ExperimentCohortsManaging {
    /// Retrieves the cohort ID associated with the specified subfeature.
    /// - Parameter subfeature: The experiment subfeature for which the cohort ID is needed.
    /// - Returns: The cohort ID as a `String` if one exists; otherwise, returns `nil`.
    func cohort(for subfeatureID: SubfeatureID) -> CohortID?

    /// Retrieves the enrollment date for the specified subfeature.
    /// - Parameter subfeatureID: The experiment subfeature for which the enrollment date is needed.
    /// - Returns: The `Date` of enrollment if one exists; otherwise, returns `nil`.
    func enrollmentDate(for subfeatureID: SubfeatureID) -> Date?

    /// Assigns a cohort to the given subfeature based on defined weights and saves it to UserDefaults.
    /// - Parameter subfeature: The experiment subfeature to assign a cohort for.
    /// - Returns: The name of the assigned cohort, or `nil` if no cohort could be assigned.
    func assignCohort(to subfeature: ExperimentSubfeature) -> CohortID?

    /// Removes the assigned cohort data for the specified subfeature.
    /// - Parameter subfeature: The experiment subfeature for which the cohort data should be removed.
    func removeCohort(from subfeatureID: SubfeatureID)
}

public final class ExperimentCohortsManager: ExperimentCohortsManaging {

    private var store: ExperimentsDataStoring
    private let randomizer: (Range<Double>) -> Double

    var experiments: Experiments? {
        store.experiments
    }

    public init(store: ExperimentsDataStoring = ExperimentsDataStore(), 
         randomizer: @escaping (Range<Double>) -> Double = Double.random(in:)) {
        self.store = store
        self.randomizer = randomizer
    }

    public func cohort(for subfeatureID: SubfeatureID) -> CohortID? {
        guard let experiments = experiments else { return nil }
        return experiments[subfeatureID]?.cohort
    }

    public func enrollmentDate(for subfeatureID: SubfeatureID) -> Date? {
        guard let experiments = experiments else { return nil }
        return experiments[subfeatureID]?.enrollmentDate
    }

    public func assignCohort(to subfeature: ExperimentSubfeature) -> CohortID? {
        let cohorts = subfeature.cohorts
        let totalWeight = cohorts.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }

        let randomValue = randomizer(0..<Double(totalWeight))
        var cumulativeWeight = 0.0

        for cohort in cohorts {
            cumulativeWeight += Double(cohort.weight)
            if randomValue < cumulativeWeight {
                saveCohort(cohort.name, in: subfeature.subfeatureID, parentID: subfeature.parentID)
                return cohort.name
            }
        }
        return nil
    }

    public func removeCohort(from subfeatureID: SubfeatureID) {
        guard var experiments = experiments else { return }
        experiments.removeValue(forKey: subfeatureID)
        saveExperiment(experiments)
    }

    private func saveExperiment(_ experiments: Experiments) {
        store.experiments = experiments
    }

    private func saveCohort(_ cohort: CohortID, in experimentID: SubfeatureID, parentID: ParentFeatureID) {
        var experiments = experiments ?? Experiments()
        let experimentData = ExperimentData(parentID: parentID, cohort: cohort, enrollmentDate: Date())
        experiments[experimentID] = experimentData
        saveExperiment(experiments)
    }
}
