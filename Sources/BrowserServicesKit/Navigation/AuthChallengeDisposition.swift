//
//  AuthChallengeDisposition.swift
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

public enum AuthChallengeDisposition {
    /// Use the specified credential
    case useCredential(URLCredential?)
    /// The entire request will be canceled
    case cancelAuthenticationChallenge
    /// This challenge is rejected and the next authentication protection space should be tried
    case rejectProtectionSpace

    var dispositionAndCredential: (URLSession.AuthChallengeDisposition, URLCredential?) {
        switch self {
        case .useCredential(let credential):
            return (.useCredential, credential)
        case .cancelAuthenticationChallenge:
            return (.cancelAuthenticationChallenge, nil)
        case .rejectProtectionSpace:
            return (.rejectProtectionSpace, nil)
        }
    }
}

extension AuthChallengeDisposition? {
    /// Pass challenge to next responder
    public static let next = AuthChallengeDisposition?.none
}
