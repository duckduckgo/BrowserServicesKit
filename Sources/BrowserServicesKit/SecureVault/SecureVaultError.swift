//
//  SecureVaultError.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public enum SecureVaultError: Error {

    case initFailed(cause: Error)
    case authRequired
    case invalidPassword
    case noL1Key
    case noL2Key
    case authError(cause: Error)
    case failedToOpenDatabase(cause: Error)
    case databaseError(cause: Error)
    case duplicateRecord
    case keystoreError(status: Int32)
    case secError(status: Int32)
    case generalCryptoError
    
}
