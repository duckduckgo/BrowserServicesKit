//
//  TLDTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
@testable import BrowserServicesKit

final class TLDTests: XCTestCase {

    let tld = TLD()

    func testWhenJsonAccessedThenReturnsValidJson() {
        let tlds = try? JSONDecoder().decode([String].self, from: tld.json.data(using: .utf8)!)

        XCTAssertNotNil(tlds)
        XCTAssertFalse(tlds?.isEmpty ?? true)
    }

    func testWhenHostMultiPartTopLevelWithSubdomainThenDomainCorrect() {
        XCTAssertEqual("bbc.co.uk", tld.domain("www.bbc.co.uk"))
        XCTAssertEqual("bbc.co.uk", tld.domain("other.bbc.co.uk"))
        XCTAssertEqual("bbc.co.uk", tld.domain("multi.part.bbc.co.uk"))
    }

    func testWhenHostDotComWithSubdomainThenDomainIsTopLevel() {
        XCTAssertEqual("example.com", tld.domain("www.example.com"))
        XCTAssertEqual("example.com", tld.domain("other.example.com"))
        XCTAssertEqual("example.com", tld.domain("multi.part.example.com"))
    }

    func testWhenHostIsTopLevelDotComThenDomainIsSame() {
        XCTAssertEqual("example.com", tld.domain("example.com"))
    }
    
    func testWhenHostIsMalformedThenDomainIsFixed() {
        XCTAssertEqual("example.com", tld.domain(".example.com"))
    }
    
    func testWhenHostMultiPartTopLevelWithSubdomainThenETLDp1Correct() {
        XCTAssertEqual("bbc.co.uk", tld.eTLDplus1("www.bbc.co.uk"))
        XCTAssertEqual("bbc.co.uk", tld.eTLDplus1("other.bbc.co.uk"))
        XCTAssertEqual("bbc.co.uk", tld.eTLDplus1("multi.part.bbc.co.uk"))
    }

    func testWhenHostDotComWithSubdomainThenETLDp1Correct() {
        XCTAssertEqual("example.com", tld.eTLDplus1("www.example.com"))
        XCTAssertEqual("example.com", tld.eTLDplus1("other.example.com"))
        XCTAssertEqual("example.com", tld.eTLDplus1("multi.part.example.com"))
    }

    func testWhenHostIsTLDLevelThenETLDp1IsNotFound() {
        XCTAssertEqual(nil, tld.eTLDplus1("com"))
        XCTAssertEqual(nil, tld.eTLDplus1("co.uk"))
    }
    
    func testWhenHostIsIncorrectThenETLDp1IsNotFound() {
        XCTAssertEqual(nil, tld.eTLDplus1("abcderfg"))
    }
    
    func testWhenHostIsNilDomainIsNil() {
        XCTAssertNil(tld.domain(nil))
    }
    
    func testWhenHostIsTLDThenDomainIsFound() {
        XCTAssertEqual("com", tld.domain("com"))
        XCTAssertEqual("co.uk", tld.domain("co.uk"))
    }
    
    func testWhenHostIsIncorrectThenDomainIsNil() {
        XCTAssertNil(tld.domain("abcdefgh"))
    }

    func testWhenTLDInstantiatedThenLoadsTLDData() {
        XCTAssertFalse(tld.tlds.isEmpty)
    }

}
