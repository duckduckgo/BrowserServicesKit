//
//  NavigationType.swift
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
import WebKit

public enum NavigationType: Equatable {

#if os(macOS)
    case linkActivated(isMiddleClick: Bool)
#else
    case linkActivated
#endif
    case formSubmitted
    case formResubmitted

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    case backForward(distance: Int)
#else
    case backForward
#endif
    case reload

    case redirect(RedirectType)
    case sessionRestoration
    case sameDocumentNavigation

    case other

    /// developer-defined, set using `DistributedNavigationDelegate.setExpectedNavigationType(_:matching:)`
    case custom(CustomNavigationType)

    public init(_ navigationAction: WebViewNavigationAction, currentHistoryItemIdentity: HistoryItemIdentity?) {
        switch navigationAction.navigationType {
        case .linkActivated where navigationAction.isSameDocumentNavigation,
             .other where navigationAction.isSameDocumentNavigation:
            self = .sameDocumentNavigation

        case .linkActivated:
#if os(macOS)
            self = .linkActivated(isMiddleClick: navigationAction.isMiddleClick)
#else
            self = .linkActivated
#endif
        case .backForward:
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
            self = .backForward(distance: navigationAction.getDistance(from: currentHistoryItemIdentity) ?? 0)
#else
            self = .backForward
#endif
        case .reload:
            self = .reload
        case .formSubmitted:
            self = .formSubmitted
        case .formResubmitted:
            self = .formResubmitted
        case .other:
            self = .other
        @unknown default:
            self = .other
        }
    }

}

public struct CustomNavigationType: RawRepresentable, Hashable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension NavigationType {

    var isLinkActivated: Bool {
        if case .linkActivated = self { return true }
        return false
    }

#if os(macOS)
    var isMiddleButtonClick: Bool {
        if case .linkActivated(isMiddleClick: let isMiddleClick) = self { return isMiddleClick }
        return false
    }
#endif

    var isRedirect: Bool {
        if case .redirect = self { return true }
        return false
    }
    
    var redirect: RedirectType? {
        if case .redirect(let redirect) = self { return redirect }
        return nil
    }

    var isBackForward: Bool {
        if case .backForward = self { return true }
        return false
    }

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    var backForwardDistance: Int? {
        if case .backForward(distance: let distance) = self, distance != 0 { return distance }
        return nil
    }

    var isGoingBack: Bool {
        (backForwardDistance ?? 0) < 0
    }

    var isGoingForward: Bool {
        (backForwardDistance ?? 0) > 0
    }
#endif

    var isSessionRestoration: Bool {
        if case .sessionRestoration = self { return true }
        return false
    }

}

public protocol WebViewNavigationAction {
    var navigationType: WKNavigationType { get }
    var isSameDocumentNavigation: Bool { get }

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    func getDistance(from historyItemIdentity: HistoryItemIdentity?) -> Int?
#endif
#if os(macOS)
    var isMiddleClick: Bool { get }
#endif
    var isUserInitiated: Bool? { get }
}

public struct HistoryItemIdentity: Hashable {
    let object: any AnyObject & Hashable

    public init(_ object: any AnyObject & Hashable) {
        self.object = object
    }

    public static func == (lhs: HistoryItemIdentity, rhs: HistoryItemIdentity) -> Bool {
        lhs.object === rhs.object
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(object)
    }
}

extension WKBackForwardListItem {

    public var identity: HistoryItemIdentity { HistoryItemIdentity(self) }

}

extension NavigationType: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .linkActivated: return "linkActivated"
        case .formSubmitted: return "formSubmitted"
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        case .backForward(let distance): return "backForward" + (distance != 0 ? "[\(distance)]" : "")
#else
        case .backForward: return "backForward"
#endif
        case .reload: return "reload"
        case .formResubmitted: return "formResubmitted"
        case .sessionRestoration: return "sessionRestoration"
        case .other: return "other"
        case .redirect(let redirect):
            return "redirect(\(redirect))"
        case .sameDocumentNavigation:
            return "sameDocumentNavigation"
        case .custom(let name):
            return "custom(\(name.rawValue))"
        }
    }
}
