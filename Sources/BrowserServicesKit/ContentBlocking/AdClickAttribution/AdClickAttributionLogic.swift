//
//  AdClickAttributionLogic.swift
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
import ContentBlocking
import Common

public protocol AdClickAttributionLogicDelegate: AnyObject {

    func attributionLogic(_ logic: AdClickAttributionLogic,
                          didRequestRuleApplication rules: ContentBlockerRulesManager.Rules?,
                          forVendor vendor: String?)
}

public class AdClickAttributionLogic {

    public enum State {

        case noAttribution
        case preparingAttribution(vendor: String, session: SessionInfo, completionBlocks: [(() -> Void)])
        case activeAttribution(vendor: String, session: SessionInfo, rules: ContentBlockerRulesManager.Rules)

        var isActiveAttribution: Bool {
            if case .activeAttribution = self { return true }
            return false
        }
    }

    public struct SessionInfo {
        // Start of the attribution
        public let attributionStartedAt: Date
        // Present when we leave webpage associated with the attribution
        public let leftAttributionContextAt: Date?

        init(start: Date = Date(), leftContextAt: Date? = nil) {
            attributionStartedAt = start
            leftAttributionContextAt = leftContextAt
        }
    }

    private let featureConfig: AdClickAttributing
    private let rulesProvider: AdClickAttributionRulesProviding
    private let tld: TLD
    private let getLog: () -> OSLog
    private var log: OSLog {
        getLog()
    }
    private let eventReporting: EventMapping<AdClickAttributionEvents>?
    private let errorReporting: EventMapping<AdClickAttributionDebugEvents>?
    private lazy var counter: AdClickAttributionCounter = AdClickAttributionCounter(onSendRequest: { count in
        self.eventReporting?.fire(.adAttributionPageLoads, parameters: [AdClickAttributionEvents.Parameters.count: String(count)])
    })

    public private(set) var state = State.noAttribution

    private var registerFirstActivity = false

    private var attributionTimeout: DispatchWorkItem?

    public weak var delegate: AdClickAttributionLogicDelegate?

    public init(featureConfig: AdClickAttributing,
                rulesProvider: AdClickAttributionRulesProviding,
                tld: TLD,
                eventReporting: EventMapping<AdClickAttributionEvents>? = nil,
                errorReporting: EventMapping<AdClickAttributionDebugEvents>? = nil,
                log: @escaping @autoclosure () -> OSLog = .disabled) {
        self.featureConfig = featureConfig
        self.rulesProvider = rulesProvider
        self.tld = tld
        self.eventReporting = eventReporting
        self.errorReporting = errorReporting
        self.getLog = log
    }

    public func applyInheritedAttribution(state: State?) {
        guard let state = state else { return }

        if case .noAttribution = self.state {} else {
            errorReporting?.fire(.adAttributionLogicUnexpectedStateOnInheritedAttribution)
            assert(NSClassFromString("XCTest") != nil /* allow when running tests */, "unexpected initial attribution state \(self.state)")
        }

        switch state {
        case .noAttribution:
            self.state = state
        case .preparingAttribution(let vendor, let info, _):
            requestAttribution(forVendor: vendor,
                               attributionStartedAt: info.attributionStartedAt)
        case .activeAttribution(_, let sessionInfo, _):
            if sessionInfo.leftAttributionContextAt == nil {
                self.state = state
                applyRules()
            }
        }
    }

    public func onRulesChanged(latestRules: [ContentBlockerRulesManager.Rules]) {
        switch state {
        case .noAttribution:
            applyRules()
        case .preparingAttribution(let vendor, _, let completionBlocks):
            requestAttribution(forVendor: vendor, completionBlocks: completionBlocks)
        case .activeAttribution(let vendor, _, _):
            requestAttribution(forVendor: vendor)
        }
    }

    public func reapplyCurrentRules() {
        applyRules()
    }

