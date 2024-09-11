//
//  Logger+PhishingDetection.swift
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
import os

public extension Logger {
    static var phishingDetection: Logger = { Logger(subsystem: "Phishing Detection", category: "") }()
    static var phishingDetectionClient: Logger = { Logger(subsystem: "Phishing Detection", category: "APIClient") }()
    static var phishingDetectionTasks: Logger = { Logger(subsystem: "Phishing Detection", category: "BackgroundActivities") }()
    static var phishingDetectionDataProvider: Logger = { Logger(subsystem: "Phishing Detection", category: "DataProvider") }()
    static var phishingDetectionDataStore: Logger = { Logger(subsystem: "Phishing Detection", category: "DataStore") }()
    static var phishingDetectionUpdateManager: Logger = { Logger(subsystem: "Phishing Detection", category: "UpdateManager") }()
}
