//
//  PixelExperimentKit.swift
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

import PixelKit
import BrowserServicesKit
import Foundation

struct ExperimentEvent: PixelKitEvent {
    var name: String
    var parameters: [String : String]?
}

public protocol ExperimentActionPixelStore {
    func removeObject(forKey defaultName: String)
    func integer(forKey defaultName: String) -> Int
    func set(_ value: Int, forKey defaultName: String)
}

extension PixelKit {

    struct Constants {
        static let enrollmentEventPrefix = "experiment_enroll"
        static let metricsEventPrefix = "experiment_metrics"
        static let metricKey = "metric"
        static let conversionWindowDaysKey = "conversionWindowDays"
        static let valueKey = "value"
        static let enrollmentDateKey = "enrollmentDate"
        static let searchMetricValue = "search"
        static let appUseMetricValue = "app_use"
    }

    // Static property to hold shared dependencies
    struct ExperimentConfig {
        static var privacyConfigManager: PrivacyConfigurationManager?
        static var store: ExperimentActionPixelStore = UserDefaults.standard
        static var fireFunction: (PixelKitEvent, PixelKit.Frequency, Bool) -> Void = { event, frequency, includeAppVersion in
            fire(event, frequency: frequency, includeAppVersionParameter: includeAppVersion)
        }
    }

    // Setup method to initialize dependencies
    public static func configureExperimentKit(
        privacyConfigManager: PrivacyConfigurationManager,
        store: ExperimentActionPixelStore = UserDefaults.standard,
        fire: @escaping (PixelKitEvent, PixelKit.Frequency, Bool) -> Void = { event, frequency, includeAppVersion in
            fire(event, frequency: frequency, includeAppVersionParameter: includeAppVersion)
        }
    ) {
        ExperimentConfig.privacyConfigManager = privacyConfigManager
        ExperimentConfig.store = store
        ExperimentConfig.fireFunction = fire
    }

    /// Fires a pixel indicating the user's enrollment in an experiment.
    /// - Parameters:
    ///   - subfeatureID: Identifier for the subfeature associated with the experiment.
    ///   - experiment: Data about the experiment like cohort and enrollment date
    public static func fireExperimentEnrollmentPixel(subfeatureID: SubfeatureID, experiment: ExperimentData) {
        let eventName = "\(Self.Constants.enrollmentEventPrefix)_\(subfeatureID)_\(experiment.cohort)"
        let event = ExperimentEvent(name: eventName, parameters: [Self.Constants.enrollmentDateKey: experiment.enrollmentDate.toYYYYMMDDInET()])
        ExperimentConfig.fireFunction(event, .uniqueIncludingParameters, false)
    }

    /// Fires a pixel for a specific action in an experiment, based on conversion window and value thresholds (if value is a number).
    /// - Parameters:
    ///   - subfeatureID: Identifier for the subfeature associated with the experiment.
    ///   - metric: The name of the metric being tracked (e.g., "searches").
    ///   - conversionWindowDays: The range of days after enrollment during which the action is valid.
    ///   - value: A specific value associated to the action. It could be the target number of actions required to fire the pixel.
    ///
    /// This function:
    /// 1. Validates if the experiment is active.
    /// 2. Ensures the user is within the specified conversion window.
    /// 3. Tracks actions performed and sends the pixel once the target value is reached (if applicable).
    public static func fireExperimentPixel(for subfeatureID: SubfeatureID, metric: String, conversionWindowDays: ClosedRange<Int>, value: String) {
        // Check is active experiment for user
        guard let privacyConfigManager = ExperimentConfig.privacyConfigManager else {
            assertionFailure("PrivacyConfigurationManager is not configured")
            return
        }
        guard let experimentData = privacyConfigManager.privacyConfig.getAllActiveExperiments()[subfeatureID] else { return }

        Self.fireExperimentPixelForActiveExperiment(subfeatureID, experimentData: experimentData, metric: metric, conversionWindowDays: conversionWindowDays, value: value)
    }

    /// Fires search-related experiment pixels for all active experiments.
    ///
    /// This function iterates through all active experiments and triggers
    /// pixel firing based on predefined search-related value and conversion window mappings.
    /// - The value and conversion windows define when and how many search actions
    ///   must occur before the pixel is fired.
    public static func fireSearchExperimentPixels() {
        let valueConversionDictionary: [Int: [ClosedRange<Int>]] = [
            1: [0...0, 1...1, 2...2, 3...3, 4...4, 5...5, 6...6, 7...7, 5...7],
            4: [5...7, 8...15],
            6: [5...7, 8...15],
            11: [5...7, 8...15],
            21: [5...7, 8...15],
            30: [5...7, 8...15]
        ]
        guard let privacyConfigManager = ExperimentConfig.privacyConfigManager else {
            assertionFailure("PrivacyConfigurationManager is not configured")
            return
        }
        privacyConfigManager.privacyConfig.getAllActiveExperiments().forEach { experiment in
            fireExperimentPixelsfor(
                experiment.key,
                experimentData: experiment.value,
                metric: Self.Constants.searchMetricValue,
                valueConversionDictionary: valueConversionDictionary
            )
        }
    }

