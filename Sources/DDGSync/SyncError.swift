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
    case settingsMetadataNotPresent

    case unauthenticatedWhileLoggedIn

    public var isServerError: Bool {
        switch self {
        case .noResponseBody,
                .unexpectedStatusCode,
                .unexpectedResponseBody,
                .invalidDataInResponse:
            return true
        default:
            return false
        }
    }

    var syncErrorString: String {
        return "syncError"
    }
    var syncErrorMessage: String {
        return "syncErrorMessage"
    }

    public var errorParameters: [String: String] {
        switch self {
        case .noToken:
            return [syncErrorString: "noToken"]
        case .failedToMigrate:
            return [syncErrorString: "failedToMigrate"]
        case .failedToLoadAccount:
            return [syncErrorString: "failedToLoadAccount"]
        case .failedToSetupEngine:
            return [syncErrorString: "failedToSetupEngine"]
        case .failedToCreateAccountKeys(let message):
            return [syncErrorString: "failedToCreateAccountKeys", syncErrorMessage: message]
        case .accountNotFound:
            return [syncErrorString: "accountNotFound"]
        case .accountAlreadyExists:
            return [syncErrorString: "accountAlreadyExists"]
        case .invalidRecoveryKey:
            return [syncErrorString: "invalidRecoveryKey"]
        case .noFeaturesSpecified:
            return [syncErrorString: "noFeaturesSpecified"]
        case .noResponseBody:
            return [syncErrorString: "noResponseBody"]
        case .unexpectedStatusCode(let statusCode):
            return [syncErrorString: "unexpectedStatusCode", "code": String(statusCode)]
        case .unexpectedResponseBody:
            return [syncErrorString: "unexpectedResponseBody"]
        case .unableToEncodeRequestBody(let message):
            return [syncErrorString: "unableToEncodeRequestBody", syncErrorMessage: message]
        case .unableToDecodeResponse(let message):
            return [syncErrorString: "unableToDecodeResponse", syncErrorMessage: message]
        case .invalidDataInResponse(let message):
            return [syncErrorString: "invalidDataInResponse", syncErrorMessage: message]
        case .accountRemoved:
            return [syncErrorString: "accountRemoved"]
        case .failedToEncryptValue(let message):
            return [syncErrorString: "failedToEncryptValue", syncErrorMessage: message]
        case .failedToDecryptValue(let message):
            return [syncErrorString: "failedToDecryptValue", syncErrorMessage: message]
        case .failedToPrepareForConnect(let message):
            return [syncErrorString: "failedToPrepareForConnect", syncErrorMessage: message]
        case .failedToOpenSealedBox(let message):
            return [syncErrorString: "failedToOpenSealedBox", syncErrorMessage: message]
        case .failedToSealData(let message):
            return [syncErrorString: "failedToSealData", syncErrorMessage: message]
        case .failedToWriteSecureStore(status: let status):
            return [syncErrorString: "failedToWriteSecureStore", "status": String(status)]
        case .failedToReadSecureStore(status: let status):
            return [syncErrorString: "failedToReadSecureStore", "status": String(status)]
        case .failedToRemoveSecureStore(status: let status):
            return [syncErrorString: "failedToRemoveSecureStore", "status": String(status)]
        case .credentialsMetadataMissingBeforeFirstSync:
            return [syncErrorString: "credentialsMetadataMissingBeforeFirstSync"]
        case .receivedCredentialsWithoutUUID:
            return [syncErrorString: "receivedCredentialsWithoutUUID"]
        case .emailProtectionUsernamePresentButTokenMissing:
            return [syncErrorString: "emailProtectionUsernamePresentButTokenMissing"]
        case .settingsMetadataNotPresent:
            return [syncErrorString: "settingsMetadataNotPresent"]
        case .unauthenticatedWhileLoggedIn:
            return [syncErrorString: "unauthenticatedWhileLoggedIn"]
        }
    }
}
