
import Foundation
import BrowserServicesKit

struct ProductionDependencies: SyncDependencies {

    let accountCreation: AccountCreating
    let endpoints: EndpointURLs
    let api: RemoteAPIRequestCreating
    let keyGenerator: KeyGenerating
    let secureStore: SecureStoring

    // Wire up dependencies here
    init(baseURL: URL) {
        endpoints = EndpointURLs(baseURL: baseURL)
        api = RemoteAPIRequestCreator()
        keyGenerator = KeyGeneration()
        accountCreation = AccountCreation(endpoints: endpoints, api: api, keyGenerator: keyGenerator)
        secureStore = SecureStorage()
    }

}
