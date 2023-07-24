//
//  File.swift
//  
//
//  Created by ddg on 24/07/2023.
//

import Foundation

/// A convenience enum to unify the logic for selecting the right keychain through the query attributes.
///
public enum KeychainType {
    /// Uses the app's default data proteciton keychain, without specifying an access group.
    ///
    case app

    /// Uses the system keychain.
    ///
    case system

    /// Uses the data protection keychain for the specified access group (to which the app must have access to).
    ///
    case shared(accessGroup: String)

    func queryAttributes() -> [CFString: Any] {
        switch self {
        case .app:
            return [kSecUseDataProtectionKeychain: true]
        case .system:
            return [kSecUseDataProtectionKeychain: false]
        case .shared(let accessGroup):
            return [
                kSecUseDataProtectionKeychain: true,
                kSecAttrAccessGroup: accessGroup
            ]
        }
    }
}
