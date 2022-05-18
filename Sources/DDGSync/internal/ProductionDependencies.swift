
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
    let responseHandler: ResponseHandling
    let dataLastUpdated: DataLastUpdatedPersisting
    let crypter: Crypting

    private let persistence: LocalDataPersisting

    init(baseURL: URL, persistence: LocalDataPersisting) {
        self.persistence = persistence

        let signUpUrl = baseURL.appendingPathComponent(Endpoints.signup)

        dataLastUpdated = DataLastUpdatedPersistence()
        api = RemoteAPIRequestCreator()
        keyGenerator = KeyGeneration()
        secureStore = SecureStorage()

        crypter = Crypter(secureStore: secureStore)
        accountCreation = AccountCreation(signUpUrl: signUpUrl, api: api, keyGenerator: keyGenerator)
        responseHandler = ResponseHandler(persistence: persistence, dataLastUpdated: dataLastUpdated, crypter: crypter)
    }

    func createAtomicSender() throws -> AtomicSending {
        let auth = try accountAndToken()
        let syncUrl = auth.account.baseDataURL.appendingPathComponent(Endpoints.sync)

        return AtomicSender(dependencies: self,
                            syncUrl: syncUrl,
                            token: auth.token)
    }

    func createUpdatesFetcher() throws -> UpdatesFetching {
        let auth = try accountAndToken()
        let syncUrl = auth.account.baseDataURL.appendingPathComponent(Endpoints.sync)
        return UpdatesFetcher(dependencies: self, syncUrl: syncUrl, token: auth.token)
    }

    private func accountAndToken() throws -> (account: SyncAccount, token: String) {
        guard let account = try secureStore.account() else {
            throw SyncError.accountNotFound
        }

        guard let token = account.token else {
            throw SyncError.noToken
        }

        return (account, token)
    }

}
