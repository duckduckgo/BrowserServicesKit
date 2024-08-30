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

public enum SSLErrorType: String {

    case expired
    case wrongHost
    case selfSigned
    case invalid

    public static func forErrorCode(_ errorCode: Int) -> Self {
        switch Int32(errorCode) {
        case errSSLCertExpired:
            return .expired
        case errSSLHostNameMismatch:
            return .wrongHost
        case errSSLXCertChainInvalid:
            return .selfSigned
        default:
            return .invalid
        }
    }

    public var rawParameter: String {
        switch self {
        case .expired: return "expired"
        case .wrongHost: return "wrong_host"
        case .selfSigned: return "self_signed"
        case .invalid: return "generic"
        }
    }

}
