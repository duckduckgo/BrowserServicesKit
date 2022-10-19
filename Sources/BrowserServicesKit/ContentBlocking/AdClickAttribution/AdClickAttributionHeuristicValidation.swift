//
//  AdClickAttributionHeuristicValidation.swift
//  DuckDuckGo
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

protocol AdClickAttributionHeuristicValidationAddressSource: AnyObject {

    var currentWebsite: URL? { get }
}

class AdClickAttributionHeuristicValidation {
    
    enum Constants {
        static let checkInterval: TimeInterval = 0.3
    }
    
    enum State {
        case idle
        case validating(domain: String, timer: Timer)
    }
    
    weak var websiteAddressSource: AdClickAttributionHeuristicValidationAddressSource?
    
    private var state: State = .idle {
        willSet {
            if case .validating(_, let timer) = state {
                timer.invalidate()
            }
        }
    }
    
    private func scheduleValidation(for domain: String) {
        let timer = Timer.scheduledTimer(withTimeInterval: Constants.checkInterval, repeats: false) { _ [weak self] in
            self?.onTimerFired()
        }
        state = .validating(domain: domain, timer: timer)
    }
    
    private func onTimerFired() {
        guard case .validating(let domain, _) = state else {
            return
        }
        
        // fire event
    }
    
    func onHeuristicDetected(domain: String) {
        scheduleValidation(for: domain)
    }
    
    func onNavigation() {
        guard case .validating(let domain, _) = state else {
            return
        }
        scheduleValidation(for: domain)
    }

    /// Invalidate on:
    ///  - User navigation
    ///  - Back/Forward navigation
    func invalidateValidation() {
        state = .idle
    }
}
