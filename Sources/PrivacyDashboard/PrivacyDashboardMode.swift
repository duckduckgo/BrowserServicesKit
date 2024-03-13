//
//  PrivacyDashboardMode.swift
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

/// Type of web page displayed
public enum PrivacyDashboardMode: Equatable {

    case dashboard
    case report
    case toggleReport(completionHandler: (Bool) -> Void)

    var screen: PrivacyDashboard.Screen {
        switch self {
        case .dashboard: return .primaryScreen
        case .report: return .breakageForm
        case .toggleReport: return .toggleReport
        }
    }

    public static func == (lhs: PrivacyDashboardMode, rhs: PrivacyDashboardMode) -> Bool {
        switch (lhs, rhs) {
        case (.dashboard, .dashboard), (.report, .report), (.toggleReport, .toggleReport):
            return true
        default:
            return false
        }
    }

}
