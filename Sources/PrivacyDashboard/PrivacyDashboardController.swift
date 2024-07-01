//
//  PrivacyDashboardController.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import WebKit
import Combine
import PrivacyDashboardResources
import BrowserServicesKit
import Common

public enum PrivacyDashboardOpenSettingsTarget: String {

    case general
    case cookiePopupManagement = "cpm"

}

public protocol PrivacyDashboardControllerDelegate: AnyObject {

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didChangeProtectionSwitch protectionState: ProtectionState,
                                    didSendReport: Bool)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestOpenUrlInNewTab url: URL)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestOpenSettings target: PrivacyDashboardOpenSettingsTarget)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didSelectBreakageCategory category: String)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitBrokenSiteReportWithCategory category: String,
                                    description: String)
    func privacyDashboardControllerDidRequestShowAlertForMissingDescription(_ privacyDashboardController: PrivacyDashboardController)
    func privacyDashboardControllerDidRequestShowGeneralFeedback(_ privacyDashboardController: PrivacyDashboardController)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitToggleReportWithSource source: BrokenSiteReport.Source)
    func privacyDashboardControllerDidRequestClose(_ privacyDashboardController: PrivacyDashboardController)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, didSetHeight height: Int)

#if os(macOS)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didSetPermission permissionName: String, 
                                    to state: PermissionAuthorizationState)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    setPermission permissionName: String, 
                                    paused: Bool)
#endif

}

@MainActor public final class PrivacyDashboardController: NSObject {

    public weak var privacyDashboardDelegate: PrivacyDashboardControllerDelegate?

    @Published public var theme: PrivacyDashboardTheme?
    @Published public var allowedPermissions: [AllowedPermission] = []
    public var preferredLocale: String?

    public private(set) weak var privacyInfo: PrivacyInfo?
    private let entryPoint: PrivacyDashboardEntryPoint
    private let variant: PrivacyDashboardVariant
    private let eventMapping: EventMapping<PrivacyDashboardEvents>

    private weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()

    private var protectionStateToSubmitOnToggleReportDismiss: ProtectionState?

    private let privacyDashboardScript: PrivacyDashboardUserScript
    private var toggleReportsManager: ToggleReportsManager

    public init(privacyInfo: PrivacyInfo?,
                entryPoint: PrivacyDashboardEntryPoint,
                variant: PrivacyDashboardVariant,
                privacyConfigurationManager: PrivacyConfigurationManaging,
                eventMapping: EventMapping<PrivacyDashboardEvents>) {
        self.privacyInfo = privacyInfo
        self.entryPoint = entryPoint
        self.variant = variant
        self.eventMapping = eventMapping
        privacyDashboardScript = PrivacyDashboardUserScript(privacyConfigurationManager: privacyConfigurationManager)
        toggleReportsManager = ToggleReportsManager(feature: ToggleReportsFeature(manager: privacyConfigurationManager))
    }

    public func setup(for webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self

        setupPrivacyDashboardUserScript()
        loadStartScreen()
    }

    private func loadStartScreen() {
        let url = PrivacyDashboardURLBuilder(configuration: .startScreen(entryPoint: entryPoint, variant: variant)).build()
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    public func updatePrivacyInfo(_ privacyInfo: PrivacyInfo?) {
        cancellables.removeAll()
        self.privacyInfo = privacyInfo

        subscribeToDataModelChanges()
        sendProtectionStatus()
    }

    public func cleanup() {
        cancellables.removeAll()
        privacyDashboardScript.messageNames.forEach { messageName in
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        }
    }

    public func didStartRulesCompilation() {
        guard let webView else { return }
        privacyDashboardScript.setIsPendingUpdates(true, webView: webView)
    }

    public func didFinishRulesCompilation() {
        guard let webView else { return }
        privacyDashboardScript.setIsPendingUpdates(false, webView: webView)
    }

    private func setupPrivacyDashboardUserScript() {
        guard let webView else { return }
        privacyDashboardScript.delegate = self
        webView.configuration.userContentController.addUserScript(privacyDashboardScript.makeWKUserScriptSync())
        privacyDashboardScript.messageNames.forEach { messageName in
            webView.configuration.userContentController.add(privacyDashboardScript, name: messageName)
        }
    }

}

// MARK: - WKNavigationDelegate

extension PrivacyDashboardController: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        subscribeToDataModelChanges()

