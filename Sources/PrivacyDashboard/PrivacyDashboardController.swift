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

public enum PrivacyDashboardOpenSettingsTarget: String {
    case general
    case cookiePopupManagement = "cpm"
}

/// Navigation delegate for the pages provided by the PrivacyDashboardController
public protocol PrivacyDashboardNavigationDelegate: AnyObject {

    func privacyDashboardControllerDidTapClose(_ privacyDashboardController: PrivacyDashboardController)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, didSetHeight height: Int)

}

/// `Report broken site` web page delegate
public protocol PrivacyDashboardReportBrokenSiteDelegate: AnyObject {

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitBrokenSiteReportWithCategory category: String, description: String)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    reportBrokenSiteDidChangeProtectionSwitch protectionState: ProtectionState)

}

/// `Privacy Dashboard` web page delegate
public protocol PrivacyDashboardControllerDelegate: AnyObject {

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didChangeProtectionSwitch protectionState: ProtectionState)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestOpenUrlInNewTab url: URL)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestOpenSettings target: PrivacyDashboardOpenSettingsTarget)
    func privacyDashboardControllerDidRequestShowReportBrokenSite(_ privacyDashboardController: PrivacyDashboardController)

#if os(macOS)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didSetPermission permissionName: String, to state: PermissionAuthorizationState)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    setPermission permissionName: String, paused: Bool)
#endif

}

@MainActor public final class PrivacyDashboardController: NSObject {

    public weak var privacyDashboardDelegate: PrivacyDashboardControllerDelegate?
    public weak var privacyDashboardNavigationDelegate: PrivacyDashboardNavigationDelegate?
    public weak var privacyDashboardReportBrokenSiteDelegate: PrivacyDashboardReportBrokenSiteDelegate?

    @Published public var theme: PrivacyDashboardTheme?
    public var preferredLocale: String?
    @Published public var allowedPermissions: [AllowedPermission] = []
    public private(set) weak var privacyInfo: PrivacyInfo?
    public let dashboardMode: PrivacyDashboardMode

    private weak var webView: WKWebView?
    private let privacyDashboardScript: PrivacyDashboardUserScript
    private var cancellables = Set<AnyCancellable>()
    private var protectionStateToSubmit: ProtectionState?

    public init(privacyInfo: PrivacyInfo?, dashboardMode: PrivacyDashboardMode, privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyInfo = privacyInfo
        self.dashboardMode = dashboardMode
        privacyDashboardScript = PrivacyDashboardUserScript(privacyConfigurationManager: privacyConfigurationManager)
    }

    public func setup(for webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self

        setupPrivacyDashboardUserScript()
        loadPrivacyDashboardHTML(screen: dashboardMode.screen)
    }

    public func updatePrivacyInfo(_ privacyInfo: PrivacyInfo?) {
        cancellables.removeAll()
        self.privacyInfo = privacyInfo

        subscribeToDataModelChanges()
        sendProtectionStatus()
    }

    public func cleanUp() {
        cancellables.removeAll()

        privacyDashboardScript.messageNames.forEach { messageName in
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        }
    }

    public func didStartRulesCompilation() {
        guard let webView = self.webView else { return }
        privacyDashboardScript.setIsPendingUpdates(true, webView: webView)
    }

    public func didFinishRulesCompilation() {
        guard let webView = self.webView else { return }
        privacyDashboardScript.setIsPendingUpdates(false, webView: webView)
    }

    private func setupPrivacyDashboardUserScript() {
        guard let webView = self.webView else { return }

        privacyDashboardScript.delegate = self

        webView.configuration.userContentController.addUserScript(privacyDashboardScript.makeWKUserScriptSync())

        privacyDashboardScript.messageNames.forEach { messageName in
            webView.configuration.userContentController.add(privacyDashboardScript, name: messageName)
        }
    }

