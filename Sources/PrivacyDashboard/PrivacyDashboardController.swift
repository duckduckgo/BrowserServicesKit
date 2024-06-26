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

extension UserDefaults {

    var toggleReportCounter: Int {
        get {
            integer(forKey: PrivacyDashboardController.Constant.toggleReportsCounter)
        }
        set {
            set(newValue, forKey: PrivacyDashboardController.Constant.toggleReportsCounter)
        }
    }

}

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
                                    didRequestSubmitBrokenSiteReportWithCategory category: String,
                                    description: String)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    reportBrokenSiteDidChangeProtectionSwitch protectionState: ProtectionState)
    func privacyDashboardControllerDidRequestShowAlertForMissingDescription(_ privacyDashboardController: PrivacyDashboardController)
    func privacyDashboardControllerDidRequestShowGeneralFeedback(_ privacyDashboardController: PrivacyDashboardController)

}

public protocol PrivacyDashboardToggleReportDelegate: AnyObject {

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitToggleReportWithSource source: BrokenSiteReport.Source,
                                    didOpenReportInfo: Bool,
                                    toggleReportCounter: Int?)

}

/// `Privacy Dashboard` web page delegate
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

#if os(macOS)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didSetPermission permissionName: String, to state: PermissionAuthorizationState)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    setPermission permissionName: String, paused: Bool)
#endif

}

@MainActor public final class PrivacyDashboardController: NSObject {

    fileprivate enum Constant {

        static let screenKey = "screen"
        static let breakageScreenKey = "breakageScreen"
        static let openerKey = "opener"
        static let categoryKey = "category"

        static let menuScreenKey = "menu"
        static let dashboardScreenKey = "dashboard"

        static let toggleReportsCounter = "com.duckduckgo.toggle-reports-counter"

    }

    private enum ToggleReportDismissType {

        case send
        case doNotSend
        case dismiss

        var event: PrivacyDashboardEvents? {
            switch self {
            case .send: return nil
            case .doNotSend: return .toggleReportDoNotSend
            case .dismiss: return .toggleReportDismiss
            }
        }

    }

    private enum ToggleReportDismissSource {

        case userScript
        case viewWillDisappear

    }

    public weak var privacyDashboardDelegate: PrivacyDashboardControllerDelegate?
    public weak var privacyDashboardNavigationDelegate: PrivacyDashboardNavigationDelegate?
    public weak var privacyDashboardReportBrokenSiteDelegate: PrivacyDashboardReportBrokenSiteDelegate?
    public weak var privacyDashboardToggleReportDelegate: PrivacyDashboardToggleReportDelegate?

    @Published public var theme: PrivacyDashboardTheme?
    public var preferredLocale: String?
    @Published public var allowedPermissions: [AllowedPermission] = []
    public private(set) weak var privacyInfo: PrivacyInfo?
    public let initDashboardMode: PrivacyDashboardMode

    private weak var webView: WKWebView?
    private let privacyDashboardScript: PrivacyDashboardUserScript
    private var cancellables = Set<AnyCancellable>()
    private var protectionStateToSubmitOnToggleReportDismiss: ProtectionState?
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let eventMapping: EventMapping<PrivacyDashboardEvents>

    private let variant: PrivacyDashboardVariant

    private var toggleReportCounter: Int? { userDefaults.toggleReportCounter > 20 ? nil : userDefaults.toggleReportCounter }

    private let userDefaults: UserDefaults
    private var didOpenReportInfo: Bool = false

    public init(privacyInfo: PrivacyInfo?,
                dashboardMode: PrivacyDashboardMode,
                variant: PrivacyDashboardVariant,
                privacyConfigurationManager: PrivacyConfigurationManaging,
                eventMapping: EventMapping<PrivacyDashboardEvents>,
                userDefaults: UserDefaults = UserDefaults.standard) {
        self.privacyInfo = privacyInfo
        self.initDashboardMode = dashboardMode
        self.variant = variant
        self.privacyConfigurationManager = privacyConfigurationManager
        privacyDashboardScript = PrivacyDashboardUserScript(privacyConfigurationManager: privacyConfigurationManager)
        self.eventMapping = eventMapping
        self.userDefaults = userDefaults
    }

