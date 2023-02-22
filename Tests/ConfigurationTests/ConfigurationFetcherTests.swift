//
//  ConfigurationFetcherTests.swift
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

import XCTest
@testable import Configuration
@testable import API
@testable import TestUtils

final class ConfigurationFetcherTests: XCTestCase {
    
    enum MockError: Error {
        case someError
    }
    
    override class func setUp() {
        APIHeaders.setUserAgent("")
        Configuration.setURLProvider(MockConfigurationURLProvider())
    }
    
    func makeConfigurationFetcher(store: ConfigurationStoring = MockStore(),
                                  validator: ConfigurationValidating = MockValidator()) -> ConfigurationFetcher {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return ConfigurationFetcher(store: store,
                                    validator: validator,
                                    urlSession: URLSession(configuration: testConfiguration))
    }
    
    func testWhenOneAssetFailsToFetchThenOtherIsNotStored() async {
        MockURLProtocol.requestHandler = { request in
            if let url = request.url, url == Configuration.bloomFilterBinary.url {
                return (HTTPURLResponse.internalServerError, nil)
            } else {
                return (HTTPURLResponse.ok, Data("Bloom Filter Spec".utf8))
            }
        }
        let store = MockStore()
        let fetcher = makeConfigurationFetcher(store: store)
        do {
            try await fetcher.fetch([.bloomFilterBinary, .bloomFilterSpec])
            XCTFail("Expected an error to be thrown")
        } catch {}
        XCTAssertNil(store.loadData(for: .bloomFilterBinary))
        XCTAssertNil(store.loadData(for: .bloomFilterSpec))
    }
    
    let privacyConfigurationData = Data("Privacy Config".utf8)
    
    func testWhenValidateDataFailsThenErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let validatorMock = MockValidator()
        validatorMock.throwError = true
    
        let fetcher = makeConfigurationFetcher(validator: validatorMock)
        do {
            try await fetcher.fetch([.privacyConfiguration])
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let fetcherError = error as? ConfigurationFetcher.Error,
                  case .invalidPayload = fetcherError else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }
    
    func testWhenEtagAndDataAreStoredThenResponseIsStored() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, self.privacyConfigurationData) }
        let oldEtag = UUID().uuidString
        let oldData = Data()
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (oldEtag, oldData)

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch([.privacyConfiguration])
        
        XCTAssertEqual(store.loadData(for: .privacyConfiguration), self.privacyConfigurationData)
        XCTAssertEqual(store.loadEtag(for: .privacyConfiguration), HTTPURLResponse.testEtag)
    }
    
    func testWhenNoEtagIsStoredThenResponseIsStored() async throws {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        let fetcher = makeConfigurationFetcher(store: store)
        try await fetcher.fetch([.privacyConfiguration])
        XCTAssertEqual(store.loadData(for: .privacyConfiguration), self.privacyConfigurationData)
        XCTAssertEqual(store.loadEtag(for: .privacyConfiguration), HTTPURLResponse.testEtag)
    }
    
    func testWhenEtagIsStoredButStoreHasNoDataThenResponseIsStored() async throws {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (HTTPURLResponse.testEtag, nil)
        
        let fetcher = makeConfigurationFetcher(store: store)
        try await fetcher.fetch([.privacyConfiguration])
        
        XCTAssertNotNil(store.loadData(for: .privacyConfiguration))
    }
    
    func testWhenStoringDataFailsThenEtagIsNotStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        store.defaultSaveData = { _, _ in throw MockError.someError }

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch([.privacyConfiguration])

        XCTAssertNil(store.loadData(for: .privacyConfiguration))
        XCTAssertNil(store.loadEtag(for: .privacyConfiguration))
    }
    
    func testWhenStoringEtagFailsThenEtagIsNotStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        store.defaultSaveEtag = { _, _ in throw MockError.someError }
        
        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch([.privacyConfiguration])
        
        XCTAssertNil(store.loadEtag(for: .privacyConfiguration))
    }
    
    func testWhenResponseIsNotModifiedThenNoDataStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.notModified, nil) }
        let store = MockStore()
        
        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch([.privacyConfiguration])
        
        XCTAssertNil(store.loadEtag(for: .privacyConfiguration))
        XCTAssertNil(store.loadData(for: .privacyConfiguration))
    }
    
    func testWhenEtagAndDataStoredThenEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, Data())
        
        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch([.privacyConfiguration])
        
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch), etag)
    }
    
    func testWhenNoEtagStoredThenNoEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (nil, Data())
        
        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch([.privacyConfiguration])
        
        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch))
    }
    
    func testWhenNoDataStoredThenNoEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, nil)
        
        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch([.privacyConfiguration])
        
        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch))
    }
    
    func testWhenEtagProvidedThenItIsAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, Data())
        
        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch([.privacyConfiguration])
        
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch), etag)
    }
    
    func testWhenEmbeddedEtagAndExternalEtagProvidedThenExternalAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let embeddedEtag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, Data())
        store.configToEmbeddedEtag[.privacyConfiguration] = embeddedEtag
        
        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch([.privacyConfiguration])
        
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch), etag)
    }
    
}
