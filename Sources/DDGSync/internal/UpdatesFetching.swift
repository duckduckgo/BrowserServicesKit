
import Foundation
import BrowserServicesKit

struct UpdatesFetcher: UpdatesFetching {

    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies
    
    func fetch() async throws {
        guard let token = try dependencies.secureStore.account()?.token else {
            throw SyncError.noToken
        }
        
        switch try await send(token) {
        case .success(let updates):
            try await dependencies.responseHandler.handleUpdates(updates)
            break

        case .failure(let error):
            switch error {
            case SyncError.unexpectedStatusCode(let statusCode):
                if statusCode == 403 {
                    try dependencies.secureStore.removeAccount()
                }
                
            default: break
            }
            throw error
        }
    }

    private func send(_ authorization: String) async throws -> Result<Data, Error> {
        let syncUrl = dependencies.endpoints.syncGet

        // A comma separated list of types
        let url = syncUrl.appendingPathComponent("bookmarks")

        var request = dependencies.api.createRequest(url: url, method: .GET)
        request.addHeader("Authorization", value: "bearer \(authorization)")

        // The since parameter should be an array of each lasted updated timestamp, but don't pass anything if any of the types are missing.
        if let bookmarksUpdatedSince = persistence.bookmarksLastModified {
            let since = [
                bookmarksUpdatedSince
            ]
            request.addParameter("since", value: since.joined(separator: ","))
        }

        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let data = result.data else {
            throw SyncError.noResponseBody
        }

        return .success(data)
    }

}
