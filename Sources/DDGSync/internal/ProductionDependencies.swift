
import Foundation
import BrowserServicesKit

struct ProductionDependencies: SyncDependencies {

    let fileStorageUrl: URL
    let endpoints: Endpoints
    let account: AccountManaging
    let api: RemoteAPIRequestCreating
    let secureStore: SecureStoring
    let responseHandler: ResponseHandling
    let crypter: Crypting

    private let persistence: LocalDataPersisting

    init(baseUrl: URL,
         persistence: LocalDataPersisting) {
        
        self.init(fileStorageUrl: FileManager.default.applicationSupportDirectoryForComponent(named: "Sync"),
                  baseUrl: baseUrl,
                  persistence: persistence,
                  secureStore: SecureStorage())
    }
    
    init(fileStorageUrl: URL, baseUrl: URL, persistence: LocalDataPersisting, secureStore: SecureStoring) {
        self.fileStorageUrl = fileStorageUrl
        self.endpoints = Endpoints(baseUrl: baseUrl)
        self.persistence = persistence
        self.secureStore = secureStore

        api = RemoteAPIRequestCreator()

        crypter = Crypter(secureStore: secureStore)
        account = AccountManager(endpoints: endpoints, api: api, crypter: crypter)
        responseHandler = ResponseHandler(persistence: persistence, crypter: crypter)
    }

    func createUpdatesSender(_ persistence: LocalDataPersisting) throws -> UpdatesSending {
        return UpdatesSender(fileStorageUrl: fileStorageUrl, persistence: persistence, dependencies: self)
    }

    func createUpdatesFetcher(_ persistence: LocalDataPersisting) throws -> UpdatesFetching {
        return UpdatesFetcher(persistence: persistence, dependencies: self)
    }

}
