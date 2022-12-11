//
//  File.swift
//  
//
//  Created by Alexey Martemianov on 09.12.2022.
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
    case backForward(from: HistoryItemIdentity?)
    case reload
    case formResubmitted

    case redirect(type: RedirectType, history: [URL], initial: InitialNavigationType)
    case sessionRestoration

    /// NavigationAction contains `isUserInitiated` flag indicating that javascript navigation action was initiated by user
    case userInitatedJavascriptNavigation

    case custom(UserInfo)

    case unknown

    public init(_ navigationAction: WebViewNavigationAction) {
        switch navigationAction.navigationType {
        case .linkActivated:
#if os(macOS)
            self = .linkActivated(isMiddleClick: navigationAction.isMiddleClick)
#else
            self = .linkActivated
#endif
        case .backForward:
            self = .backForward(from: navigationAction.currentHistoryItemIdentity)
        case .reload:
            self = .reload
        case .formSubmitted:
            self = .formSubmitted
        case .formResubmitted:
            self = .formResubmitted
#if _IS_USER_INITIATED_ENABLED
        case .other where navigationAction.isUserInitiated:
            self = .userInitatedJavascriptNavigation
#endif
        case .other:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }

}

public extension NavigationType {

    var isUserInitiated: Bool {
        switch self {
        case .linkActivated,
                .formSubmitted,
                .backForward,
                .reload,
                .formResubmitted,
                .userInitatedJavascriptNavigation:
            return true
        case .sessionRestoration,
             .redirect,
             .custom,
             .unknown:
            return false
        }
    }

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
    
    var redirectType: RedirectType? {
        if case .redirect(type: let type, history: _, initial: _) = self { return type }
        return nil
    }

    var redirectHistory: [URL]? {
        if case .redirect(type: _, history: let history, initial: _) = self { return history }
        return nil
    }

    var isBackForward: Bool {
        if case .backForward = self { return true }
        return false
    }

}

public enum InitialNavigationType: Equatable {
    case linkActivated
    case backForward(from: HistoryItemIdentity?)
    case reload
    case formSubmitted
    case formResubmitted
    case sessionRestoration
    case userInitatedJavascriptNavigation
    case custom(UserInfo)
    case unknown

    public init(navigationType: NavigationType) {
        switch navigationType {
        case .linkActivated:
            self = .linkActivated
        case .backForward(from: let item):
            self = .backForward(from: item)
        case .reload:
            self = .reload
        case .formSubmitted:
            self = .formSubmitted
        case .formResubmitted:
            self = .formResubmitted
        case .redirect(type: _, history: _, initial: let initialType):
            self = initialType
        case .sessionRestoration:
            self = .sessionRestoration
        case .userInitatedJavascriptNavigation:
            self = .userInitatedJavascriptNavigation
        case .custom(let userInfo):
            self = .custom(userInfo)
        case .unknown:
            self = .unknown
        }
    }
}

public protocol WebViewNavigationAction {
    var navigationType: WKNavigationType { get }
    var currentHistoryItemIdentity: HistoryItemIdentity? { get }
#if os(macOS)
    var isMiddleClick: Bool { get }
#endif
    var isUserInitiated: Bool { get }
}

public struct HistoryItemIdentity: Hashable {
    let object: any AnyObject & Hashable

    init(_ object: any AnyObject & Hashable) {
        self.object = object
    }

    public static func == (lhs: HistoryItemIdentity, rhs: HistoryItemIdentity) -> Bool {
        lhs.object === rhs.object
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(object)
    }
}

extension NavigationType: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .linkActivated: return "linkActivated"
        case .formSubmitted: return "formSubmitted"
        case .backForward: return "backForward"
        case .reload: return "reload"
        case .formResubmitted: return "formResubmitted"
        case .sessionRestoration: return "sessionRestoration"
        case .userInitatedJavascriptNavigation: return "userInitated"
        case .unknown: return "unknown"
        case .redirect(type: let redirectType, history: let history, initial: let initialType):
            return "redirect(\(redirectType), history: \(history), initial: \(initialType))"
        case .custom(let name):
            return "custom(\(name))"
        }
    }
}