    private func loadPrivacyDashboardHTML(screen: Screen) {
        guard var url = Bundle.privacyDashboardURL else { return }
        url = url.appendingParameter(name: "screen", value: screen.rawValue)
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent().deletingLastPathComponent())
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
                guard let self = self, let webView = self.webView else { return }
                self.privacyDashboardScript.setTheme(themeName, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToTrackerInfo() {
        privacyInfo?.$trackerInfo
            .receive(on: DispatchQueue.main)
            .throttle(for: 0.25, scheduler: RunLoop.main, latest: true)
            .sink(receiveValue: { [weak self] trackerInfo in
                guard let self = self, let url = self.privacyInfo?.url, let webView = self.webView else { return }
                self.privacyDashboardScript.setTrackerInfo(url, trackerInfo: trackerInfo, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToConnectionUpgradedTo() {
        privacyInfo?.$connectionUpgradedTo
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] connectionUpgradedTo in
                guard let self = self, let webView = self.webView else { return }
                let upgradedHttps = connectionUpgradedTo != nil
                self.privacyDashboardScript.setUpgradedHttps(upgradedHttps, webView: webView)
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
                guard let self = self, let serverTrustViewModel = serverTrustViewModel, let webView = self.webView else { return }
                self.privacyDashboardScript.setServerTrust(serverTrustViewModel, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToConsentManaged() {
        privacyInfo?.$cookieConsentManaged
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] consentManaged in
                guard let self = self, let webView = self.webView else { return }
                self.privacyDashboardScript.setConsentManaged(consentManaged, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToAllowedPermissions() {
        $allowedPermissions
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] allowedPermissions in
                guard let self = self, let webView = self.webView else { return }
                self.privacyDashboardScript.setPermissions(allowedPermissions: allowedPermissions, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func sendProtectionStatus() {
        guard let webView = self.webView,
              let protectionStatus = privacyInfo?.protectionStatus
        else { return }

        privacyDashboardScript.setProtectionStatus(protectionStatus, webView: webView)
    }

    private func sendParentEntity() {
        guard let webView = self.webView else { return }
        privacyDashboardScript.setParentEntity(privacyInfo?.parentEntity, webView: webView)
    }

    private func sendCurrentLocale() {
        guard let webView = self.webView else { return }

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
        if !protectionState.isProtected {
            loadSimpleBreakageReportScreen(with: protectionState)
        } else {
            didChangeProtectionState(protectionState)
        }
    }

    private func didChangeProtectionState(_ protectionState: ProtectionState) {
        switch protectionState.eventOrigin.screen {
        case .primaryScreen:
            privacyDashboardDelegate?.privacyDashboardController(self, didChangeProtectionSwitch: protectionState)
        case .breakageForm:
            privacyDashboardReportBrokenSiteDelegate?.privacyDashboardController(self, reportBrokenSiteDidChangeProtectionSwitch: protectionState)
        case .simpleBreakageReport:
            assertionFailure("Simple Breakage report screen doesn't have toggling capability")
        }
    }

    private func loadSimpleBreakageReportScreen(with protectionStateToSubmit: ProtectionState) {
        guard var url = Bundle.privacyDashboardURL else { return }
        url = url.appendingParameters(["screen": Screen.simpleBreakageReport.rawValue,
                                       "opener": "dashboard"])

        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent().deletingLastPathComponent())
        self.protectionStateToSubmit = protectionStateToSubmit
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestOpenUrlInNewTab url: URL) {
        privacyDashboardDelegate?.privacyDashboardController(self, didRequestOpenUrlInNewTab: url)
    }

    func userScriptDidRequestClosing(_ userScript: PrivacyDashboardUserScript) {
        handleUserScriptClosing()
    }

    private func handleUserScriptClosing() {
        performToggleReportActionIfNeeded()
        submitProtectionStateChangeIfNeeded()
        closeDashboard()
    }

    private func performToggleReportActionIfNeeded() {
        if case .toggleReport(onAnyAction: let action) = dashboardMode {
            action()
        }
    }

    private func submitProtectionStateChangeIfNeeded() {
        if let protectionStateToSubmit {
            didChangeProtectionState(protectionStateToSubmit)
        }
    }

    private func closeDashboard() {
        privacyDashboardNavigationDelegate?.privacyDashboardControllerDidTapClose(self)
    }

    func userScriptDidRequestShowReportBrokenSite(_ userScript: PrivacyDashboardUserScript) {
        privacyDashboardDelegate?.privacyDashboardControllerDidRequestShowReportBrokenSite(self)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, setHeight height: Int) {
        privacyDashboardNavigationDelegate?.privacyDashboardController(self, didSetHeight: height)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestSubmitBrokenSiteReportWithCategory category: String, description: String) {
        privacyDashboardReportBrokenSiteDelegate?.privacyDashboardController(self, didRequestSubmitBrokenSiteReportWithCategory: category,
                                                                             description: description)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didSetPermission permission: String, to state: PermissionAuthorizationState) {
#if os(macOS)
        privacyDashboardDelegate?.privacyDashboardController(self, didSetPermission: permission, to: state)
#endif
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, setPermission permission: String, paused: Bool) {
#if os(macOS)
        privacyDashboardDelegate?.privacyDashboardController(self, setPermission: permission, paused: paused)
#endif
    }

    // Toggle reports

    func userScriptDidRequestToggleReportOptions(_ userScript: PrivacyDashboardUserScript) {
        guard let webView = self.webView else { return }
        let site = privacyInfo?.url.trimmingQueryItemsAndFragment().absoluteString ?? ""
        privacyDashboardScript.setToggleReportOptions(forSite: site, webView: webView)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didSelectReportAction shouldSendReport: Bool) {
        handleUserScriptClosing()
    }

}
