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
    /// Retrieves all the experiments a user is enrolled into
    var experiments: Experiments? { get }

    /// Retrieves the assigned cohort for a given experiment subfeature, or attempts to assign a new cohort if none is currently assigned
    /// and `assignIfEnabled` is set to true. If a cohort is already assigned but does not match any valid cohorts for the experiment,
    /// the cohort will be removed.
    ///
    /// - Parameters:
    ///   - experiment: The `ExperimentSubfeature` for which to retrieve, assign, or remove a cohort. This subfeature includes
    ///     relevant identifiers and potential cohorts that may be assigned.
    ///   - assignIfEnabled: A Boolean value that determines whether a new cohort should be assigned if none is currently assigned.
    ///     If `true`, the function will attempt to assign a cohort from the available options; otherwise, it will only check for existing assignments.
    ///
    /// - Returns: A tuple containing:
    ///   - `cohortID`: The identifier of the assigned cohort if one exists, or `nil` if no cohort was assigned, if assignment failed, or if the cohort was removed.
    ///   - `didAttemptAssignment`: A Boolean indicating whether an assignment attempt was made. This will be `true` if `assignIfEnabled`
    ///     is `true` and no cohort was previously assigned, and `false` otherwise.
    func cohort(for experiment: ExperimentSubfeature, assignIfEnabled: Bool) -> (cohortID: CohortID?, didAttemptAssignment: Bool)
}

public class ExperimentCohortsManager: ExperimentCohortsManaging {

    private var store: ExperimentsDataStoring
    private let randomizer: (Range<Double>) -> Double
    private let queue = DispatchQueue(label: "com.ExperimentCohortsManager.queue")

    public var experiments: Experiments? {
        get {
            queue.sync {
                store.experiments
            }
        }
    }

    public init(store: ExperimentsDataStoring, randomizer: @escaping (Range<Double>) -> Double = Double.random(in:)) {
        self.store = store
        self.randomizer = randomizer
    }

    public func cohort(for experiment: ExperimentSubfeature, assignIfEnabled: Bool) -> (cohortID: CohortID?, didAttemptAssignment: Bool) {
        queue.sync {
            let assignedCohort = cohort(for: experiment.subfeatureID)
            if experiment.cohorts.contains(where: { $0.name == assignedCohort }) {
                return (assignedCohort, false)
            } else {
                removeCohort(from: experiment.subfeatureID)
            }

            return assignIfEnabled ? (assignCohort(to: experiment), true) : (nil, true)
        }
    }

    private func assignCohort(to subfeature: ExperimentSubfeature) -> CohortID? {
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

    func cohort(for subfeatureID: SubfeatureID) -> CohortID? {
        guard let experiments = store.experiments else { return nil }
        return experiments[subfeatureID]?.cohort
    }

    private  func enrollmentDate(for subfeatureID: SubfeatureID) -> Date? {
        guard let experiments = store.experiments else { return nil }
        return experiments[subfeatureID]?.enrollmentDate
    }

    private func removeCohort(from subfeatureID: SubfeatureID) {
        guard var experiments = store.experiments else { return }
        experiments.removeValue(forKey: subfeatureID)
        store.experiments = experiments
    }

    private func saveCohort(_ cohort: CohortID, in experimentID: SubfeatureID, parentID: ParentFeatureID) {
        var experiments = store.experiments ?? Experiments()
        let experimentData = ExperimentData(parentID: parentID, cohort: cohort, enrollmentDate: Date())
        experiments[experimentID] = experimentData
        store.experiments = experiments
    }

}
