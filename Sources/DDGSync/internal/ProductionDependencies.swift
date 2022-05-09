
import Foundation
import BrowserServicesKit

struct ProductionDependencies: SyncDependencies {

    enum Endpoints {

        static let signup = "sync-auth/signup"
        static let sync = "sync-data/sync"

    }

    let accountCreation: AccountCreating
    let api: RemoteAPIRequestCreating
    let keyGenerator: KeyGenerating
    let secureStore: SecureStoring

    init(baseURL: URL) {

        api = RemoteAPIRequestCreator()
        keyGenerator = KeyGeneration()
        let signUpUrl = baseURL.appendingPathComponent(Endpoints.signup)
        accountCreation = AccountCreation(signUpUrl: signUpUrl, api: api, keyGenerator: keyGenerator)
        secureStore = SecureStorage()
    }

    func createAtomicSender() throws -> AtomicSending {
        let account = try secureStore.account()
        let syncUrl = account.baseDataURL.appendingPathComponent(Endpoints.sync)
        let token = account.token
        return AtomicSender(syncUrl: syncUrl, token: token, api: api)
    }

}
