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
        /*
         Response: <NSHTTPURLResponse: 0x6000026c0140> { URL: https://login.microsoftonline.com/728892a0-4da9-4114-b511-52f75ee3bc3d/saml2?SAMLRequest=hVPRjpswEHy%2Fr0C8E2wCJFhJpDRR1UjXXpTk%2BtCXarGXnFWwqW16178%2FQ3JNTmpTJIS0npmdHS8zC03dsmXnntQOf3Zo3V0QvDS1smw4moedUUyDlZYpaNAyx9l%2B%2BfmeJSPCWqOd5roO35Fuc8BaNE5q1ZM263m4fnz4zoEg8HE5BSImaZrTSZHnohR0TChBSkgJeZXnwHOOhIDgiZhAUaQcaFZWNOu1vqKxXnYe%2Bi6DtrUdbpR1oJwvkiSNSBHR5ECmLMsYzb71qLUfWSpwA%2FPJudayOK71UapRI7nRVldOq1oqHHHdxJNkOi0SIFEqoIhSStOozCiNsqSaZIjjko9F3IeQ9OLbcz4fpBJSHW8HU55Aln06HLbR9mF%2F6CWWb3GttLJdg2aP5pfk%2BLi7v%2FjtLEYnz6LjP%2Fr3qAe7wG0cLrxMEMx6V2wIxSz%2BS2zQgQAH8Sy%2B5l2UWvbFT7BZb3Ut%2Be%2Bh3j8ftWnA%2FXtQOqJDRYqoGqCsU7ZFLiuJIvwjs6xr%2FbwyCA7noTMdhkH8rvl5WVEMq%2BuzcfjigpVuWjDS9neJL8DdefbL%2FNfwVe13cYfV4ua6csZ7nC9v%2FedZG9HfKnLf%2B2DAm9fGnUP6q%2FjJdXzD9uLu7fj6P1y8Ag%3D%3D&RelayState=dS5h4gOuXho66SoCdVkeyA9bDyI1RogEkHUMECV0 } { Status Code: 200, Headers {
             "Cache-Control" =     (
                 "no-store, no-cache"
             );
             "Content-Encoding" =     (
                 gzip
             );
             "Content-Length" =     (
                 14040
             );
             "Content-Type" =     (
                 "text/html; charset=utf-8"
             );
             Date =     (
                 "Thu, 12 Sep 2024 08:55:15 GMT"
             );
             Expires =     (
                 "-1"
             );
             Link =     (
                 "<https://aadcdn.msftauth.net>; rel=preconnect; crossorigin,<https://aadcdn.msftauth.net>; rel=dns-prefetch,<https://aadcdn.msauth.net>; rel=dns-prefetch"
             );
             P3P =     (
                 "CP=\"DSP CUR OTPi IND OTRi ONL FIN\""
             );
             Pragma =     (
                 "no-cache"
             );
             "Set-Cookie" =     (
                 "buid=0.AVcAoJKIcqlNFEG1EVL3XuO8PaSFW4aO72tOqP3HLHkghFzbAAA.AQABGgEAAAApTwJmzXqdR4BN2miheQMYzI7rIJUzcGXEjmSdhvxBzN9Df1PiRkuejsCTjau-vl0FhKsWtPMFZLXPxl5Z8Lj8XDXLZA-shkm4DmFPDPsY5OumGToZH3-32zku6DUHlRYgAA; expires=Sat, 12-Oct-2024 08:55:16 GMT; path=/; secure; HttpOnly; SameSite=None",
                 "esctx=PAQABBwEAAAApTwJmzXqdR4BN2miheQMY5tqEta2UFRqm2vucXwGRmdC_wcZa2jx4Hy9f8wwbeXE0jylPml2tuyo--ML5WlWAGirCcW2wrx0M_Wcz9uWVgm47-QLO4FWLeyxvwE8jt1K8o3At4ZgLV368f_UdZrmSMZU02Qt514Qn00LDTlSgM6LjE2_9EaygEfMLpeqydbggAA; domain=.login.microsoftonline.com; path=/; secure; HttpOnly; SameSite=None",
                 "esctx-MyRKGAt6bqg=AQABCQEAAAApTwJmzXqdR4BN2miheQMY1tYxxBd3UFIsIOw-5snsDNXHaAvn6Fx75xWVa2C_LZcj3QK6c1kJLM6gwFCEgUDUtfeK7pOMiiR8dW3Hd0gunFGRFiAvItfCaUuQaidNopmaQX9RNq3hRBBO0FbMZD8R4FWLa9-rEd6_zCPjZKYXDyAA; domain=.login.microsoftonline.com; path=/; secure; HttpOnly; SameSite=None",
                 "fpc=AqJ6vXBSNVJHt1EXLD2oB2l4NvSFAQAAAHOjdN4OAAAA; expires=Sat, 12-Oct-2024 08:55:16 GMT; path=/; secure; HttpOnly; SameSite=None",
                 "x-ms-gateway-slice=estsfd; path=/; secure; samesite=none; httponly",
                 "stsservicecookie=estsfd; path=/; secure; samesite=none; httponly"
             );
             "Strict-Transport-Security" =     (
                 "max-age=31536000; includeSubDomains"
             );
             Vary =     (
                 "Accept-Encoding"
             );
             "X-Content-Type-Options" =     (
                 nosniff
             );
             "X-DNS-Prefetch-Control" =     (
                 on
             );
             "X-Frame-Options" =     (
                 DENY
             );
             "X-XSS-Protection" =     (
                 0
             );
             "x-ms-ests-server" =     (
                 "2.1.18874.5 - SCUS ProdSlices"
             );
             "x-ms-request-id" =     (
                 "0821e789-2c00-4495-925e-cb4784a63200"
             );
             "x-ms-srs" =     (
                 "1.P"
             );
         } } Data size: 36639 bytes
         */
        let authService = DefaultAuthService(baseURL: baseURL)
        let codeChallenge = AuthCodesGenerator.codeChallenge(codeVerifier: AuthCodesGenerator.codeVerifier)!
        let result = try await authService.authorise(codeChallenge: codeChallenge)
        XCTAssertNotNil(result.location)
        XCTAssertNotNil(result.setCookie)
    }

    func testAuthoriseRealFailure() async throws { // TODO: Disable
        let authService = DefaultAuthService(baseURL: baseURL)
        do {
            _ = try await authService.authorise(codeChallenge: "")
        } catch {
            switch error {
            case AuthServiceError.authAPIError(let code, let desc):
                XCTAssertEqual(code, "invalid_authorization_request")
                XCTAssertEqual(desc, "One or more of the required parameters are missing or any provided parameters have invalid values.")
                break
            default:
                XCTFail("Wrong error")
                break
            }
        }
    }
}
