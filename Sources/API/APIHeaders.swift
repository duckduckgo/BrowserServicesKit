//
//  APIHeaders.swift
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

public typealias HTTPHeaders = [String: String]

public struct APIHeaders {
    
    public typealias UserAgent = String
    private let userAgent: UserAgent
    
    public init(with userAgent: UserAgent) {
        self.userAgent = userAgent
    }
    
    public var defaultHeaders: HTTPHeaders {
        let acceptEncoding = "gzip;q=1.0, compress;q=0.5"
        let languages = Locale.preferredLanguages.prefix(6)
        let acceptLanguage = languages.enumerated().map { index, language in
            let q = 1.0 - (Double(index) * 0.1)
            return "\(language);q=\(q)"
        }.joined(separator: ", ")
        
        return [
            HTTPHeaderField.acceptEncoding: acceptEncoding,
            HTTPHeaderField.acceptLanguage: acceptLanguage,
            HTTPHeaderField.userAgent: userAgent
        ]
    }
    
    public func defaultHeaders(with etag: String?) -> HTTPHeaders {
        guard let etag = etag else {
            return defaultHeaders
        }
        
        return defaultHeaders.merging([HTTPHeaderField.ifNoneMatch: etag]) { (_, new) in new }
    }
    
    func addHeaders(to request: inout URLRequest) {
        request.addValue(HTTPHeaderField.userAgent, forHTTPHeaderField: userAgent)
    }
    
}
