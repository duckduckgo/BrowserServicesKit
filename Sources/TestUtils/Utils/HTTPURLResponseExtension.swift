//
//  HTTPURLResponseExtension.swift
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
import Networking

extension HTTPURLResponse {

    static let testEtag = "test-etag"
    static let testUrl = URL(string: "http://www.example.com")!

    static let ok = HTTPURLResponse(url: testUrl,
                                    statusCode: 200,
                                    httpVersion: nil,
                                    headerFields: [APIRequest.HTTPHeaderField.etag: testEtag])!

    static let okNoEtag = HTTPURLResponse(url: testUrl,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: [:])!

    static let notModified = HTTPURLResponse(url: testUrl,
                                             statusCode: 304,
                                             httpVersion: nil,
                                             headerFields: [APIRequest.HTTPHeaderField.etag: testEtag])!

    static let internalServerError = HTTPURLResponse(url: testUrl,
                                                     statusCode: 500,
                                                     httpVersion: nil,
                                                     headerFields: [:])!

}
