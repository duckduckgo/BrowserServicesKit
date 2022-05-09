
import Foundation
import BrowserServicesKit

struct UpdatesFetcher: UpdatesFetching {

    let syncUrl: URL
    let token: String
    let api: RemoteAPIRequestCreating
    let responseHandler: ResponseHandling

    func fetch() async throws {

        switch try await send() {
        case .success(let updates):
            try await responseHandler.handleUpdates(updates)
            break

        case .failure(let error):
            throw error
        }
    }

    private func send() async throws -> Result<[String: Any], Error> {
        var request = api.createRequest(url: syncUrl, method: .GET)

        request.addHeader("Authorization", value: "bearer \(token)")

        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let data = result.data else {
            return .success([:])
        }

        guard let updates = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.unableToDecodeResponse(message: "Failed to convert response to JSON dictionary of type [String: Any]")
        }

        return .success(updates)
    }

}
