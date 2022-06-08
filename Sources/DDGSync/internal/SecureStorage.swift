
import Foundation

struct SecureStorage: SecureStoring {

    // DO NOT CHANGE except if you want to deliberately invalidate all users's sync accounts.
    // The keys have a uid to deter casual hacker from easily seeing which keychain entry is related to what.
    private static let encodedKey = "833CC26A-3804-4D37-A82A-C245BC670692".data(using: .utf8)
    
    private static let defaultQuery: [AnyHashable: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.duckduckgo.sync",
        kSecAttrGeneric: encodedKey as Any,
        kSecAttrAccount: encodedKey as Any,
    ]
    
    func persistAccount(_ account: SyncAccount) throws {
        let data = try JSONEncoder().encode(account)
        
        var query = Self.defaultQuery
        query[kSecUseDataProtectionKeychain] = true
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        query[kSecAttrSynchronizable] = false
        query[kSecValueData] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SyncError.failedToWriteSecureStore(status: status)
        }
    }

    func account() throws -> SyncAccount? {
        var query = Self.defaultQuery
        query[kSecReturnData] = true

        var item: CFTypeRef?

        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw SyncError.failedToReadSecureStore(status: status)
        }
        
        if let data = item as? Data {
            return try JSONDecoder().decode(SyncAccount.self, from: data)
        }
        
        return nil
    }

    func removeAccount() throws {
        let status = SecItemDelete(Self.defaultQuery as CFDictionary)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw SyncError.failedToRemoveSecureStore(status: status)
        }
    }
    
}
