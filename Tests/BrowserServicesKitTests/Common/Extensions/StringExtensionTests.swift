//
//  StringExtensionTests.swift
//  
//
//  Created by Sam Symons on 2022-02-26.
//

import Foundation

import XCTest
@testable import BrowserServicesKit

final class StringExtensionTests: XCTestCase {

    func testWhenNormalizingDiacritics_ThenDiacriticsAreRemoved() {
        let stringToNormalize = "àáâäãåāèéêëēėęîïíīįìôöòóōõûüùúū"
        let normalizedString = stringToNormalize.normalizingDiacritics()
        
        XCTAssertEqual(normalizedString, "aaaaaaaeeeeeeeiiiiiioooooouuuuu")
    }

}
