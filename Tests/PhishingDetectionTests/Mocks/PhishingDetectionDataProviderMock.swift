//
//  PhishingDetectionDataProviderMock.swift
//
//
//  Created by Thom on 29/05/2024.
//

import Foundation
import PhishingDetection

public class MockPhishingDetectionDataProvider: PhishingDetectionDataProviding {
    public var embeddedRevision: Int = 0
    var loadHashPrefixesCalled: Bool = false
    var loadFilterSetCalled: Bool = true
    
    public func loadEmbeddedFilterSet() -> Set<PhishingDetection.Filter> {
        self.loadHashPrefixesCalled = true
        return []
    }
    
    public func loadEmbeddedHashPrefixes() -> Set<String> {
        self.loadFilterSetCalled = true
        return []
    }
    
}
