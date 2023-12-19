//
//  ConfigurationValidating.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import TrackerRadarKit
import Common

protocol ConfigurationValidating {

    func validate(_ data: Data, for configuration: Configuration) throws

}

public struct ConfigurationValidator: ConfigurationValidating {

    private let eventMapping: EventMapping<ConfigurationDebugEvents>?

    init(eventMapping: EventMapping<ConfigurationDebugEvents>? = nil) {
        self.eventMapping = eventMapping
    }

    func validate(_ data: Data, for configuration: Configuration) throws {
        do {
            switch configuration {
            case .privacyConfiguration:
                try validatePrivacyConfiguration(with: data)
            case .trackerDataSet:
                try validateTrackerDataSet(with: data)
            default:
                break
            }
        } catch {
            eventMapping?.fire(.invalidPayload(configuration), error: error)
            throw ConfigurationFetcher.Error.invalidPayload
        }
    }

    private func validatePrivacyConfiguration(with data: Data) throws {
        _ = try PrivacyConfigurationData(data: data)
    }

    private func validateTrackerDataSet(with data: Data) throws {
        _ = try JSONDecoder().decode(TrackerData.self, from: data)
    }

}
