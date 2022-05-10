
import Foundation
import DDGSyncCrypto
import BrowserServicesKit

struct AccountCreation: AccountCreating {

    let signUpUrl: URL
    let api: RemoteAPIRequestCreating
    let keyGenerator: KeyGenerating

    func createAccount(device: DeviceDetails) async throws -> SyncAccount {
        let userId = UUID().uuidString
        let password = UUID().uuidString

        let accountKeys = try keyGenerator.createAccountCreationKeys(userId: userId, password: password)

        let hashedPassword = Data(accountKeys.passwordHash).base64EncodedString()
        let protectedEncyrptionKey = Data(accountKeys.protectedSymmetricKey).base64EncodedString()

        let params = Parameters(user_id: userId,
                                hashed_password: hashedPassword,
                                protected_encryption_key: protectedEncyrptionKey,
                                device_id: device.id.uuidString,
                                device_name: device.name)

        guard let paramJson = try? JSONEncoder().encode(params) else {
            fatalError()
        }

        var request = api.createRequest(url: signUpUrl, method: .POST)
        request.setBody(body: paramJson, withContentType: "application/json")

        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        guard let signupResult = try? JSONDecoder().decode(Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse(message: "Failed to decode signup result")
        }

        guard let baseDataURL = URL(string: signupResult.data_url_base) else {
            throw SyncError.invalidDataInResponse(message: "data_url_base missing from response")
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

    struct Parameters: Encodable {

        let user_id: String
        let hashed_password: String
        let protected_encryption_key: String
        let device_id: String
        let device_name: String

    }

}
