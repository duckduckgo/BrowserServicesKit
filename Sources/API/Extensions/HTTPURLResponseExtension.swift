//
//  HTTPURLResponseExtension.swift
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

import Foundation
import Common

public extension HTTPURLResponse {
    
    enum Constants {
        
        static let weakEtagPrefix = "W/"
        
    }
    
    func assertStatusCode<S: Sequence>(_ acceptedStatusCodes: S) throws where S.Iterator.Element == Int {
        guard acceptedStatusCodes.contains(statusCode) else { throw APIRequest.Error.invalidStatusCode }
    }
    
    func assertSuccessfulStatusCode() throws {
        try assertStatusCode(200..<300)
    }
    
    var isSuccessfulResponse: Bool {
        do {
            try assertSuccessfulStatusCode()
            return true
        } catch {
            return false
        }
    }
    
    func etag(shouldDropWeakPrefix: Bool) -> String? {
        let etag = value(forHTTPHeaderField: HTTPHeaderField.etag)
        if shouldDropWeakPrefix {
            return etag?.dropping(prefix: HTTPURLResponse.Constants.weakEtagPrefix)
        }
        return etag
    }
    
    var etag: String? { etag(shouldDropWeakPrefix: true) }
    
}
