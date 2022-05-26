
import Foundation
import DDGSyncCrypto
import BrowserServicesKit

struct AccountManager: AccountManaging {

    let authUrl: URL
    let api: RemoteAPIRequestCreating
    let crypter: Crypting

    func createAccount(device: DeviceDetails) async throws -> SyncAccount {
        let userId = UUID().uuidString
        let password = UUID().uuidString

        let accountKeys = try crypter.createAccountCreationKeys(userId: userId, password: password)

        let hashedPassword = Data(accountKeys.passwordHash).base64EncodedString()
        let protectedEncyrptionKey = Data(accountKeys.protectedSymmetricKey).base64EncodedString()

        let params = Signup.Parameters(user_id: userId,
                                hashed_password: hashedPassword,
                                protected_encryption_key: protectedEncyrptionKey,
                                device_id: device.id.uuidString,
                                device_name: device.name)

        guard let paramJson = try? JSONEncoder().encode(params) else {
            fatalError()
        }

        var request = api.createRequest(url: authUrl.appendingPathComponent(Endpoints.signup), method: .POST)
        request.setBody(body: paramJson, withContentType: "application/json")

        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        guard let result = try? JSONDecoder().decode(Signup.Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse("Failed to decode signup result")
        }

        guard let baseDataUrl = URL(string: result.data_url_base) else {
            throw SyncError.invalidDataInResponse("data_url_base missing from response")
        }

        return SyncAccount(userId: userId,
                           primaryKey: Data(accountKeys.primaryKey),
                           secretKey: Data(accountKeys.secretKey),
                           token: result.token,
                           baseDataUrl: baseDataUrl)
    }

    func login(recoveryKey: Data, device: DeviceDetails) async throws -> SyncAccount {
        let recoveryInfo = try crypter.extractLoginInfo(recoveryKey: recoveryKey)

        let params = Login.Parameters(user_id: recoveryInfo.userId,
                                      hashed_password: recoveryInfo.passwordHash.base64EncodedString(),
                                      device_id: device.id.uuidString,
                                      device_name: device.name)

        guard let paramJson = try? JSONEncoder().encode(params) else {
            fatalError()
        }

        var request = api.createRequest(url: authUrl.appendingPathComponent(Endpoints.login), method: .POST)
        request.setBody(body: paramJson, withContentType: "application/json")

        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        print(String(data: body, encoding: .utf8) ?? "invalid result.data")
        guard let result = try? JSONDecoder().decode(Login.Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse("Failed to decode login result")
        }

        guard let baseDataUrl = URL(string: result.data_url_base) else {
            throw SyncError.invalidDataInResponse("data_url_base missing from response")
        }

        guard let protectedSecretKey = Data(base64Encoded: result.protected_encryption_key) else {
            throw SyncError.invalidDataInResponse("protected_key missing from response")
        }

        let token = result.token

        let secretKey = try crypter.extractSecretKey(protectedSecretKey: protectedSecretKey, stretchedPrimaryKey: recoveryInfo.stretchedPrimaryKey)

        return SyncAccount(userId: recoveryInfo.userId, primaryKey: recoveryInfo.primaryKey, secretKey: secretKey, token: token, baseDataUrl: baseDataUrl)
    }

    struct Signup {
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

    struct Login {

        struct Result: Decodable {
            let data_url_base: String
            let devices: [Device]
            let token: String
            let protected_encryption_key: String
        }

        struct Device: Decodable {
            let device_id: String
            let device_name: String
        }
        
        struct Parameters: Encodable {
            let user_id: String
            let hashed_password: String
            let device_id: String
            let device_name: String
        }

    }

}
