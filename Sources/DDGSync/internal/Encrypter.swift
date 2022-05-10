
import Foundation
import Clibsodium

struct Crypter: Crypting {

    let secureStore: SecureStoring

    func encryptAndBase64Encode(_ value: String) throws -> String {
        guard let value = value.data(using: .utf16)?.base64EncodedString(options: []) else {
            fatalError("Unable to base64 encode value")
        }
        return value
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        guard let data = Data(base64Encoded: value),
                let value = String(data: data, encoding: .utf16) else {
            fatalError("Unable to base64 decode value")
        }
        return value
    }

}
