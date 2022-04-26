
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
        guard (200 ..< 300).contains(result.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.statusCode)
        }

        return SyncAccount(userId: userId, primaryKey: Data(), secretKey: Data(), token: "")
    }

}
