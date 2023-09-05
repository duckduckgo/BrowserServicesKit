//
//  SyncError.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

public enum SyncError: Error, Equatable {

    case noToken

    case failedToMigrate
    case failedToLoadAccount
    case failedToSetupEngine

    case failedToCreateAccountKeys(_ message: String)
    case accountNotFound
    case accountAlreadyExists
    case invalidRecoveryKey

    case noFeaturesSpecified
    case noResponseBody
    case unexpectedStatusCode(Int)
    case unexpectedResponseBody
    case unableToEncodeRequestBody(_ message: String)
    case unableToDecodeResponse(_ message: String)
    case invalidDataInResponse(_ message: String)
    case accountRemoved

    case failedToEncryptValue(_ message: String)
    case failedToDecryptValue(_ message: String)
    case failedToPrepareForConnect(_ message: String)
    case failedToOpenSealedBox(_ message: String)
    case failedToSealData(_ message: String)

    case failedToWriteSecureStore(status: OSStatus)
    case failedToReadSecureStore(status: OSStatus)
    case failedToRemoveSecureStore(status: OSStatus)

    case credentialsMetadataMissingBeforeFirstSync
    case receivedCredentialsWithoutUUID

    case emailProtectionUsernamePresentButTokenMissing
}

extension SyncError: CustomNSError {

    public var errorCode: Int {
        switch self {
        case .noToken: return 13

        case .failedToMigrate: return 14
        case .failedToLoadAccount: return 15
        case .failedToSetupEngine: return 16

        case .failedToCreateAccountKeys: return 0
        case .accountNotFound: return 17
        case .accountAlreadyExists: return 18
        case .invalidRecoveryKey: return 19

        case .noFeaturesSpecified: return 20
        case .noResponseBody: return 21
        case .unexpectedStatusCode: return 1
        case .unexpectedResponseBody: return 22
        case .unableToEncodeRequestBody: return 2
        case .unableToDecodeResponse: return 3
        case .invalidDataInResponse: return 4
        case .accountRemoved: return 23

        case .failedToEncryptValue: return 5
        case .failedToDecryptValue: return 6
        case .failedToPrepareForConnect: return 7
        case .failedToOpenSealedBox: return 8
        case .failedToSealData: return 9

        case .failedToWriteSecureStore: return 10
        case .failedToReadSecureStore: return 11
        case .failedToRemoveSecureStore: return 12

        case .credentialsMetadataMissingBeforeFirstSync: return 24
        case .receivedCredentialsWithoutUUID: return 25
        case .emailProtectionUsernamePresentButTokenMissing: return 26
        }
    }

    public var errorUserInfo: [String: Any] {
        var errorUserInfo = [String: Any]()
        switch self {
        case .unexpectedStatusCode(let statusCode):
            errorUserInfo["statusCode"] = statusCode
        case .failedToWriteSecureStore(let status), .failedToReadSecureStore(let status), .failedToRemoveSecureStore(let status):
            errorUserInfo["statusCode"] = status
        default:
            break
        }

        return errorUserInfo
    }

}
