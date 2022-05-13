
import Foundation
import BrowserServicesKit

struct UpdatesFetcher: UpdatesFetching {

    let dependencies: SyncDependencies
    let syncUrl: URL
    let token: String

    func fetch() async throws {

        switch try await send() {
        case .success(let updates):
            try await dependencies.responseHandler.handleUpdates(updates)
            break

        case .failure(let error):
            throw error
        }
    }

    private func send() async throws -> Result<[String: Any], Error> {
        let url = syncUrl.appendingPathComponent("favorites,bookmarks")

        var request = dependencies.api.createRequest(url: url, method: .GET)
        request.addHeader("Authorization", value: "bearer \(token)")

        let since = [dependencies.dataLastUpdated.favorites ?? "",
                     dependencies.dataLastUpdated.bookmarks ?? ""]

        request.addParameter("since", value: since.joined(separator: ","))

        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let data = result.data else {
            return .success([:])
        }

        guard let updates = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.unableToDecodeResponse("Failed to convert response to JSON dictionary of type [String: Any]")
        }

        return .success(updates)
    }

}
