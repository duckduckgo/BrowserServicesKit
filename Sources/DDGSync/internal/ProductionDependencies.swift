
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

    func createAtomicSender(_ persistence: LocalDataPersisting) throws -> AtomicSending {
        let auth = try accountAndToken()
        let syncUrl = auth.account.baseDataUrl.appendingPathComponent(Endpoints.sync)

        return AtomicSender(persistence: persistence,
                            dependencies: self,
                            syncUrl: syncUrl,
                            token: auth.token)
    }

    func createUpdatesFetcher(_ persistence: LocalDataPersisting) throws -> UpdatesFetching {
        let auth = try accountAndToken()
        let syncUrl = auth.account.baseDataUrl.appendingPathComponent(Endpoints.sync)
        return UpdatesFetcher(persistence: persistence, dependencies: self, syncUrl: syncUrl, token: auth.token)
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
