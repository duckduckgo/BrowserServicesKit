//
//  CryptingMock.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Bookmarks
import DDGSync
import Foundation

struct CryptingMock: Crypting {

    var _encryptAndBase64Encode: (String) throws -> String = { value in
        if [BookmarkEntity.Constants.favoritesFolderID, BookmarkEntity.Constants.rootFolderID].contains(value) {
            return value
        }
        return "encrypted_\(value)"
    }
    var _base64DecodeAndDecrypt: (String) throws -> String = { value in
        if [BookmarkEntity.Constants.favoritesFolderID, BookmarkEntity.Constants.rootFolderID].contains(value) {
            return value
        }
        return value.dropping(prefix: "encrypted_")
    }

    func fetchSecretKey() throws -> Data {
        .init()
    }

    func encryptAndBase64Encode(_ value: String) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }

    func encryptAndBase64Encode(_ value: String, using secretKey: Data) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String, using secretKey: Data) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }
}
