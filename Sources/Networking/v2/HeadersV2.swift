//
//  HeadersV2.swift
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

public extension APIRequestV2 {

    struct HeadersV2 {

        private var userAgent: String?
        let acceptEncoding: String = "gzip;q=1.0, compress;q=0.5"
        let acceptLanguage: String = {
            let languages = Locale.preferredLanguages.prefix(6)
            return languages.enumerated().map { index, language in
                let q = 1.0 - (Double(index) * 0.1)
                return "\(language);q=\(q)"
            }.joined(separator: ", ")
        }()
        let etag: String?
        let cookies: [HTTPCookie]?
        let authToken: String?
        let additionalHeaders: [String: String]?

        public init(userAgent: String? = nil,
                    etag: String? = nil,
                    cookies: [HTTPCookie]? = nil,
                    authToken: String? = nil,
                    additionalHeaders: [String: String]? = nil) {
            self.userAgent = userAgent
            self.etag = etag
            self.cookies = cookies
            self.authToken = authToken
            self.additionalHeaders = additionalHeaders
        }

        public var httpHeaders: [String: String] {
            var headers = [
                HTTPHeaderKey.acceptEncoding: acceptEncoding,
                HTTPHeaderKey.acceptLanguage: acceptLanguage
            ]
            if let userAgent {
                headers[HTTPHeaderKey.userAgent] = userAgent
            }
            if let etag {
                headers[HTTPHeaderKey.ifNoneMatch] = etag
            }
            if let cookies, cookies.isEmpty == false {
                let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
                headers.merge(cookieHeaders) { lx, _ in
                    assertionFailure("Duplicated values in HTTPHeaders")
                    return lx
                }
            }
            if let authToken {
                headers[HTTPHeaderKey.authorization] = "Bearer \(authToken)"
            }
            if let additionalHeaders {
                headers.merge(additionalHeaders) { old, _ in old }
            }
            return headers
        }

    }

}
