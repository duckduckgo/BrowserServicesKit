//
//  Configuration.swift
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

final class ConfigurationTests: XCTestCase {
    
    let configurationFetcher: ConfigurationFetcher = {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return ConfigurationFetcher(store: MockStore(),
                                    onDidStore: {},
                                    urlSession: URLSession(configuration: testConfiguration),
                                    userAgent: "")
    }()
    
    enum MockError: Error {
        case whatever
    }
    
    func testExample() async throws {
        
//        MockURLProtocol.requestHandler = { request in
//
//            if let url = request.url, url == Configuration.bloomFilter.url {
//                throw WTFError.whatever
//            } else {
//                let response = HTTPURLResponse(url: Configuration.bloomFilterSpec.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
//                return (response, ata())
//            }
//        }
//
//        do {
//            try await configurationFetcher.fetch([.init(configuration: .bloomFilter),
//                                                  .init(configuration: .bloomFilterSpec)])
//        } catch let error {
//            print(":(")
//        }
//
        // testWhenThereIsNoResponseThenThereIsNothingToUpdate
        // testWhenNoEtagIsPresentThenResponseIsStored
        // testWhenEtagIsPresentThenResponseIsStoredOnlyWhenNeeded
        // testWhenEtagIsMissingThenResponseIsNotStored
        // testWhenStoringFailsThenEtagIsNotStored
        // testWhenEtagIsPresentButStoreHasNoDataThenResponseIsStored
        
        
    }
    
    func testWhenThereIsNoResponseThenThereIsNothingToUpdate() async throws {
        MockURLProtocol.requestHandler = { _ in throw MockError.whatever }
        do {
            try await configurationFetcher.fetch([.init(configuration: .privacyConfig)])
            XCTFail("Fetch did not throw an error")
        } catch { }
        // todo: here?
    }
    
    /*
     func testWhenNoEtagIsPresentThenResponseIsStored() {
         
         mockRequest.mockResponse = .success(etag: "test", data: Data())
         
         let loader = ContentBlockerLoader(etagStorage: mockEtagStorage)
         XCTAssertTrue(loader.checkForUpdates(dataSource: mockRequest))
         
         XCTAssertEqual(mockEtagStorage.etags[.surrogates], nil)
         
         loader.applyUpdate(to: mockStorageCache)
         
         XCTAssertEqual(mockEtagStorage.etags[.surrogates], "test")
         XCTAssertNotNil(mockStorageCache.processedUpdates[.surrogates])
     }
     */
    
//    func testWhenNoEtagIsPresentThenResponseIsStored() async throws {
//            try await configurationFetcher.fetch([.init(configuration: .privacyConfig)])
//            XCTFail("Fetch did not throw an error")
//        } catch { }
//    }

}
