//
//  MockPhishingDetectionUpdateManager.swift
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

import Foundation
@testable import MaliciousSiteProtection

class MockPhishingDetectionUpdateManager: MaliciousSiteProtection.MaliciousSiteUpdateManaging {
    var didUpdateFilterSet = false
    var didUpdateHashPrefixes = false
    var startPeriodicUpdatesCalled = false
    var completionHandler: (() -> Void)?
    var updateDataForDatasetTypeCalled = false
    var capturedUpdateDatasetType: DataManager.StoredDataType.Kind?

    var lastHashPrefixSetUpdateDate: Date = .distantPast
    var lastFilterSetUpdateDate: Date = .distantPast

    func updateData(for key: some MaliciousSiteProtection.MaliciousSiteDataKey) async {
        switch key.dataType {
        case .filterSet: await updateFilterSet()
        case .hashPrefixSet: await updateHashPrefixes()
        }
    }

    func updateFilterSet() async {
        didUpdateFilterSet = true
        checkCompletion()
    }

    func updateHashPrefixes() async {
        didUpdateHashPrefixes = true
        checkCompletion()
    }

    func checkCompletion() {
        if didUpdateFilterSet && didUpdateHashPrefixes {
            completionHandler?()
        }
    }

    public func startPeriodicUpdates() -> Task<Void, any Error> {
        startPeriodicUpdatesCalled = true
        return Task {}
    }

    public func updateData(datasetType: DataManager.StoredDataType.Kind) -> Task<Void, any Error> {
        updateDataForDatasetTypeCalled = true
        capturedUpdateDatasetType = datasetType
        return Task {}
    }
}
