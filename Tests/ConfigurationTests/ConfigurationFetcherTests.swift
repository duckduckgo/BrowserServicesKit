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

final class ConfigurationFetcherTests: XCTestCase {
    
    func makeConfigurationFetcher(with store: ConfigurationStoring) -> ConfigurationFetcher {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return ConfigurationFetcher(store: store,
                                    onDidStore: {},
                                    urlSession: URLSession(configuration: testConfiguration),
                                    userAgent: "")
    }
    
    enum MockError: Error {
        case someError
    }
    
    // Server responses handling logic
    
    func testWhenUrlSessionThrowsErrorThenWrappedUrlSessionErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in throw MockError.someError }
        let fetcher = makeConfigurationFetcher(with: MockStore())
        do {
            try await fetcher.fetch([.init(configuration: .privacyConfig)])
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let fetcherError = error as? ConfigurationFetcher.Error,
                  case .urlSession = fetcherError else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }
    
    func testWhenThereIsNoResponseThenEmptyDataErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, nil) }
        let fetcher = makeConfigurationFetcher(with: MockStore())
        do {
            try await fetcher.fetch([.init(configuration: .privacyConfig)])
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let fetcherError = error as? ConfigurationFetcher.Error,
                  case .emptyData = fetcherError else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }
    
    let privacyConfigData = Data("Privacy Config".utf8)
    
    func testWhenEtagIsMissingInResponseThenMissingEtagErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.okNoEtag, self.privacyConfigData) }
        let fetcher = makeConfigurationFetcher(with: MockStore())
        do {
            try await fetcher.fetch([.init(configuration: .privacyConfig)])
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let fetcherError = error as? ConfigurationFetcher.Error,
                  case .missingEtagInResponse = fetcherError else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }
    
    func testWhenInternalServerErrorThenInvalidStatusCodeErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let fetcher = makeConfigurationFetcher(with: MockStore())
        do {
            try await fetcher.fetch([.init(configuration: .privacyConfig)])
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let fetcherError = error as? ConfigurationFetcher.Error,
                  case .invalidStatusCode = fetcherError else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }
    
    func testWhenOneAssetFailsToFetchThenOtherIsNotStored() async {
        MockURLProtocol.requestHandler = { request in
            if let url = request.url, url == Configuration.bloomFilter.url {
                return (HTTPURLResponse.internalServerError, nil)
            } else {
                return (HTTPURLResponse.ok, Data("Bloom Filter Spec".utf8))
            }
        }
        let store = MockStore()
        let fetcher = makeConfigurationFetcher(with: store)
        do {
            try await fetcher.fetch([.init(configuration: .bloomFilter),
                                     .init(configuration: .bloomFilterSpec)])
            XCTFail("Expected an error to be thrown")
        } catch {}
        XCTAssertNil(store.loadData(for: .bloomFilter))
        XCTAssertNil(store.loadData(for: .bloomFilterSpec))
    }
    
    // -
    
    func testWhenEtagAndDataAreStoredThenResponseIsStored() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, self.privacyConfigData) }
        let oldEtag = UUID().uuidString
        let oldData = Data()
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfig] = (oldEtag, oldData)

        let fetcher = makeConfigurationFetcher(with: store)
        try? await fetcher.fetch([.init(configuration: .privacyConfig)])
        
        XCTAssertEqual(store.loadData(for: .privacyConfig), self.privacyConfigData)
        XCTAssertEqual(store.loadEtag(for: .privacyConfig), HTTPURLResponse.testEtag)
    }
    
    func testWhenNoEtagIsStoredThenResponseIsStored() async throws {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigData) }
        let store = MockStore()
        let fetcher = makeConfigurationFetcher(with: store)
        try await fetcher.fetch([.init(configuration: .privacyConfig)])
        XCTAssertEqual(store.loadData(for: .privacyConfig), self.privacyConfigData)
        XCTAssertEqual(store.loadEtag(for: .privacyConfig), HTTPURLResponse.testEtag)
    }
    
    func testWhenEtagIsStoredButStoreHasNoDataThenResponseIsStored() async throws {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigData) }
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfig] = (HTTPURLResponse.testEtag, nil)
        
        let fetcher = makeConfigurationFetcher(with: store)
        try await fetcher.fetch([.init(configuration: .privacyConfig)])
        
        XCTAssertNotNil(store.loadData(for: .privacyConfig))
    }
    
    func testWhenStoringDataFailsThenEtagIsNotStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigData) }
        let store = MockStore()
        store.defaultSaveData = { _, _ in throw MockError.someError }

        let fetcher = makeConfigurationFetcher(with: store)
        try? await fetcher.fetch([.init(configuration: .privacyConfig)])

        XCTAssertNil(store.loadData(for: .privacyConfig))
        XCTAssertNil(store.loadEtag(for: .privacyConfig))
    }
    
    func testWhenStoringEtagFailsThenEtagIsNotStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigData) }
        let store = MockStore()
        store.defaultSaveEtag = { _, _ in throw MockError.someError }
        
        let fetcher = makeConfigurationFetcher(with: store)
        try? await fetcher.fetch([.init(configuration: .privacyConfig)])
        
        XCTAssertNil(store.loadEtag(for: .privacyConfig))
    }
    
    func testWhenResponseIsNotModifiedThenNoDataStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.notModified, self.privacyConfigData) }
        let store = MockStore()
        
        let fetcher = makeConfigurationFetcher(with: store)
        try? await fetcher.fetch([.init(configuration: .privacyConfig)])
        
        XCTAssertNil(store.loadEtag(for: .privacyConfig))
    }
    
    func testWhenEtagAndDataStoredThenEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfig] = (etag, Data())
        
        let fetcher = makeConfigurationFetcher(with: store)
        try? await fetcher.fetch([.init(configuration: .privacyConfig)])
        
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch), etag)
    }
    
    func testWhenNoEtagStoredThenNoEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfig] = (nil, Data())
        
        let fetcher = makeConfigurationFetcher(with: store)
        try? await fetcher.fetch([.init(configuration: .privacyConfig)])
        
        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch))
    }
    
    func testWhenNoDataStoredThenNoEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfig] = (etag, nil)
        
        let fetcher = makeConfigurationFetcher(with: store)
        try? await fetcher.fetch([.init(configuration: .privacyConfig)])
        
        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch))
    }
    
    func testWhenEtagProvidedThenItIsAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfig] = (etag, Data())
        
        let fetcher = makeConfigurationFetcher(with: store)
        try? await fetcher.fetch([.init(configuration: .privacyConfig)])
        
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch), etag)
    }
    
    func testWhenEmbeddedEtagAndExternalEtagProvidedThenExternalAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let embeddedEtag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfig] = (etag, Data())
        store.configToEmbeddedEtag[.privacyConfig] = embeddedEtag
        
        let fetcher = makeConfigurationFetcher(with: store)
        try? await fetcher.fetch([.init(configuration: .privacyConfig)])
        
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch), etag)
    }
    
}
