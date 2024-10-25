//
//  OAuthServiceTests.swift
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

import XCTest
import TestUtils
@testable import Networking

final class AuthServiceTests: XCTestCase {

    let baseURL = OAuthEnvironment.staging.url

    override func setUpWithError() throws {
        /*
         var mockedApiService = MockAPIService(decodableResponse: <#T##Result<any Decodable, any Error>#>,
         apiResponse: <#T##Result<(data: Data?, httpResponse: HTTPURLResponse), any Error>#>)
         */
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    var realAPISService: APIService {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let urlSession = URLSession(configuration: configuration,
                                    delegate: SessionDelegate(),
                                    delegateQueue: nil)
        return DefaultAPIService(urlSession: urlSession)
    }

    // MARK: - Authorise

    func test_real_AuthoriseSuccess() async throws { // TODO: Disable
        let authService = DefaultOAuthService(baseURL: baseURL, apiService: realAPISService)
        let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: OAuthCodesGenerator.codeVerifier)!
        let result = try await authService.authorise(codeChallenge: codeChallenge)
        XCTAssertNotNil(result)
    }

    func test_real_AuthoriseFailure() async throws { // TODO: Disable
        let authService = DefaultOAuthService(baseURL: baseURL, apiService: realAPISService)
        do {
            _ = try await authService.authorise(codeChallenge: "")
        } catch {
            switch error {
            case OAuthServiceError.authAPIError(let code, let desc):
                XCTAssertEqual(code, "invalid_authorization_request")
                XCTAssertEqual(desc, "One or more of the required parameters are missing or any provided parameters have invalid values")
            default:
                XCTFail("Wrong error")
            }
        }
    }

    func test_real_GetJWTSigner() async throws { // TODO: Disable
        let authService = DefaultOAuthService(baseURL: baseURL, apiService: realAPISService)
        let signer = try await authService.getJWTSigners()
        do {
            let _: JWTAccessToken = try signer.verify("sdfgdsdzfgsdf")
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