    /// Fires app retention-related experiment pixels for all active experiments.
    ///
    /// This function iterates through all active experiments and triggers
    /// pixel firing based on predefined app retention value and conversion window mappings.
    /// - The value and conversion windows define when and how many app usage actions
    ///   must occur before the pixel is fired.
    public static func fireAppRetentionExperimentPixels() {
        let valueConversionDictionary: [Int: [ClosedRange<Int>]] = [
            1: [1...1, 2...2, 3...3, 4...4, 5...5, 6...6, 7...7, 5...7],
            4: [5...7, 8...15],
            6: [5...7, 8...15],
            11: [5...7, 8...15],
            21: [5...7, 8...15],
            30: [5...7, 8...15]
        ]
        guard let privacyConfigManager = ExperimentConfig.privacyConfigManager else {
            assertionFailure("PrivacyConfigurationManager is not configured")
            return
        }
        privacyConfigManager.privacyConfig.getAllActiveExperiments().forEach { experiment in
            fireExperimentPixelsfor(
                experiment.key,
                experimentData: experiment.value,
                metric: Self.Constants.appUseMetricValue,
                valueConversionDictionary: valueConversionDictionary
            )
        }
    }

    private static func fireExperimentPixelsfor(
        _ experiment: SubfeatureID,
        experimentData: ExperimentData,
        metric: String,
        valueConversionDictionary: [Int: [ClosedRange<Int>]]
    ) {
        valueConversionDictionary.forEach { value, ranges in
            ranges.forEach { range in
                fireExperimentPixelForActiveExperiment(
                    experiment,
                    experimentData: experimentData,
                    metric: metric,
                    conversionWindowDays: range,
                    value: "\(value)"
                )
            }
        }
    }

    private static func fireExperimentPixelForActiveExperiment(_ subfeatureID: SubfeatureID, experimentData: ExperimentData,metric: String, conversionWindowDays: ClosedRange<Int>, value: String) {
        // Set parameters, event name, store key
        let eventName = "\(Self.Constants.metricsEventPrefix)_\(subfeatureID)_\(experimentData.cohort)"
        let parameters: [String: String] = [
            Self.Constants.metricKey: metric,
            Self.Constants.conversionWindowDaysKey: "\(conversionWindowDays.lowerBound.description)-\(conversionWindowDays.upperBound.description)",
            Self.Constants.valueKey: value,
            Self.Constants.enrollmentDateKey: experimentData.enrollmentDate.toYYYYMMDDInET()
        ]
        let event = ExperimentEvent(name: eventName, parameters: parameters)
        let eventStoreKey = eventName + "_" + parameters.escapedString()

        // Check if user is in conversion window
        // if not don't send pixel and remove related action from the store
        guard isUserInConversionWindow(conversionWindowDays, enrollmentDate: experimentData.enrollmentDate) else {
            ExperimentConfig.store.removeObject(forKey: eventStoreKey)
            return
        }

        // Check if value is a number
        // if so check if the action for the given experiment and parameter has been performed a number of time >= than the required
        // if so send the pixel
        // if not increase the count of the action
        // if value is not a number send the pixel
        if let numberOfAction = Int(value), numberOfAction > 1 {
            let actualActionNumber = ExperimentConfig.store.integer(forKey: eventStoreKey)
            if actualActionNumber >= numberOfAction {
                ExperimentConfig.fireFunction(event, .uniqueIncludingParameters, false)
            } else {
                ExperimentConfig.store.set(actualActionNumber + 1, forKey: eventStoreKey)
            }
        } else {
            ExperimentConfig.fireFunction(event, .uniqueIncludingParameters, false)
        }
    }

    private static func isUserInConversionWindow(_ conversionWindowDays: ClosedRange<Int>, enrollmentDate: Date) -> Bool {
        guard let startOfWindowDate = enrollmentDate.addDays(conversionWindowDays.lowerBound) else { return false }
        guard let endOfWindowDate = enrollmentDate.addDays(conversionWindowDays.upperBound) else { return false }
        return Date() >= startOfWindowDate && Date() <= endOfWindowDate
    }
}

extension Dictionary where Key: Comparable {
    func escapedString(pairSeparator: String = ":", entrySeparator: String = ",") -> String {
        return self.sorted { $0.key < $1.key }
            .map { "\("\($0.key)".replacingOccurrences(of: entrySeparator, with: "\\\(entrySeparator)"))\(pairSeparator)\("\($0.value)".replacingOccurrences(of: entrySeparator, with: "\\\(entrySeparator)"))" }
            .joined(separator: entrySeparator)
    }
}

extension UserDefaults: ExperimentActionPixelStore {}

extension Date {
    public func toYYYYMMDDInET() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: self)
    }

    func addDays(_ days: Int) -> Date? {
        return Calendar.current.date(byAdding: .day, value: days, to: self)
    }
}
