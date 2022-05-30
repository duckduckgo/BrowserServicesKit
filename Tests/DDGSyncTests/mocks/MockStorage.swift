
import Foundation
import DDGSync

class MockStorage: SecureStoring {
    
    var _account: SyncAccount?
    var _tokenCleared = false
    
    func persistAccount(_ account: SyncAccount) throws {
        _account = account
    }

    func account() throws -> SyncAccount? {
        return _account
    }

    func clearToken() throws {
        _tokenCleared = true
    }
    
}
