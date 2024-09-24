//
//  AuthServiceTests.swift
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

    let baseURL = URL(string: "https://quackdev.duckduckgo.com")!

    override func setUpWithError() throws {
/*
 var mockedApiService = MockAPIService(decodableResponse: <#T##Result<any Decodable, any Error>#>,
                                       apiResponse: <#T##Result<(data: Data?, httpResponse: HTTPURLResponse), any Error>#>)
 */
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - Authorise

    func testAuthoriseRealSuccess() async throws { // TODO: Disable
        let authService = DefaultOAuthService(baseURL: baseURL)
        let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: OAuthCodesGenerator.codeVerifier)!
        let result = try await authService.authorise(codeChallenge: codeChallenge)
        XCTAssertNotNil(result)
    }

    func testAuthoriseRealFailure() async throws { // TODO: Disable
        let authService = DefaultOAuthService(baseURL: baseURL)
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

    func testGetJWTSigner() async throws { // TODO: Disable
        let authService = DefaultOAuthService(baseURL: baseURL)
        let signer = try await authService.getJWTSigners()
        do {
            let _: OAuthAccessToken = try signer.verify("sdfgdsdzfgsdf")
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
