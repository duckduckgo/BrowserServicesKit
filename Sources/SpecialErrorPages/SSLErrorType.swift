//
//  SSLErrorType.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import WebKit

public let SSLErrorCodeKey = "_kCFStreamErrorCodeKey"

public enum SSLErrorType: String, Encodable {

    case expired
    case selfSigned
    case wrongHost
    case invalid

    init(errorCode: Int) {
        self = switch Int32(errorCode) {
        case errSSLCertExpired: .expired
        case errSSLXCertChainInvalid: .selfSigned
        case errSSLHostNameMismatch: .wrongHost
        default: .invalid
        }
    }

}

extension WKError {
    public var sslErrorType: SSLErrorType? {
        guard let errorCode = self.userInfo[SSLErrorCodeKey] as? Int else { return nil }
        let sslErrorType = SSLErrorType(errorCode: errorCode)
        return sslErrorType
    }
}
