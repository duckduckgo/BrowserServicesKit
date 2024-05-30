//
//  PhishingDetectionDataProviderMock.swift
//
//
//  Created by Thom on 29/05/2024.
//

import Foundation
import PhishingDetection

public class MockPhishingDetectionDataProvider: PhishingDetectionDataProviderProtocol {
    public var loadFilterSetCalled = false
    public var loadHashPrefixesCalled = false
    
    public var embeddedFilterSet: Set<Filter> {
        return self.loadFilterSet()
    }
    
    public var embeddedHashPrefixes: Set<String> {
        return self.loadHashPrefixes()
    }
    
    func loadFilterSet() -> Set<Filter> {
        self.loadFilterSetCalled = true
        return []
    }
    
    func loadHashPrefixes() -> Set<String> {
        self.loadHashPrefixesCalled = true
        return []
    }
    
}
