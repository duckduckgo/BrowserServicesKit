
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

    private let persistence: LocalDataPersisting

    init(baseURL: URL, persistence: LocalDataPersisting) {
        self.persistence = persistence

        let signUpUrl = baseURL.appendingPathComponent(Endpoints.signup)

        dataLastUpdated = DataLastUpdatedPersistence()
        api = RemoteAPIRequestCreator()
        keyGenerator = KeyGeneration()
        secureStore = SecureStorage()

        accountCreation = AccountCreation(signUpUrl: signUpUrl, api: api, keyGenerator: keyGenerator)
        responseHandler = ResponseHandler(persistence: persistence, dataLastUpdated: dataLastUpdated)
    }

    func createAtomicSender() throws -> AtomicSending {
        let account = try secureStore.account()
        let syncUrl = account.baseDataURL.appendingPathComponent(Endpoints.sync)
        let token = account.token
        return AtomicSender(syncUrl: syncUrl, token: token, api: api, responseHandler: responseHandler, dataLastUpdated: dataLastUpdated)
    }

    func createUpdatesFetcher() throws -> UpdatesFetching {
        let account = try secureStore.account()
        let syncUrl = account.baseDataURL.appendingPathComponent(Endpoints.sync)
        let token = account.token
        return UpdatesFetcher(syncUrl: syncUrl, token: token, api: api, responseHandler: responseHandler)
    }

}
