//
//  PrivacyDashboardControllerTests.swift
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
import Common
import WebKit
@testable import PrivacyDashboard
@testable import BrowserServicesKit

@MainActor
final class PrivacyDashboardControllerTests: XCTestCase {

    var privacyDashboardController: PrivacyDashboardController!
    var delegateMock: PrivacyDashboardDelegateMock!
    var toggleReportingManagerMock: ToggleReportingManagerMock!
    var webView: WKWebView!

    private func makePrivacyDashboardController(entryPoint: PrivacyDashboardEntryPoint) {
        delegateMock = PrivacyDashboardDelegateMock()
        toggleReportingManagerMock = ToggleReportingManagerMock()
        privacyDashboardController = PrivacyDashboardController(privacyInfo: nil,
                                                                entryPoint: entryPoint,
                                                                variant: .control,
                                                                toggleReportingManager: toggleReportingManagerMock,
                                                                eventMapping: EventMapping<PrivacyDashboardEvents> { _, _, _, _ in })
        webView = WKWebView()
        privacyDashboardController.setup(for: webView)
        privacyDashboardController.delegate = delegateMock
    }

    // MARK: - Setup

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
            if case .afterTogglePrompt = entryPoint {
                XCTAssertEqual(currentURL?.getParameter(named: "category"), "apple")
            }
            if case .toggleReport = entryPoint {
                XCTAssertEqual(currentURL?.getParameter(named: "opener"), "menu")
            }
        }
    }

    // MARK: - didChangeProtectionState

    func testUserScriptDidDisableProtectionStateNotFromPrimaryScreenShouldNotSegueToToggleReportScreen() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        let allScreensButPrimaryScreen = Screen.allCases.filter { $0 != .primaryScreen }
        for screen in allScreensButPrimaryScreen {
            let protectionState = ProtectionState(isProtected: false, eventOrigin: .init(screen: screen))
            privacyDashboardController.userScript(PrivacyDashboardUserScript(), didChangeProtectionState: protectionState)
            XCTAssertTrue(delegateMock.didChangeProtectionSwitchCalled)
            XCTAssertFalse(delegateMock.protectionState!.isProtected)
            XCTAssertFalse(delegateMock.didSendReport)
            XCTAssertTrue(delegateMock.didRequestCloseCalled)
        }
    }

    func testUserScriptDidEnableProtectionStateShouldNotSegueToToggleReportScreen() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        simulateProtectionToggleSwitch(true)
        XCTAssertTrue(delegateMock.didChangeProtectionSwitchCalled)
        XCTAssertTrue(delegateMock.protectionState!.isProtected)
        XCTAssertFalse(delegateMock.didSendReport)
        XCTAssertTrue(delegateMock.didRequestCloseCalled)
    }

    private func simulateProtectionToggleSwitch(_ isProtected: Bool) {
        let protectionState = ProtectionState(isProtected: isProtected, eventOrigin: .init(screen: .primaryScreen))
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didChangeProtectionState: protectionState)
    }

    func testUserScriptDidDisableProtectionStateShouldSegueToToggleReportScreen() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        simulateProtectionToggleSwitch(false)
        XCTAssertFalse(delegateMock.didChangeProtectionSwitchCalled)
        XCTAssertFalse(delegateMock.didRequestCloseCalled)
        let currentURL = privacyDashboardController.webView!.url
        XCTAssertEqual(currentURL?.getParameter(named: "screen"), "toggleReport")
        XCTAssertEqual(currentURL?.getParameter(named: "opener"), "dashboard")
    }

    // MARK: - userScriptDidRequestClose

    func testUserScriptDidRequestCloseShouldCallDidRequestClose() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        privacyDashboardController.userScriptDidRequestClose(PrivacyDashboardUserScript())
        XCTAssertTrue(delegateMock.didRequestCloseCalled)
    }

    func testUserScriptDidRequestCloseIfEntryPointIsToggleReportShouldCallCompletionHandler() {
        func completionHandler(didSendReport: Bool) {
            XCTAssertFalse(didSendReport)
        }
        makePrivacyDashboardController(entryPoint: .toggleReport(completionHandler: completionHandler(didSendReport:)))
        privacyDashboardController.userScriptDidRequestClose(PrivacyDashboardUserScript())
    }

    func testUserScriptDidRequestCloseIfThereIsProtectionStateToSubmitShouldCallDidChangeProtectionSwitch() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        simulateProtectionToggleSwitch(false)
        XCTAssertFalse(delegateMock.didChangeProtectionSwitchCalled)
        privacyDashboardController.userScriptDidRequestClose(PrivacyDashboardUserScript())
        XCTAssertTrue(delegateMock.didChangeProtectionSwitchCalled)
        XCTAssertFalse(delegateMock.didSendReport)
        XCTAssertTrue(delegateMock.didRequestCloseCalled)
    }

    func testUserScriptDidRequestCloseIfNotInToggleReportFlowShouldNotRecordToggleDismissal() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        privacyDashboardController.userScriptDidRequestClose(PrivacyDashboardUserScript())
        XCTAssertFalse(toggleReportingManagerMock.recordDismissalCalled)
        XCTAssertFalse(toggleReportingManagerMock.recordPromptCalled)
    }

    func testUserScriptDidRequestCloseIfEntryPointIsToggleReportShouldRecordToggleDismissal() {
        makePrivacyDashboardController(entryPoint: .toggleReport(completionHandler: { _ in }))
        privacyDashboardController.userScriptDidRequestClose(PrivacyDashboardUserScript())
        XCTAssertTrue(toggleReportingManagerMock.recordDismissalCalled)
        XCTAssertFalse(toggleReportingManagerMock.recordPromptCalled)
    }

    func testUserScriptDidRequestCloseIfInToggleReportFlowShouldRecordToggleDismissal() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        simulateProtectionToggleSwitch(false)
        privacyDashboardController.userScriptDidRequestClose(PrivacyDashboardUserScript())
        XCTAssertTrue(toggleReportingManagerMock.recordDismissalCalled)
        XCTAssertFalse(toggleReportingManagerMock.recordPromptCalled)
    }

    // MARK: - userScriptDidSelectReportAction

    // MARK: (do not send)

    func testUserScriptDidSelectReportActionDoNotSendShouldRecordDismissal() {
        makePrivacyDashboardController(entryPoint: .toggleReport(completionHandler: { _ in }))
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didSelectReportAction: false)
        XCTAssertTrue(toggleReportingManagerMock.recordDismissalCalled)
        XCTAssertFalse(toggleReportingManagerMock.recordPromptCalled)
    }

    func testUserScriptDidSelectReportActionDoNotSendIfEntryPointIsToggleReportShouldCallCompletionHandler() {
        func completionHandler(didSendReport: Bool) {
            XCTAssertFalse(didSendReport)
        }
        makePrivacyDashboardController(entryPoint: .toggleReport(completionHandler: completionHandler(didSendReport:)))
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didSelectReportAction: false)
        XCTAssertTrue(delegateMock.didRequestCloseCalled)
    }

    func testUserScriptDidSelectReportActionDoNotSendIfThereIsProtectionStateToSubmitShouldCallDidChangeProtectionSwitch() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        simulateProtectionToggleSwitch(false)
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didSelectReportAction: false)
        XCTAssertTrue(delegateMock.didChangeProtectionSwitchCalled)
        XCTAssertFalse(delegateMock.didSendReport)
        XCTAssertTrue(delegateMock.didRequestCloseCalled)
    }

    // MARK: (send)

    func testUserScriptDidSelectReportActionSendShouldRecordPrompt() {
        makePrivacyDashboardController(entryPoint: .toggleReport(completionHandler: { _ in }))
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didSelectReportAction: true)
        XCTAssertTrue(toggleReportingManagerMock.recordPromptCalled)
        XCTAssertFalse(toggleReportingManagerMock.recordDismissalCalled)
    }

    func testUserScriptDidSelectReportActionSendShouldCallDidRequestSubmitToggleReport() {
        makePrivacyDashboardController(entryPoint: .toggleReport(completionHandler: { _ in }))
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didSelectReportAction: true)
        XCTAssertTrue(delegateMock.didRequestSubmitToggleReport)
    }

    func testUserScriptDidSelectReportActionSendIfEntryPointIsToggleReportShouldCallCompletionHandler() {
        func completionHandler(didSendReport: Bool) {
            XCTAssertTrue(didSendReport)
        }
        makePrivacyDashboardController(entryPoint: .toggleReport(completionHandler: completionHandler(didSendReport:)))
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didSelectReportAction: true)
    }

    func testUserScriptDidSelectReportActionSendIfThereIsProtectionStateToSubmitShouldCallDidChangeProtectionSwitchOnIOSApp() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        simulateProtectionToggleSwitch(false)
        privacyDashboardController.toggleReportingFlow?.shouldHandlePendingProtectionStateChangeOnReportSent = true // simulate iOS app
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didSelectReportAction: true)
        XCTAssertTrue(delegateMock.didChangeProtectionSwitchCalled)
        XCTAssertTrue(delegateMock.didSendReport)
        XCTAssertTrue(delegateMock.didRequestCloseCalled)
    }

    func testUserScriptDidSelectReportActionSendIfThereIsProtectionStateToSubmitShouldNotCallDidChangeProtectionSwitchOnMacOSApp() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        simulateProtectionToggleSwitch(false)
        privacyDashboardController.toggleReportingFlow?.shouldHandlePendingProtectionStateChangeOnReportSent = false // simulate macOS app
        privacyDashboardController.userScript(PrivacyDashboardUserScript(), didSelectReportAction: true)
        XCTAssertFalse(delegateMock.didChangeProtectionSwitchCalled)
        XCTAssertFalse(delegateMock.didRequestCloseCalled)
    }

    // MARK: - handleViewWillDisappear

    func testHandleViewWillDisappearIfEntryPointIsToggleReportShouldRecordToggleDismissal() {
        makePrivacyDashboardController(entryPoint: .toggleReport(completionHandler: { _ in }))
        privacyDashboardController.handleViewWillDisappear()
        XCTAssertFalse(toggleReportingManagerMock.recordPromptCalled)
        XCTAssertTrue(toggleReportingManagerMock.recordDismissalCalled)
    }

    func testHandleViewWillDisappearIfInToggleReportFlowShouldRecordToggleDismissal() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        simulateProtectionToggleSwitch(false)
        privacyDashboardController.handleViewWillDisappear()
        XCTAssertFalse(toggleReportingManagerMock.recordPromptCalled)
        XCTAssertTrue(toggleReportingManagerMock.recordDismissalCalled)
    }

    func testHandleViewWillDisappearIfEntryPointIsToggleReportShouldCallCompletionHandler() {
        func completionHandler(didSendReport: Bool) {
            XCTAssertFalse(didSendReport)
        }
        makePrivacyDashboardController(entryPoint: .toggleReport(completionHandler: completionHandler(didSendReport:)))
        privacyDashboardController.handleViewWillDisappear()
    }

    func testHandleViewWillDisappearIfInToggleReportFlowShouldCallDidChangeProtectionSwitch() {
        makePrivacyDashboardController(entryPoint: .dashboard)
        simulateProtectionToggleSwitch(false)
        privacyDashboardController.handleViewWillDisappear()
        XCTAssertTrue(delegateMock.didChangeProtectionSwitchCalled)
        XCTAssertFalse(delegateMock.didRequestCloseCalled)
    }

}
