
import Foundation
import DDGSyncAuth
import BrowserServicesKit

struct AccountCreation: AccountCreating {

    let endpoints: EndpointURLs
    let api: RemoteAPIRequestCreating
    let keyGenerator: KeyGenerating

    func createAccount(device: DeviceDetails) async throws -> SyncAccount {
        let userId = UUID().uuidString
        let password = UUID().uuidString

        let accountKeys = try keyGenerator.createAccountCreationKeys(userId: userId, password: password)

        // /sync-auth/signup and extra JWT token
        var request = api.createRequest(url: endpoints.signup, method: .POST)
        request.addParameter("user_id", value: userId)
        request.addParameter("hashed_password", value: Data(accountKeys.passwordHash).base64EncodedString())
        request.addParameter("protected_encryption_key", value: Data(accountKeys.protectedSymmetricKey).base64EncodedString())
        request.addParameter("device_id", value: device.id.uuidString)
        request.addParameter("device_name", value: device.name)

        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        guard let signupResult = try? JSONDecoder().decode(Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse("signup result")
        }

        guard let baseDataURL = URL(string: signupResult.data_url_base) else {
            throw SyncError.invalidDataInResponse("signup result data_url_base")
        }

        return SyncAccount(userId: userId,
                           primaryKey: Data(accountKeys.primaryKey),
                           secretKey: Data(accountKeys.secretKey),
                           token: signupResult.token,
                           baseDataURL: baseDataURL)
    }

    struct Result: Decodable {

        let user_id: String
        let token: String
        let data_url_base: String

    }

}
