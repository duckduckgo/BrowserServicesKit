//
//  ExpireFirstPartyCookieReferenceTests.swift
//  
//
//  Created by Fernando Bunn on 05/12/2022.
//

import XCTest

final class ExpireFirstPartyCookieReferenceTests: XCTestCase {

    private enum Resource {
        static let config = "Resources/privacy-reference-tests/expire-first-party-js-cookies/config_reference.json"
        static let tests = "Resources/privacy-reference-tests/expire-first-party-js-cookies/tests.json"
    }
    
    func testExample() throws {
        let data = JsonTestDataLoader()
        let configData = data.fromJsonFile(Resource.config)
        
        let testData = data.fromJsonFile(Resource.tests)
        let tests =  try JSONDecoder().decode(TestData.self, from: testData).expireFirstPartyTrackingCookies.tests

        for test in tests {
            let cookieProperties = test.setDocumentCookie
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .reduce(into: [String: String]()) { result, item in
                    let keyValue = item.split(separator: "=")
                    
                    if let key = keyValue.first,
                       let value = keyValue.last  {
                        result[String(key.lowercased())] = String(value)
                    }
                }
        
            
            let cookie = cookieForProperties(cookieProperties, name: test.name)
            print("COOKIE \(cookie)")
        }
 
    }

    private func cookieForProperties(_ properties: [String: String], name: String) -> HTTPCookie? {
        var cookieProperties = [HTTPCookiePropertyKey: Any]()
        
        if let path = properties["path"] {
            cookieProperties[.path] = path
        }
        
        
        if let value = properties["foo"] {
            cookieProperties[.value] = value
        }
        
        if let expiry = properties["max-age"] {
            cookieProperties[.expires] = NSDate(timeIntervalSinceNow: 31556926)
        }
        
        if let domain = properties["domain"] {
            cookieProperties[.domain] = domain
        }
        
        if let _ = properties["secure"] {
            cookieProperties[.secure] = true
        }
        
        cookieProperties[.name] = name
        
      //  print("PROPERT \(cookieProperties)")
        
        return HTTPCookie(properties: cookieProperties)
    }
    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}

// MARK: - TestData
private struct TestData: Codable {
    let expireFirstPartyTrackingCookies: ExpireFirstPartyTrackingCookies
}

// MARK: - ExpireFirstPartyTrackingCookies
private struct ExpireFirstPartyTrackingCookies: Codable {
    let name, desc: String
    let tests: [Test]
}

// MARK: - Test
private struct Test: Codable {
    let name: String
    let siteURL: String
    let scriptURL: String
    let setDocumentCookie: String
    let expectCookieSet: Bool
    let expectExpiryToBe: Int?
    let exceptPlatforms: [String]
}
