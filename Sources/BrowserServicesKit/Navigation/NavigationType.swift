//
//  File.swift
//  
//
//  Created by Alexey Martemianov on 09.12.2022.
//

import Common
import Foundation
import WebKit

public indirect enum NavigationType: Equatable {

    case linkActivated(isMiddleClick: Bool)
    case formSubmitted
    case backForward(from: WKBackForwardListItem?)
    case reload
    case formResubmitted

    case redirect(type: RedirectType, previousNavigation: Navigation?)
    case sessionRestoration

    /// NavigationAction contains `isUserInitiated` flag indicating that javascript navigation action was initiated by user
    case userInitatedJavascriptRedirect

    case custom(UserInfo)

    case unknown

    init(_ navigationAction: WKNavigationAction) {
        switch navigationAction.navigationType {
        case .linkActivated:
            self = .linkActivated(isMiddleClick: navigationAction.isMiddleClick)
        case .formSubmitted:
            self = .formSubmitted
        case .backForward:
            self = .backForward(from: navigationAction.sourceFrame.webView?.backForwardList.currentItem)
        case .reload:
            self = .reload
        case .formResubmitted:
            self = .formResubmitted
#if _IS_USER_INITIATED_ENABLED
        case .other where navigationAction.isUserInitiated:
            self = .userInitatedJavascriptRedirect
#endif
        case .other:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }

    var isUserInitiated: Bool {
        switch self {
        case .linkActivated,
                .formSubmitted,
                .backForward,
                .reload,
                .formResubmitted:
            return true
#if _IS_USER_INITIATED_ENABLED
        case .userInitatedJavascriptRedirect:
            return true
#endif
        case .sessionRestoration,
             .redirect,
             .custom,
             .unknown:
            return false
        }
    }

    var isRedirect: Bool {
        if case .redirect = self { return true }
        return false
    }

    var previousNavigation: Navigation? {
        if case .redirect(type: _, previousNavigation: let navigation) = self { return navigation }
        return nil
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
        case .userInitatedJavascriptRedirect: return "userInitated"
        case .unknown: return "unknown"
        case .redirect(type: let redirectType, previousNavigation: let navigation):
            return "redirect(\(redirectType), navigation: \(navigation?.debugDescription ?? "<nil>")"
        case .custom(let name):
            return "custom(\(name))"
        }
    }
}
