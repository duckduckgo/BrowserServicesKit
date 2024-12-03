//
//  CrashCollectionTests.swift
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

@testable import Crashes
import MetricKit
import XCTest
import Persistence
import TestUtils

class CrashCollectionTests: XCTestCase {

    func testFirstCrashFlagSent() {
        let crashCollection = CrashCollection(crashReportSender: CrashReportSender(platform: .iOS), crashCollectionStorage:  MockKeyValueStore())
        // 2 pixels with first = true attached
        XCTAssertTrue(crashCollection.isFirstCrash)
        crashCollection.start { pixelParameters, _, _ in
            let firstFlags = pixelParameters.compactMap { $0["first"] }
            XCTAssertFalse(firstFlags.isEmpty)
        }
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])
        XCTAssertFalse(crashCollection.isFirstCrash)
    }

    func testSubsequentPixelsDontSendFirstFlag() {
        let crashCollection = CrashCollection(crashReportSender: CrashReportSender(platform: .iOS), crashCollectionStorage:  MockKeyValueStore())
        // 2 pixels with no first parameter
        crashCollection.isFirstCrash = false
        crashCollection.start { pixelParameters, _, _ in
            let firstFlags = pixelParameters.compactMap { $0["first"] }
            XCTAssertTrue(firstFlags.isEmpty)
        }
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])
        XCTAssertFalse(crashCollection.isFirstCrash)
    }
    
    func testCRCIsReceivedAndUpdated()
    {
        let expectedCRCID = "Test CRCID Value"
        let store = MockKeyValueStore()
        
        let crashCollection = CrashCollection(crashReportSender: MockCrashReportSender(platform: .iOS), crashCollectionStorage: store)
        
        let expectation = self.expectation(description: "Crash collection response")
        
        crashCollection.start(process: {_ in
            return ["json-data".data(using: .utf8)!]
        }) { pixelParameters, payloads, uploadReports in
            uploadReports()
        } didFinishHandlingResponse: {
            expectation.fulfill()
        }

        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])
        
        self.wait(for: [expectation], timeout: 5)
        
        XCTAssertEqual(store.object(forKey: CrashCollection.Const.crcidKey) as? String, expectedCRCID)
    }
}

class MockPayload: MXDiagnosticPayload {

    var mockCrashes: [MXCrashDiagnostic]?

    init(mockCrashes: [MXCrashDiagnostic]?) {
        self.mockCrashes = mockCrashes
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var crashDiagnostics: [MXCrashDiagnostic]? {
        return mockCrashes
    }
}

class MockCrashReportSender: CrashReportSending {
    
    let platform: CrashCollectionPlatform
    
    required init(platform: CrashCollectionPlatform) {
        self.platform = platform
        
    }
    
    func send(_ crashReportData: Data, crcid: String?, completion: @escaping (Result<Data?, Error>) -> Void) {
        completion(.success(nil)) // TODO: Pass some data?
    }
    
    func send(_ crashReportData: Data, crcid: String?) async -> Result<Data?, Error> {
        await withCheckedContinuation { continuation in
            send(crashReportData, crcid: crcid) { result in
                continuation.resume(returning: result)
            }
        }
    }
}
