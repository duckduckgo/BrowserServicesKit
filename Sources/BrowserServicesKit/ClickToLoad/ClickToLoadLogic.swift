//
//  ClickToLoadLogic.swift
//  DuckDuckGo
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
import ContentBlocking
import Common
import os.log

public protocol ClickToLoadLogicDelegate: AnyObject {

    func clickToLoadLogic(_ logic: ClickToLoadLogic,
                          didRequestRuleApplication rules: ContentBlockerRulesManager.Rules?,
                          forDomain domain: String?)
}

public final class ClickToLoadLogic {

    public enum State {
        case `default`
        case unblocked(domain: String, rules: ContentBlockerRulesManager.Rules)
    }

    public private(set) var state = State.default

    public weak var delegate: ClickToLoadLogicDelegate?

    private let rulesProvider: ClickToLoadRulesProviding
    private var compilationTimeout: DispatchWorkItem?
    private let getLog: () -> OSLog
    private var log: OSLog {
        getLog()
    }

    public init(rulesProvider: ClickToLoadRulesProviding,
                log: @escaping @autoclosure () -> OSLog = .disabled) {
        self.rulesProvider = rulesProvider
        self.getLog = log
    }

    public func onRulesChanged(latestRules: [ContentBlockerRulesManager.Rules]) {
        switch state {
        case .`default`:
            applyRules()
        case .unblocked(let domain, _):
            requestException(forDomain: domain)
        }
    }

//    public func onProvisionalNavigation(completion: @escaping () -> Void) {
//        switch state {
//        case .`default`:
//            break
//        case .unblocked:
//            disableAttribution()
//        }
//        completion()
//    }

//    @MainActor
//    public func onProvisionalNavigation() async {
//        await withCheckedContinuation { continuation in
//            onProvisionalNavigation {
//                continuation.resume()
//            }
//        }
//    }

    public func onDidFinishNavigation(host: String?) {
        guard case .unblocked = state else {
            return
        }
        disableAttribution()
    }

    private func disableAttribution() {
        state = .default
        applyRules()
    }

    private func onClickToLoadRulesCompiled(forDomain domain: String, _ rules: ContentBlockerRulesManager.Rules) {
        guard case .default = state else {
            os_log(.error, log: log, "CTL Rules received unexpectedly")
            return
        }
        state = .unblocked(domain: domain, rules: rules)
        applyRules()
    }

    private func onClickToLoadRulesCompilationFailed(forDomain domain: String) {
        guard case .default = state else {
            os_log(.error, log: log, "CTL Rules compilation failed")
            return
        }
        state = .default
        applyRules()
    }

    private func applyRules() {
        if case .unblocked(let domain, let rules) = state {
            delegate?.clickToLoadLogic(self, didRequestRuleApplication: rules, forDomain: domain) // there check for domain and refresh if needed
        } else {
            delegate?.clickToLoadLogic(self, didRequestRuleApplication: rulesProvider.globalRules, forDomain: nil)
        }
    }

    /// Request attribution when we detect it is needed
    private func requestException(forDomain domain: String) {
        scheduleTimeout(forDomain: domain)
        rulesProvider.requestException(forDomain: domain) { [weak self] rules in
            self?.cancelTimeout()
            if let rules = rules {
                self?.onClickToLoadRulesCompiled(forDomain: domain, rules)
            } else {
                self?.onClickToLoadRulesCompilationFailed(forDomain: domain)
            }
        }
    }

    private func scheduleTimeout(forDomain domain: String) {
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.onClickToLoadRulesCompilationFailed(forDomain: domain)
            self?.compilationTimeout = nil
        }
        self.compilationTimeout?.cancel()
        self.compilationTimeout = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0,
                                      execute: timeoutWorkItem)
    }

    private func cancelTimeout() {
        compilationTimeout?.cancel()
        compilationTimeout = nil
    }

    /// Respond to new requests for attribution
    private func onClickToLoad(forDomain domain: String) {
        switch state {
        case .`default`:
            os_log(.debug, log: log, "Preparing exception for %{private}s", domain)
            requestException(forDomain: domain)
        case .unblocked(let expectedDomain, _):
            if expectedDomain != domain {
                os_log(.debug, log: log, "Preparing exception for %{private}s replacing %{private}s", domain, expectedDomain)
                requestException(forDomain: domain)
            } else {
                os_log(.debug, log: log, "CTL exception for %{private}s already active", domain)
            }
        }
    }

// Do we need it?
//
//    public func reapplyCurrentRules() {
//        applyRules()
//    }


}
