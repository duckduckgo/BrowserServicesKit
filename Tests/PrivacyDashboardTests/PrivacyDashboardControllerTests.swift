//
//  PrivacyDashboardControllerTests.swift
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

import XCTest
import Combine
import Common
import WebKit
@testable import PrivacyDashboard
@testable import BrowserServicesKit

final class PrivacyDashboardDelegateMock: PrivacyDashboardControllerDelegate {

    var didChangeProtectionSwitchCalled = false
    var protectionState: ProtectionState? = nil
    var didSendReport = false
    var didRequestCloseCalled = false

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didChangeProtectionSwitch protectionState: ProtectionState,
                                    didSendReport: Bool) {
        didChangeProtectionSwitchCalled = true
        self.protectionState = protectionState
        self.didSendReport = didSendReport

    }
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitToggleReportWithSource source: BrokenSiteReport.Source) {
    }

    func privacyDashboardControllerDidRequestClose(_ privacyDashboardController: PrivacyDashboardController) {
        didRequestCloseCalled = true
    }

    // not under tests

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, didRequestOpenUrlInNewTab url: URL) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestOpenSettings target: PrivacyDashboardOpenSettingsTarget) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, didSelectBreakageCategory category: String) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitBrokenSiteReportWithCategory category: String,
                                    description: String) {}
    func privacyDashboardControllerDidRequestShowAlertForMissingDescription(_ privacyDashboardController: PrivacyDashboardController) {}
    func privacyDashboardControllerDidRequestShowGeneralFeedback(_ privacyDashboardController: PrivacyDashboardController) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, didSetHeight height: Int) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didSetPermission permissionName: String,
                                    to state: PermissionAuthorizationState) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, setPermission permissionName: String, paused: Bool) { }

}


final class PrivacyDashboardControllerTests: XCTestCase {

    var privacyDashboardController: PrivacyDashboardController!
    var mockDelegate: PrivacyDashboardDelegateMock!
    var webView: WKWebView!

    @MainActor 
    private func makePrivacyDashboardController(entryPoint: PrivacyDashboardEntryPoint) {
        mockDelegate = PrivacyDashboardDelegateMock()
        let toggleReportsFeature = ToggleReportsFeature(privacyConfigurationToggleReportsFeature: .init(isEnabled: true, settings: [:]),
                                                        currentLocale: Locale(identifier: "en"))
        privacyDashboardController = PrivacyDashboardController(privacyInfo: nil,
                                                                entryPoint: entryPoint,
                                                                variant: .control,
                                                                toggleReportsFeature: toggleReportsFeature,
                                                                eventMapping: EventMapping<PrivacyDashboardEvents> { _, _, _, _ in })
        webView = WKWebView()
        privacyDashboardController.setup(for: webView)
        privacyDashboardController.privacyDashboardDelegate = mockDelegate
    }

    // MARK: - Setup

    @MainActor
    func testOpenCorrectURL() {
        let entryPoints: [PrivacyDashboardEntryPoint] = [
            .dashboard,
            .report,
            .afterTogglePrompt(category: "apple", didToggleProtectionsFixIssue: false),
            .toggleReport(completionHandler: { _ in })
        ]
        for entryPoint in entryPoints {
            makePrivacyDashboardController(entryPoint: entryPoint)
            let currentURL = privacyDashboardController.webView!.url
            XCTAssertEqual(currentURL?.getParameter(named: "screen"), entryPoint.screen(for: .control).rawValue)
            if case .afterTogglePrompt(_, _) = entryPoint {
                XCTAssertEqual(currentURL?.getParameter(named: "category"), "apple")
            }
            if case .toggleReport(_) = entryPoint {
                XCTAssertEqual(currentURL?.getParameter(named: "opener"), "menu")
            }
        }
    }

    // MARK: - didChangeProtectionState

    @MainActor
    func testUserScriptDidDisableProtectionStateNotFromPrimaryScreenShouldNotSegueToToggleReportScreen() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        let allScreensButPrimaryScreen = Screen.allCases.filter { $0 != .primaryScreen }
        for screen in allScreensButPrimaryScreen {
            let protectionState = ProtectionState(isProtected: false, eventOrigin: .init(screen: screen))
            privacyDashboardController.userScript(PrivacyDashboardUserScript(), didChangeProtectionState: protectionState)
            XCTAssertTrue(mockDelegate.didChangeProtectionSwitchCalled)
            XCTAssertFalse(mockDelegate.protectionState!.isProtected)
            XCTAssertFalse(mockDelegate.didSendReport)
            XCTAssertTrue(mockDelegate.didRequestCloseCalled)
        }
    }

    @MainActor
    func testUserScriptDidEnableProtectionStateShouldNotSegueToToggleReportScreen() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        let protectionState = ProtectionState(isProtected: true, eventOrigin: .init(screen: .primaryScreen))
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didChangeProtectionState: protectionState)
        XCTAssertTrue(mockDelegate.didChangeProtectionSwitchCalled)
        XCTAssertTrue(mockDelegate.protectionState!.isProtected)
        XCTAssertFalse(mockDelegate.didSendReport)
        XCTAssertTrue(mockDelegate.didRequestCloseCalled)
    }

    @MainActor
    func testUserScriptDidDisableProtectionStateShouldSegueToToggleReportScreen() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        let protectionState = ProtectionState(isProtected: false, eventOrigin: .init(screen: .primaryScreen))
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didChangeProtectionState: protectionState)
        XCTAssertFalse(mockDelegate.didChangeProtectionSwitchCalled)
        XCTAssertFalse(mockDelegate.didRequestCloseCalled)
        let currentURL = privacyDashboardController.webView!.url
        XCTAssertEqual(currentURL?.getParameter(named: "screen"), "toggleReport")
        XCTAssertEqual(currentURL?.getParameter(named: "opener"), "dashboard")
    }

    // MARK: - userScriptDidRequestClose


    /*
     func userScriptDidRequestClose(_ userScript: PrivacyDashboardUserScript) {
     
     // called when protection is toggled off from app menu
     if case .toggleReport(completionHandler: let completionHandler) = entryPoint {
         completionHandler(didSendReport)
     // called when protection is toggled off from privacy dashboard
     } else if let protectionStateToSubmitOnToggleReportDismiss {
         privacyDashboardDelegate?.privacyDashboardController(self,
                                                              didChangeProtectionSwitch: protectionStateToSubmitOnToggleReportDismiss,
                                                              didSendReport: didSendReport)
         // privacyDashboardNavigationDelegate?.privacyDashboardControllerDidRequestClose(self) potentially missing for mac!
         // if needed move it outside of this func anyway!
     }

     if isInToggleReportingFlow {
         toggleReportsManager.recordDismissal()
     }

 #if os(iOS)
         privacyDashboardNavigationDelegate?.privacyDashboardControllerDidRequestClose(self)
 #endif
     
     }
     */

//    @MainActor
//    func testUserScriptDidRequestCloseShould() {
//        makePrivacyDashboardController(entryPoint: .dashboard)
//        let protectionState = ProtectionState(isProtected: false, eventOrigin: .init(screen: .primaryScreen))
//        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didChangeProtectionState: protectionState)
//        XCTAssertFalse(mockDelegate.didChangeProtectionSwitchCalled)
//        XCTAssertFalse(mockDelegate.didRequestCloseCalled)
//        let currentURL = privacyDashboardController.webView!.url
//        XCTAssertEqual(currentURL?.getParameter(named: "screen"), "toggleReport")
//        XCTAssertEqual(currentURL?.getParameter(named: "opener"), "dashboard")
//    }


}
