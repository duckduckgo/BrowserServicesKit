//
//  PrivacyDashboardEntryPoint.swift
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

/// Represents the type of web page displayed within the privacy dashboard flow.
public enum PrivacyDashboardEntryPoint: Equatable {
    /// The standard dashboard page that appears when the user taps on the shield icon.
    /// This page displays the toggle protection option and provides information on trackers.
    case dashboard

    /// The report broken site screen, which is accessed from the app menu.
    /// This only allows users to report issues with websites.
    case report

    /// The toggle report screen, which is triggered whenever the user toggles off protection (from outside of Privacy Dashboard)
    /// This is only available on iOS, as macOS does not have an option to disable protection outside of the dashboard.
    case toggleReport(completionHandler: (Bool) -> Void)

    /// The prompt report screen, which is triggered whenever the user taps report from the toast 'Site not working?"
    case prompt

    /// The experimental after toggle prompt screen, presented in variant B.
    /// After the user toggles off protection, this prompt asks if the action helped and allows the user to report their experience.
    /// - Parameters:
    ///   - category: The category of the issue reported by the user.
    ///   - didToggleProtectionsFixIssue: A Boolean indicating whether toggling protections resolved the issue.
    case afterTogglePrompt(category: String, didToggleProtectionsFixIssue: Bool)

    var screen: Screen {
        switch self {
        case .dashboard: return .primaryScreen
        case .report: return .breakageForm
        case .afterTogglePrompt: return .choiceBreakageForm
        case .prompt: return .promptBreakageForm
        case .toggleReport: return .toggleReport
        }
    }

    public static func == (lhs: PrivacyDashboardEntryPoint, rhs: PrivacyDashboardEntryPoint) -> Bool {
        switch (lhs, rhs) {
        case
            (.dashboard, .dashboard),
            (.report, .report),
            (.toggleReport, .toggleReport),
            (.prompt, .prompt),
            (.afterTogglePrompt, .afterTogglePrompt):
            return true
        default:
            return false
        }
    }

}