    public func setup(for webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self

        setupPrivacyDashboardUserScript()
        loadPrivacyDashboardHTML()
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

    private func loadPrivacyDashboardHTML() {
        guard var url = Bundle.privacyDashboardURL else { return }
        let screen = initDashboardMode.screen(for: variant).rawValue
        url = url.appendingParameter(name: Constant.screenKey, value: screen)
        if let breakageScreen = breakageScreen(for: variant)?.rawValue {
            url = url.appendingParameter(name: Constant.breakageScreenKey, value: breakageScreen)
        }
        if case .afterTogglePrompt(let category, _) = initDashboardMode {
            url = url.appendingParameter(name: Constant.categoryKey, value: category)
        }
        if case .toggleReport = initDashboardMode {
            url = url.appendingParameter(name: Constant.openerKey, value: Constant.menuScreenKey)
            userDefaults.toggleReportCounter += 1
        }
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    private func breakageScreen(for variant: PrivacyDashboardVariant) -> BreakageScreen? {
        switch variant {
        case .control: return nil
        case .a: return .categorySelection
        case .b: return .categoryTypeSelection
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
        if protectionState.eventOrigin.screen == .choiceToggle {
            eventMapping.fire(.toggleProtectionOff)
        }
        if shouldSegueToToggleReportScreen(with: protectionState) {
            segueToToggleReportScreen(with: protectionState)
        } else {
            didChangeProtectionState(protectionState)
            closeDashboard()
        }
    }

    private func shouldSegueToToggleReportScreen(with protectionState: ProtectionState) -> Bool {
        let manager = ToggleReportsManager(feature: ToggleReportsFeature(manager: privacyConfigurationManager))
        return !protectionState.isProtected && protectionState.eventOrigin.screen == .primaryScreen && manager.shouldShowToggleReport
    }

    private func didChangeProtectionState(_ protectionState: ProtectionState, didSendReport: Bool = false) {
        switch protectionState.eventOrigin.screen {
        case .primaryScreen:
            privacyDashboardDelegate?.privacyDashboardController(self, didChangeProtectionSwitch: protectionState, didSendReport: didSendReport)
        case .breakageForm, .choiceToggle:
            privacyDashboardReportBrokenSiteDelegate?.privacyDashboardController(self, reportBrokenSiteDidChangeProtectionSwitch: protectionState)
        case .toggleReport, .promptBreakageForm, .categorySelection, .categoryTypeSelection, .choiceBreakageForm:
            assertionFailure("These screen don't have toggling capability")
        }
    }

    private func segueToToggleReportScreen(with protectionStateToSubmit: ProtectionState) {
        guard var url = Bundle.privacyDashboardURL else { return }
        url = url.appendingParameter(name: Constant.screenKey, value: Screen.toggleReport.rawValue)
        if case .dashboard = initDashboardMode {
            url = url.appendingParameter(name: Constant.openerKey, value: Constant.dashboardScreenKey)
        }

        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent().deletingLastPathComponent())
        self.protectionStateToSubmitOnToggleReportDismiss = protectionStateToSubmit
        userDefaults.toggleReportCounter += 1
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestOpenUrlInNewTab url: URL) {
        privacyDashboardDelegate?.privacyDashboardController(self, didRequestOpenUrlInNewTab: url)
    }

    func userScriptDidRequestClosing(_ userScript: PrivacyDashboardUserScript) {
        handleUserScriptClosing(toggleReportDismissType: .dismiss)
    }

    private func handleUserScriptClosing(toggleReportDismissType: ToggleReportDismissType) {
        handleDismiss(with: toggleReportDismissType, source: .userScript)
    }

    private func handleDismiss(with type: ToggleReportDismissType, source: ToggleReportDismissSource) {
#if os(iOS)
        if case .toggleReport(completionHandler: let completionHandler) = initDashboardMode {
            completionHandler(type == .send)
            fireToggleReportEventIfNeeded(for: type)
        } else if let protectionStateToSubmitOnToggleReportDismiss {
            didChangeProtectionState(protectionStateToSubmitOnToggleReportDismiss, didSendReport: type == .send)
            fireToggleReportEventIfNeeded(for: type)
        }
        if source == .userScript {
            closeDashboard()
        }
#else
        // macOS implementation is different here - after user taps on Send Report we don't want to trigger any action
        // because of 'Thank you' screen that appears right after.
        if type != .send {
            if let protectionStateToSubmitOnToggleReportDismiss {
                didChangeProtectionState(protectionStateToSubmitOnToggleReportDismiss)
                fireToggleReportEventIfNeeded(for: type)
            }
            closeDashboard()
        }
#endif
    }

    public func handleViewWillDisappear() {
        handleDismiss(with: .dismiss, source: .viewWillDisappear)
    }

    private func fireToggleReportEventIfNeeded(for toggleReportDismissType: ToggleReportDismissType) {
        if let eventToFire = toggleReportDismissType.event {
            var parameters = [PrivacyDashboardEvents.Parameters.didOpenReportInfo: didOpenReportInfo.description]
            if let toggleReportCounter {
                parameters[PrivacyDashboardEvents.Parameters.toggleReportCounter] = String(toggleReportCounter)
            }
            eventMapping.fire(eventToFire, parameters: parameters)
        }
    }

    private func closeDashboard() {
        privacyDashboardNavigationDelegate?.privacyDashboardControllerDidTapClose(self)
    }

    func userScriptDidRequestShowReportBrokenSite(_ userScript: PrivacyDashboardUserScript) {
        let parameters = [
            PrivacyDashboardEvents.Parameters.variant: variant.rawValue,
            PrivacyDashboardEvents.Parameters.source: source.rawValue
        ]
        eventMapping.fire(.reportBrokenSiteShown, parameters: parameters)
        eventMapping.fire(.showReportBrokenSite)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, setHeight height: Int) {
        privacyDashboardNavigationDelegate?.privacyDashboardController(self, didSetHeight: height)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestSubmitBrokenSiteReportWithCategory category: String, description: String) {
        var parameters = [PrivacyDashboardEvents.Parameters.variant: variant.rawValue]
        if case let .afterTogglePrompt(_, didToggleProtectionsFixIssue) = initDashboardMode {
            parameters[PrivacyDashboardEvents.Parameters.didToggleProtectionsFixIssue] = didToggleProtectionsFixIssue.description
        }
        eventMapping.fire(.reportBrokenSiteSent, parameters: parameters)
        privacyDashboardReportBrokenSiteDelegate?.privacyDashboardController(self,
                                                                             didRequestSubmitBrokenSiteReportWithCategory: category,
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
        if shouldSendReport {
            privacyDashboardToggleReportDelegate?.privacyDashboardController(self,
                                                                             didRequestSubmitToggleReportWithSource: source,
                                                                             didOpenReportInfo: didOpenReportInfo,
                                                                             toggleReportCounter: toggleReportCounter)
        }
        let toggleReportDismissType: ToggleReportDismissType = shouldSendReport ? .send : .doNotSend
        handleUserScriptClosing(toggleReportDismissType: toggleReportDismissType)
    }

    public var source: BrokenSiteReport.Source {
        var source: BrokenSiteReport.Source
        switch initDashboardMode {
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

    func userScriptDidOpenReportInfo(_ userScript: PrivacyDashboardUserScript) {
        didOpenReportInfo = true
    }

    // Experiment flows

    func userScript(_ userScript: PrivacyDashboardUserScript, didSelectOverallCategory category: String) {
        eventMapping.fire(.overallCategorySelected, parameters: [PrivacyDashboardEvents.Parameters.category: category])
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didSelectBreakageCategory category: String) {
        let parameters = [
            PrivacyDashboardEvents.Parameters.variant: variant.rawValue,
            PrivacyDashboardEvents.Parameters.category: category
        ]
        eventMapping.fire(.breakageCategorySelected, parameters: parameters)
        privacyDashboardDelegate?.privacyDashboardController(self, didSelectBreakageCategory: category)
    }

    func userScriptDidRequestShowAlertForMissingDescription(_ userScript: PrivacyDashboardUserScript) {
        privacyDashboardReportBrokenSiteDelegate?.privacyDashboardControllerDidRequestShowAlertForMissingDescription(self)
    }

    func userScriptDidRequestShowNativeFeedback(_ userScript: PrivacyDashboardUserScript) {
        privacyDashboardReportBrokenSiteDelegate?.privacyDashboardControllerDidRequestShowGeneralFeedback(self)
    }

    func userScriptDidSkipTogglingStep(_ userScript: PrivacyDashboardUserScript) {
        eventMapping.fire(.skipToggleStep)
    }
}
