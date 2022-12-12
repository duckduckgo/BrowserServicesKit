//
//  Redirect.swift
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

import Common
import Foundation

public struct Redirect: Equatable {

    public let type: RedirectType
    public let history: [RedirectHistoryItem]
    public let initialNavigationType: InitialNavigationType // write isComitted

    public init(type: RedirectType, history: [RedirectHistoryItem], initialNavigationType: InitialNavigationType) {
        self.type = type
        self.history = history
        self.initialNavigationType = initialNavigationType
    }

    public init(type: RedirectType, appending navigation: Navigation, to redirect: Redirect?) {
        self.init(type: type,
                  history: (redirect?.history ?? []) + [RedirectHistoryItem(navigation: navigation)],
                  initialNavigationType: redirect?.initialNavigationType ?? InitialNavigationType(extractingFrom: navigation.navigationAction.navigationType))
    }

}

public enum RedirectType: Equatable {
    case client(delay: TimeInterval)
    case server
}

extension RedirectType {
    public var isClient: Bool {
        if case .client = self { return true }
        return false
    }
}

public enum InitialNavigationType: Equatable {
    case linkActivated
    case backForward(distance: Int)
    case reload
    case formSubmitted
    case formResubmitted
    case sessionRestoration
    case other
    case custom(UserInfo)
    case unknown

    public init(extractingFrom navigationType: NavigationType) {
        switch navigationType {
        case .linkActivated:
            self = .linkActivated
        case .backForward(distance: let distance):
            self = .backForward(distance: distance)
        case .reload:
            self = .reload
        case .formSubmitted:
            self = .formSubmitted
        case .formResubmitted:
            self = .formResubmitted
        case .redirect(let redirect):
            self = redirect.initialNavigationType
        case .sessionRestoration:
            self = .sessionRestoration
        case .other:
            self = .other
        case .custom(let userInfo):
            self = .custom(userInfo)
        }
    }
}

public struct RedirectHistoryItem: Equatable {

    /// NavigationAction identifier
    public let identifier: UInt64
    public let url: URL
    public let type: RedirectType?
    /// Navigation that ended with redirect started from a `BackForwardListItem` identified by `fromHistoryItemIdentity`
    public let fromHistoryItemIdentity: HistoryItemIdentity?

    public init(identifier: UInt64, url: URL, type: RedirectType?, fromHistoryItemIdentity: HistoryItemIdentity?) {
        self.identifier = identifier
        self.url = url
        self.type = type
        self.fromHistoryItemIdentity = fromHistoryItemIdentity
    }

    public init(navigation: Navigation) {
        self.init(identifier: navigation.navigationAction.identifier,
                  url: navigation.url,
                  type: navigation.navigationAction.navigationType.redirect?.type,
                  fromHistoryItemIdentity: navigation.navigationAction.fromHistoryItemIdentity)
    }

}

extension Redirect: CustomDebugStringConvertible {

    public var debugDescription: String {
        "\(type) from:#\(history.last?.identifier ?? 0) initial:\(initialNavigationType)"
    }

}
