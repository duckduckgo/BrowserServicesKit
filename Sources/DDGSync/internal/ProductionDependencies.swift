
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
        let account = try secureStore.account()
        let syncUrl = account.baseDataURL.appendingPathComponent(Endpoints.sync)
        let token = account.token

        return AtomicSender(dependencies: self,
                            syncUrl: syncUrl,
                            token: token)
    }

    func createUpdatesFetcher() throws -> UpdatesFetching {
        let account = try secureStore.account()
        let syncUrl = account.baseDataURL.appendingPathComponent(Endpoints.sync)
        let token = account.token
        return UpdatesFetcher(dependencies: self, syncUrl: syncUrl, token: token)
    }

}