        sendProtectionStatus()
        sendParentEntity()
        sendCurrentLocale()
    }

    private func subscribeToDataModelChanges() {
        cancellables.removeAll()

        subscribeToTheme()
        subscribeToTrackerInfo()
        subscribeToConnectionUpgradedTo()
        subscribeToServerTrust()
        subscribeToConsentManaged()
        subscribeToAllowedPermissions()
    }

    private func subscribeToTheme() {
        $theme
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] themeName in
                guard let self, let webView else { return }
                privacyDashboardScript.setTheme(themeName, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToTrackerInfo() {
        privacyInfo?.$trackerInfo
            .receive(on: DispatchQueue.main)
            .throttle(for: 0.25, scheduler: RunLoop.main, latest: true)
            .sink(receiveValue: { [weak self] trackerInfo in
                guard let self, let url = privacyInfo?.url, let webView else { return }
                privacyDashboardScript.setTrackerInfo(url, trackerInfo: trackerInfo, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToConnectionUpgradedTo() {
        privacyInfo?.$connectionUpgradedTo
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] connectionUpgradedTo in
                guard let self, let webView else { return }
                let upgradedHttps = connectionUpgradedTo != nil
                privacyDashboardScript.setUpgradedHttps(upgradedHttps, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToServerTrust() {
        privacyInfo?.$serverTrust
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .map { serverTrust in
                ServerTrustViewModel(serverTrust: serverTrust)
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] serverTrustViewModel in
                guard let self, let serverTrustViewModel, let webView else { return }
                privacyDashboardScript.setServerTrust(serverTrustViewModel, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToConsentManaged() {
        privacyInfo?.$cookieConsentManaged
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] consentManaged in
                guard let self, let webView else { return }
                privacyDashboardScript.setConsentManaged(consentManaged, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToAllowedPermissions() {
        $allowedPermissions
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] allowedPermissions in
                guard let self, let webView else { return }
                privacyDashboardScript.setPermissions(allowedPermissions: allowedPermissions, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func sendProtectionStatus() {
        guard let webView, let protectionStatus = privacyInfo?.protectionStatus else { return }
        privacyDashboardScript.setProtectionStatus(protectionStatus, webView: webView)
    }

    private func sendParentEntity() {
        guard let webView else { return }
        privacyDashboardScript.setParentEntity(privacyInfo?.parentEntity, webView: webView)
    }

    private func sendCurrentLocale() {
        guard let webView else { return }
        let locale = preferredLocale ?? "en"
        privacyDashboardScript.setLocale(locale, webView: webView)
    }
}

// MARK: - PrivacyDashboardUserScriptDelegate

extension PrivacyDashboardController: PrivacyDashboardUserScriptDelegate {

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestOpenSettings target: String) {
        let settingsTarget = PrivacyDashboardOpenSettingsTarget(rawValue: target) ?? .general
        privacyDashboardDelegate?.privacyDashboardController(self, didRequestOpenSettings: settingsTarget)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didChangeProtectionState protectionState: ProtectionState) {
        if protectionState.eventOrigin.screen == .choiceToggle {
            eventMapping.fire(.toggleProtectionOff)
        }
        if shouldSegueToToggleReportScreen(with: protectionState) {
            segueToToggleReportScreen(with: protectionState)
        } else {
            privacyDashboardDelegate?.privacyDashboardController(self, didChangeProtectionSwitch: protectionState, didSendReport: false)
            privacyDashboardDelegate?.privacyDashboardControllerDidRequestClose(self)
        }
    }

    private func shouldSegueToToggleReportScreen(with protectionState: ProtectionState) -> Bool {
        !protectionState.isProtected && protectionState.eventOrigin.screen == .primaryScreen && toggleReportsManager.shouldShowToggleReport
    }

    private func segueToToggleReportScreen(with protectionStateToSubmit: ProtectionState) {
        let url = PrivacyDashboardURLBuilder(configuration: .segueToScreen(.toggleReport, entryPoint: entryPoint)).build()
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent().deletingLastPathComponent())
        protectionStateToSubmitOnToggleReportDismiss = protectionStateToSubmit
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestOpenUrlInNewTab url: URL) {
        privacyDashboardDelegate?.privacyDashboardController(self, didRequestOpenUrlInNewTab: url)
    }

    func userScriptDidRequestClose(_ userScript: PrivacyDashboardUserScript) {
        processToggleReportIfNeeded(didSendReport: false)
        recordToggleDismissalIfNeeded()
#if os(iOS)
        privacyDashboardNavigationDelegate?.privacyDashboardControllerDidRequestClose(self)
#endif
    }

    private func processToggleReportIfNeeded(didSendReport: Bool) {
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
    }

    private var isInToggleReportingFlow: Bool {
        if case .toggleReport = entryPoint {
            return true
        } else if protectionStateToSubmitOnToggleReportDismiss != nil {
            return true
        }
        return false
    }

    private func recordToggleDismissalIfNeeded() {
        if isInToggleReportingFlow {
            toggleReportsManager.recordDismissal()
        }
    }

    public func handleViewWillDisappear() {
        processToggleReportIfNeeded(didSendReport: false)
        recordToggleDismissalIfNeeded()
    }

    func userScriptDidRequestShowReportBrokenSite(_ userScript: PrivacyDashboardUserScript) {
        eventMapping.fire(.reportBrokenSiteShown, parameters: [
            PrivacyDashboardEvents.Parameters.variant: variant.rawValue,
            PrivacyDashboardEvents.Parameters.source: source.rawValue
        ])
        eventMapping.fire(.showReportBrokenSite)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, setHeight height: Int) {
        privacyDashboardDelegate?.privacyDashboardController(self, didSetHeight: height)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestSubmitBrokenSiteReportWithCategory category: String, description: String) {
        var parameters = [PrivacyDashboardEvents.Parameters.variant: variant.rawValue]
        if case let .afterTogglePrompt(_, didToggleProtectionsFixIssue) = entryPoint {
            parameters[PrivacyDashboardEvents.Parameters.didToggleProtectionsFixIssue] = didToggleProtectionsFixIssue.description
        }
        eventMapping.fire(.reportBrokenSiteSent, parameters: parameters)
        privacyDashboardDelegate?.privacyDashboardController(self, didRequestSubmitBrokenSiteReportWithCategory: category, description: description)
    }

#if os(macOS)
    func userScript(_ userScript: PrivacyDashboardUserScript, didSetPermission permission: String, to state: PermissionAuthorizationState) {
        privacyDashboardDelegate?.privacyDashboardController(self, didSetPermission: permission, to: state)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, setPermission permission: String, paused: Bool) {
        privacyDashboardDelegate?.privacyDashboardController(self, setPermission: permission, paused: paused)
    }
#endif

    // Toggle reports

    func userScriptDidRequestToggleReportOptions(_ userScript: PrivacyDashboardUserScript) {
        guard let webView else { return }
        let site = privacyInfo?.url.trimmingQueryItemsAndFragment().absoluteString ?? ""
        privacyDashboardScript.setToggleReportOptions(forSite: site, webView: webView)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didSelectReportAction shouldSendReport: Bool) {
        if shouldSendReport {
            privacyDashboardDelegate?.privacyDashboardController(self, didRequestSubmitToggleReportWithSource: source)
            toggleReportsManager.recordPrompt()
            // macOS implementation differs here: After the user taps 'Send Report',
            // no immediate action should be triggered due to the subsequent 'Thank you' screen.
            // Processing of the toggle report should only proceed once the user dismisses the 'Thank you' screen.
#if os(iOS)
            processToggleReportIfNeeded(didSendReport: shouldSendReport)
#endif
        } else {
            toggleReportsManager.recordDismissal()
            processToggleReportIfNeeded(didSendReport: shouldSendReport)
        }
    }

    public var source: BrokenSiteReport.Source {
        var source: BrokenSiteReport.Source
        switch entryPoint {
        case .report: source = .appMenu
        case .dashboard: source = .dashboard
        case .toggleReport: source = .onProtectionsOffMenu
        case .prompt(let event): source = .prompt(event)
        case .afterTogglePrompt: source = .afterTogglePrompt
        }
        if protectionStateToSubmitOnToggleReportDismiss != nil {
            source = .onProtectionsOffDashboard
        }
        return source
    }

    // MARK: - Experiment flows (soon to be removed)

    func userScript(_ userScript: PrivacyDashboardUserScript, didSelectOverallCategory category: String) {
        eventMapping.fire(.overallCategorySelected, parameters: [PrivacyDashboardEvents.Parameters.category: category])
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didSelectBreakageCategory category: String) {
        eventMapping.fire(.breakageCategorySelected, parameters: [
            PrivacyDashboardEvents.Parameters.variant: variant.rawValue,
            PrivacyDashboardEvents.Parameters.category: category
        ])
        privacyDashboardDelegate?.privacyDashboardController(self, didSelectBreakageCategory: category)
    }

    func userScriptDidRequestShowAlertForMissingDescription(_ userScript: PrivacyDashboardUserScript) {
        privacyDashboardDelegate?.privacyDashboardControllerDidRequestShowAlertForMissingDescription(self)
    }

    func userScriptDidRequestShowNativeFeedback(_ userScript: PrivacyDashboardUserScript) {
        privacyDashboardDelegate?.privacyDashboardControllerDidRequestShowGeneralFeedback(self)
    }

    func userScriptDidSkipTogglingStep(_ userScript: PrivacyDashboardUserScript) {
        eventMapping.fire(.skipToggleStep)
    }

}
