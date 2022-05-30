
import Foundation
import BrowserServicesKit

struct ProductionDependencies: SyncDependencies {

    let account: AccountManaging
    let api: RemoteAPIRequestCreating
    let secureStore: SecureStoring
    let responseHandler: ResponseHandling
    let crypter: Crypting

    private let persistence: LocalDataPersisting

    init(baseUrl: URL, persistence: LocalDataPersisting) {
        self.persistence = persistence

        api = RemoteAPIRequestCreator()
        secureStore = SecureStorage()

        crypter = Crypter(secureStore: secureStore)
        account = AccountManager(authUrl: baseUrl, api: api, crypter: crypter)
        responseHandler = ResponseHandler(persistence: persistence, crypter: crypter)
    }

    func createUpdatesSender(_ persistence: LocalDataPersisting) throws -> UpdatesSending {
        return UpdatesSender(persistence: persistence, dependencies: self)
    }

    func createUpdatesFetcher(_ persistence: LocalDataPersisting) throws -> UpdatesFetching {
        return UpdatesFetcher(persistence: persistence, dependencies: self)
    }

}
