//
//  HTTPURLResponse+Utilities.swift
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

import Foundation
import Common

public extension HTTPURLResponse {

    var httpStatus: HTTPStatusCode {
        HTTPStatusCode(rawValue: statusCode) ?? .unknown
    }
    var etag: String? { etag(droppingWeakPrefix: true) }

    enum Constants {
        static let weakEtagPrefix = "W/"
    }

    func etag(droppingWeakPrefix: Bool) -> String? {
        let etag = value(forHTTPHeaderField: HTTPHeaderKey.etag)
        if droppingWeakPrefix {
            return etag?.dropping(prefix: HTTPURLResponse.Constants.weakEtagPrefix)
        }
        return etag
    }
}
