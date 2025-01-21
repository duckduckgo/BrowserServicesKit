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

public enum TdsExperimentMetricType: String {
    /// Metric triggered when the privacy toggle is used.
    case privacyToggleUsed = "privacyToggleUsed"
    /// Metric triggered after 2 quick refreshes.
    case refresh2X = "2XRefresh"
    /// Metric triggered after 3 quick refreshes.
    case refresh3X = "3XRefresh"
}

public struct TDSOverrideExperimentMetrics {

    public typealias FirePixelExperiment = (SubfeatureID, String, ConversionWindow, String) -> Void
    public typealias FireDebugExperiment = (_ parameters: [String: String]) -> Void

    private struct ExperimentConfig {
        static var firePixelExperiment: FirePixelExperiment = { subfeatureID, metric, conversionWindow, value in
            PixelKit.fireExperimentPixel(for: subfeatureID, metric: metric, conversionWindowDays: conversionWindow, value: value)
        }
    }

    static func configureTDSOverrideExperimentMetrics(firePixelExperiment: @escaping FirePixelExperiment) {
        ExperimentConfig.firePixelExperiment = firePixelExperiment
    }

    public static var activeTDSExperimentNameWithCohort: String? {
        guard let featureFlagger = PixelKit.ExperimentConfig.featureFlagger else { return nil }
        let activeExperiments = featureFlagger.getAllActiveExperiments()

        for experimentType in TdsExperimentType.allCases {
            let subfeatureID = experimentType.subfeature.rawValue
            if let experimentData = activeExperiments[subfeatureID] {
                return "\(subfeatureID)_\(experimentData.cohortID)"
            }
        }
        return nil
    }


    public static func fireTdsExperimentMetric(
        metricType: TdsExperimentMetricType,
        etag: String,
        fireDebugExperiment: @escaping FireDebugExperiment
    ) {
        for experiment in TdsExperimentType.allCases {
            for day in 0...5 {
                ExperimentConfig.firePixelExperiment(
                    experiment.subfeature.rawValue,
                    metricType.rawValue,
                    day...day,
                    "1"
                )
                fireDebugBreakageExperiment(
                    experimentType: experiment,
                    etag: etag,
                    fire: fireDebugExperiment
                )
            }
        }
    }

    private static func fireDebugBreakageExperiment(experimentType: TdsExperimentType,
                                                    etag: String,
                                                    fire: @escaping FireDebugExperiment) {
        guard
            let featureFlagger = PixelKit.ExperimentConfig.featureFlagger,
            let experimentData = featureFlagger.getAllActiveExperiments()[experimentType.subfeature.rawValue]
        else { return }

        let experimentName: String = experimentType.subfeature.rawValue + experimentData.cohortID
        let enrolmentDate = experimentData.enrollmentDate.toYYYYMMDDInET()
        let parameters = [
            "experiment": experimentName,
            "enrolmentDate": enrolmentDate,
            "tdsEtag": etag
        ]
        fire(parameters)
    }
}
