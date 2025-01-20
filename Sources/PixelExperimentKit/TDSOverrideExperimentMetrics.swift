//
//  TDSOverrideExperimentMetrics.swift
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

import Foundation
import PixelKit
import Configuration
import BrowserServicesKit


// MARK: - Tds Overrider Experiment Metrics
public struct TDSOverrideExperimentMetrics {

    private struct ExperimentConfig {
        static var firePixelExperiment: (SubfeatureID, String, ConversionWindow, String) -> Void = { subfeatureID, metric, conversionWindow, value in
            PixelKit.fireExperimentPixel(for: subfeatureID, metric: metric, conversionWindowDays: conversionWindow, value: value)
        }
    }

    static func configureTDSOverrideExperimentMetrics(firePixelExperiment: @escaping (SubfeatureID, String, ConversionWindow, String) -> Void) {
        ExperimentConfig.firePixelExperiment = firePixelExperiment
    }

    public static func fireTdsExperimentMetricPrivacyToggleUsed(
        etag: String,
        featureFlagger: FeatureFlagger,
        fireDebugExperiment: @escaping (_ parameters: [String: String]) -> Void
    ) {
        for experiment in TdsExperimentType.allCases {
            for day in 0...5 {
                ExperimentConfig.firePixelExperiment(
                    experiment.subfeature.rawValue,
                    "privacyToggleUsed",
                    day...day,
                    "1"
                )
                fireDebugBreakageExperiment(
                    experimentType: experiment,
                    etag: etag,
                    featureFlagger: featureFlagger,
                    fire: fireDebugExperiment
                )
            }
        }
    }

    public static func fireTdsExperimentMetric2XRefresh(
        etag: String,
        featureFlagger: FeatureFlagger,
        fireDebugExperiment: @escaping (_ parameters: [String: String]) -> Void
    ) {
        for experiment in TdsExperimentType.allCases {
            for day in 0...5 {
                ExperimentConfig.firePixelExperiment(
                    experiment.subfeature.rawValue,
                    "2XRefresh",
                    day...day,
                    "1"
                )
                fireDebugBreakageExperiment(
                    experimentType: experiment,
                    etag: etag,
                    featureFlagger: featureFlagger,
                    fire: fireDebugExperiment
                )
            }
        }
    }

    public static func fireTdsExperimentMetric3XRefresh(
        etag: String,
        featureFlagger: FeatureFlagger,
        fireDebugExperiment: @escaping (_ parameters: [String: String]) -> Void
    ) {
        for experiment in TdsExperimentType.allCases {
            for day in 0...5 {
                ExperimentConfig.firePixelExperiment(
                    experiment.subfeature.rawValue,
                    "3XRefresh",
                    day...day,
                    "1"
                )
                fireDebugBreakageExperiment(
                    experimentType: experiment,
                    etag: etag,
                    featureFlagger: featureFlagger,
                    fire: fireDebugExperiment
                )
            }
        }
    }

    public static var activeTDSExperimentNameWithCohort: String? {
        guard let featureFlagger = PixelKit.ExperimentConfig.featureFlagger else { return nil }
        let activeExperiments = featureFlagger.getAllActiveExperiments()
        for experimentType in TdsExperimentType.allCases {
            let subfeatureID = experimentType.subfeature.rawValue
            if activeExperiments.contains(where: { $0.key == subfeatureID }) {
                guard let experimentData = featureFlagger.getAllActiveExperiments()[subfeatureID] else { return nil }
                return "\(subfeatureID)_\(experimentData.cohortID)"
            }
        }
        return nil
    }

    private static func fireDebugBreakageExperiment(experimentType: TdsExperimentType, etag: String, featureFlagger: FeatureFlagger, fire: @escaping (_ parameters: [String: String]) -> Void) {
        let subfeatureID = experimentType.subfeature.rawValue
        let wasCohortAssigned = featureFlagger.getAllActiveExperiments().contains(where: { $0.key == subfeatureID })
        guard let experimentData = featureFlagger.getAllActiveExperiments()[subfeatureID] else { return }
        guard wasCohortAssigned else { return }
        let experimentName: String = subfeatureID + experimentData.cohortID
        let enrolmentDate = experimentData.enrollmentDate.toYYYYMMDDInET()
        let parameters = [
            "experiment": experimentName,
            "enrolmentDate": enrolmentDate,
            "tdsEtag": etag
        ]
        fire(parameters)
    }
}
