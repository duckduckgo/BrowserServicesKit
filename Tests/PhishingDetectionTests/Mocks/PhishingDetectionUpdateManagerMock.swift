//
//  PhishingDetectionUpdateManagerMock.swift
//
//
//
//

import Foundation
import PhishingDetection

public class MockPhishingDetectionUpdateManager: PhishingDetectionUpdateManaging {
    var didUpdateFilterSet = false
    var didUpdateHashPrefixes = false
    var completionHandler: (() -> Void)?
    
    public func updateFilterSet() async {
        didUpdateFilterSet = true
        checkCompletion()
    }

    public func updateHashPrefixes() async {
        didUpdateHashPrefixes = true
        checkCompletion()
    }

    private func checkCompletion() {
        if didUpdateFilterSet && didUpdateHashPrefixes {
            completionHandler?()
        }
    }
    
}