    public func onBackForwardNavigation(mainFrameURL: URL?) {
        guard case .activeAttribution(let vendor, let session, let rules) = state,
        let host = mainFrameURL?.host,
        let currentETLDp1 = tld.eTLDplus1(host) else {
            return
        }

        if vendor == currentETLDp1 {
            if session.leftAttributionContextAt != nil {
                state = .activeAttribution(vendor: vendor,
                                           session: SessionInfo(start: session.attributionStartedAt),
                                           rules: rules)
            }
        } else if session.leftAttributionContextAt == nil {
            state = .activeAttribution(vendor: vendor,
                                       session: SessionInfo(start: session.attributionStartedAt,
                                                           leftContextAt: Date()),
                                       rules: rules)
        }
    }

    public func onProvisionalNavigation(completion: @escaping () -> Void, currentTime: Date = Date()) {
        switch state {
        case .noAttribution:
            completion()
        case .preparingAttribution(let vendor, let session, var completionBlocks):
            os_log(.debug, log: log, "Suspending provisional navigation...")
            completionBlocks.append(completion)
            state = .preparingAttribution(vendor: vendor,
                                          session: session,
                                          completionBlocks: completionBlocks)
        case .activeAttribution(_, let session, _):
            if currentTime.timeIntervalSince(session.attributionStartedAt) >= featureConfig.totalExpiration {
                os_log(.debug, log: log, "Attribution has expired - total expiration")
                disableAttribution()
            } else if let leftAttributionContextAt = session.leftAttributionContextAt,
                      currentTime.timeIntervalSince(leftAttributionContextAt) >= featureConfig.navigationExpiration {
                os_log(.debug, log: log, "Attribution has expired - navigational expiration")
                disableAttribution()
            }
            completion()
        }
    }

    @MainActor
    public func onProvisionalNavigation() async {
        await withCheckedContinuation { continuation in
            onProvisionalNavigation {
                continuation.resume()
            }
        }
    }

    public func onDidFinishNavigation(host: String?, currentTime: Date = Date()) {
        guard case .activeAttribution(let vendor, let session, let rules) = state else {
            return
        }

        if tld.eTLDplus1(host) == vendor {
            counter.onAttributionActive()
        }

        if currentTime.timeIntervalSince(session.attributionStartedAt) >= featureConfig.totalExpiration {
            os_log(.debug, log: log, "Attribution has expired - total expiration")
            disableAttribution()
            return
        }

        if let leftAttributionContextAt = session.leftAttributionContextAt {
           if currentTime.timeIntervalSince(leftAttributionContextAt) >= featureConfig.navigationExpiration {
               os_log(.debug, log: log, "Attribution has expired - navigational expiration")
               disableAttribution()
           } else if tld.eTLDplus1(host) == vendor {
               os_log(.debug, log: log, "Refreshing navigational duration for attribution")
               state = .activeAttribution(vendor: vendor,
                                          session: SessionInfo(start: session.attributionStartedAt),
                                          rules: rules)
           }
        } else if tld.eTLDplus1(host) != vendor {
            os_log(.debug, log: log, "Leaving attribution context")
            state = .activeAttribution(vendor: vendor,
                                       session: SessionInfo(start: session.attributionStartedAt,
                                                            leftContextAt: Date()),
                                       rules: rules)
        }
    }

    public func onRequestDetected(request: DetectedRequest, cpmExperimentOn: Bool? = nil) {
        guard registerFirstActivity,
            BlockingState.allowed(reason: .adClickAttribution) == request.state else { return }

        var parameters: [String: String] = [:]
        if let cpmExperimentOn {
            parameters[AdClickAttributionEvents.Parameters.cpmExperiment] = cpmExperimentOn ? "1" : "0"
        }
        eventReporting?.fire(.adAttributionActive, parameters: parameters)
        registerFirstActivity = false
    }

    private func disableAttribution() {
        assert(state.isActiveAttribution, "unexpected attribution state")
        state = .noAttribution
        applyRules()
    }

    private func onAttributedRulesCompiled(forVendor vendor: String, _ rules: ContentBlockerRulesManager.Rules) {
        guard case .preparingAttribution(let expectedVendor, let session, let completionBlocks) = state else {
            os_log(.error, log: log, "Attributed Rules received unexpectedly")
            errorReporting?.fire(.adAttributionLogicUnexpectedStateOnRulesCompiled)
            return
        }
        guard expectedVendor == vendor else {
            os_log(.debug, log: log, "Attributed Rules received for wrong vendor")
            errorReporting?.fire(.adAttributionLogicWrongVendorOnSuccessfulCompilation)
            return
        }
        state = .activeAttribution(vendor: vendor, session: session, rules: rules)
        applyRules()
        os_log(.debug, log: log, "Resuming provisional navigation for %{public}d requests", completionBlocks.count)
        for completion in completionBlocks {
            completion()
        }
    }

