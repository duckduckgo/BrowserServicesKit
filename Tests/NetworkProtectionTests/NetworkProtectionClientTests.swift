//
//  NetworkProtectionClientTests.swift
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

import XCTest
@testable import NetworkProtection

final class NetworkProtectionClientTests: XCTestCase {
    var client: NetworkProtectionBackendClient!

    override func setUp() {
        super.setUp()
        client = NetworkProtectionBackendClient(environment: .default, isSubscriptionEnabled: false)
    }

    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        MockURLProtocol.stubs.removeAll()
        super.tearDown()
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testWhenDecodingServersResponse_AndServersDataIsValid_ThenResponseIsDecoded() throws {
        let data = TestData.mockServers
        let decodedServers = try JSONDecoder().decode([NetworkProtectionServer].self, from: data)
        XCTAssertEqual(decodedServers.count, 6)
    }

    // MARK: register

    func testRegister401Response_ThrowsInvalidTokenError() async {
        let emptyData = "".data(using: .utf8)!
        MockURLProtocol.stubs[client.redeemURL] = (response: HTTPURLResponse(url: client.registerKeyURL, statusCode: 401)!,
                                                   .success(emptyData))

        let body = RegisterKeyRequestBody(publicKey: .testData, serverSelection: .server(name: "MockServer"))
        let result = await client.register(authToken: "anAuthToken", requestBody: body)

        guard case .failure(let error) = result, case .invalidAuthToken = error else {
            XCTFail("Expected an invalidAuthToken error to be thrown")
            return
        }
    }

    // MARK: servers

    func testGetServer401Response_ThrowsInvalidTokenError() async {
        let emptyData = "".data(using: .utf8)!
        MockURLProtocol.stubs[client.redeemURL] = (response: HTTPURLResponse(url: client.serversURL, statusCode: 401)!,
                                                   .success(emptyData))

        let result = await client.getServers(authToken: "anAuthToken")

        guard case .failure(let error) = result, case .invalidAuthToken = error else {
            XCTFail("Expected an invalidAuthToken error to be thrown")
            return
        }
    }

    // MARK: redeem(inviteCode:)

    func testRedeemSuccess() async {
        let token = "a6s7ad6ad76aasa7s6a"
        let successData = redeemSuccessData(token: token)
        MockURLProtocol.stubs[client.redeemURL] = (response: HTTPURLResponse(url: client.redeemURL, statusCode: 200)!,
                                                   .success(successData))

        let result = await client.authenticate(withMethod: .inviteCode("DH76F8S"))

        XCTAssertEqual(try? result.get(), token)
    }

    func testRedeem400Response() async {
        let emptyData = "".data(using: .utf8)!
        MockURLProtocol.stubs[client.redeemURL] = (response: HTTPURLResponse(url: client.redeemURL, statusCode: 400)!,
                                                   .success(emptyData))

        let result = await client.authenticate(withMethod: .inviteCode("DH76F8S"))

        guard case .failure(let error) = result, case .invalidInviteCode = error else {
            XCTFail("Expected an invalidInviteCode error to be thrown")
            return
        }
    }

    func testRedeemNon200Or400Response() async {
        let emptyData = "".data(using: .utf8)!

        for code in [401, 304, 500] {
            MockURLProtocol.stubs[client.redeemURL] = (response: HTTPURLResponse(url: client.redeemURL, statusCode: code)!,
                                                       .success(emptyData))

            let result = await client.authenticate(withMethod: .inviteCode("DH76F8S"))

            guard case .failure(let error) = result, case .failedToRedeemInviteCode = error else {
                XCTFail("Expected a failedToRedeemInviteCode error to be thrown")
                return
            }
        }
    }

    func testRedeemDecodeFailure() async {
        let undecodableData = "sdfghj".data(using: .utf8)!
        MockURLProtocol.stubs[client.redeemURL] = (response: HTTPURLResponse(url: client.redeemURL, statusCode: 200)!,
                                                   .success(undecodableData))

        let result = await client.authenticate(withMethod: .inviteCode("DH76F8S"))

        guard case .failure(let error) = result, case .failedToParseRedeemResponse = error else {
            XCTFail("Expected a failedToRedeemInviteCode error to be thrown")
            return
        }
    }

    private func redeemSuccessData(token: String) -> Data {
        return """
        {
            "token": "\(token)"
        }
        """.data(using: .utf8)!
    }

    // MARK: locations(authToken:)

    func testLocationsSuccess() async {
        let successData = TestData.mockLocations
        MockURLProtocol.stubs[client.locationsURL] = (response: HTTPURLResponse(url: client.redeemURL, statusCode: 200)!,
                                                   .success(successData))

        let result = await client.getLocations(authToken: "DH76F8S")

        XCTAssertEqual(try? result.get().count, 2)
    }

    func testLocations401Response() async {
        let emptyData = "".data(using: .utf8)!
        MockURLProtocol.stubs[client.locationsURL] = (response: HTTPURLResponse(url: client.locationsURL, statusCode: 401)!,
                                                   .success(emptyData))

        let result = await client.getLocations(authToken: "DH76F8S")

        guard case .failure(let error) = result, case .invalidAuthToken = error else {
            XCTFail("Expected an invalidAuthToken error to be thrown")
            return
        }
    }

    func testLocationsNon200Or400Response() async {
        let emptyData = "".data(using: .utf8)!

        for code in [304, 500] {
            MockURLProtocol.stubs[client.locationsURL] = (response: HTTPURLResponse(url: client.locationsURL, statusCode: code)!,
                                                       .success(emptyData))

            let result = await client.getLocations(authToken: "DH76F8S")

            guard case .failure(let error) = result, case .failedToFetchLocationList = error else {
                XCTFail("Expected a failedToFetchLocationList error to be thrown")
                return
            }
        }
    }

    func testLocationsDecodeFailure() async {
        let undecodableData = "sdfghj".data(using: .utf8)!
        MockURLProtocol.stubs[client.locationsURL] = (response: HTTPURLResponse(url: client.redeemURL, statusCode: 200)!,
                                                   .success(undecodableData))

        let result = await client.getLocations(authToken: "DH76F8S")

        guard case .failure(let error) = result, case .failedToParseLocationListResponse = error else {
            XCTFail("Expected a failedToRedeemInviteCode error to be thrown")
            return
        }
    }
}

extension HTTPURLResponse {
    convenience init?(url: URL, statusCode: Int) {
        self.init(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
    }
}

extension PublicKey {
    static var testData: PublicKey {
        PublicKey(rawValue: "ZXCVBNMASDFGHJKLQWERTYUIOP123456".data(using: .utf8)!)!
    }
}
