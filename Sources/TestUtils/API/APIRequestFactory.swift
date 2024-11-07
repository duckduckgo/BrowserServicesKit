//
//  APIRequestFactory.swift
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
@testable import Subscription
@testable import Networking

public struct APIRequestFactory {

    public static func makeAuthoriseRequest(destinationMockAPIService apiService: MockAPIService, success: Bool) {
        let authoriseRequest = OAuthRequest.authorize(baseURL: OAuthEnvironment.staging.url, codeChallenge: "codeChallenge")!
        let authoriseRequestHost = authoriseRequest.apiRequest.host
        if success {
            let authoriseResponseData = Data()
            let httpResponse = HTTPURLResponse(url: authoriseRequest.apiRequest.urlRequest.url!,
                                               statusCode: authoriseRequest.httpSuccessCode.rawValue,
                                               httpVersion: nil,
                                               headerFields: [:])!
            let response = APIResponseV2(data: authoriseResponseData, httpResponse: httpResponse)
            apiService.setResponse(for: authoriseRequestHost, response: response)
        } else {
            let httpResponse = HTTPURLResponse(url: authoriseRequest.apiRequest.urlRequest.url!,
                                               statusCode: authoriseRequest.httpErrorCodes.first!.rawValue,
                                               httpVersion: nil,
                                               headerFields: [:])!
            let response = APIResponseV2(data: nil, httpResponse: httpResponse)
            apiService.setResponse(for: authoriseRequestHost, response: response)
        }
    }

    
}