    private func onAttributedRulesCompilationFailed(forVendor vendor: String) {
        guard case .preparingAttribution(let expectedVendor, _, let completionBlocks) = state else {
            os_log(.error, log: log, "Attributed Rules compilation failed")
            errorReporting?.fire(.adAttributionLogicUnexpectedStateOnRulesCompilationFailed)
            return
        }
        guard expectedVendor == vendor else {
            errorReporting?.fire(.adAttributionLogicWrongVendorOnFailedCompilation)
            return
        }
        state = .noAttribution

        applyRules()
        os_log(.debug, log: log, "Resuming provisional navigation for {public}%d requests", completionBlocks.count)
        for completion in completionBlocks {
            completion()
        }
    }

    private func applyRules() {
        if case .activeAttribution(let vendor, _, let rules) = state {
            delegate?.attributionLogic(self, didRequestRuleApplication: rules, forVendor: vendor)
        } else {
            delegate?.attributionLogic(self, didRequestRuleApplication: rulesProvider.globalAttributionRules, forVendor: nil)
        }
    }

    /// Request attribution when we detect it is needed
    private func requestAttribution(forVendor vendorHost: String, attributionStartedAt: Date = Date(), completionBlocks: [() -> Void] = []) {
        state = .preparingAttribution(vendor: vendorHost,
                                      session: SessionInfo(start: attributionStartedAt),
                                      completionBlocks: completionBlocks)

        scheduleTimeout(forVendor: vendorHost)
        rulesProvider.requestAttribution(forVendor: vendorHost) { [weak self] rules in
            self?.cancelTimeout()
            if let rules = rules {
                self?.onAttributedRulesCompiled(forVendor: vendorHost, rules)
            } else {
                self?.onAttributedRulesCompilationFailed(forVendor: vendorHost)
            }
        }
    }

    private func scheduleTimeout(forVendor vendor: String) {
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.onAttributedRulesCompilationFailed(forVendor: vendor)
            self?.attributionTimeout = nil

            self?.errorReporting?.fire(.adAttributionLogicRequestingAttributionTimedOut)
        }
        self.attributionTimeout?.cancel()
        self.attributionTimeout = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0,
                                      execute: timeoutWorkItem)
    }

    private func cancelTimeout() {
        attributionTimeout?.cancel()
        attributionTimeout = nil
    }

    /// Respond to new requests for attribution
    private func onAttributionRequested(forVendor vendorHost: String) {

        switch state {
        case .noAttribution:
            os_log(.debug, log: log, "Preparing attribution for %{private}s", vendorHost)
                requestAttribution(forVendor: vendorHost)
        case .preparingAttribution(let expectedVendor, _, let completionBlocks):
            if expectedVendor != vendorHost {
                os_log(.debug, log: log, "Preparing attributon for %{private}s replacing pending one for %{private}s", vendorHost, expectedVendor)
                requestAttribution(forVendor: vendorHost, completionBlocks: completionBlocks)
            } else {
                os_log(.debug, log: log, "Preparing attribution for %{private}s already in progress", vendorHost)
            }
        case .activeAttribution(let expectedVendor, _, _):
            if expectedVendor != vendorHost {
                os_log(.debug, log: log, "Preparing attributon for %{private}s replacing %{private}s", vendorHost, expectedVendor)
                requestAttribution(forVendor: vendorHost)
            } else {
                os_log(.debug, log: log, "Attribution for %{private}s already active", vendorHost)
            }
        }
    }

}

extension AdClickAttributionLogic: AdClickAttributionDetectionDelegate {

    public func attributionDetection(_ detection: AdClickAttributionDetection,
                                     didDetectVendor vendorHost: String) {
        os_log(.debug, log: log, "Detected attribution requests for %{private}s", vendorHost)
        onAttributionRequested(forVendor: vendorHost)
        registerFirstActivity = true
    }

}
