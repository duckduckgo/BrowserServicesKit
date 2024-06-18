//
//  PhishingDetectionDataActivities.swift
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
import PhishingDetection

public class MockPhishingDetector: PhishingDetecting {
    private var mockClient: PhishingDetectionClientProtocol
    public var hashPrefixes: Set<String> = Set()
    private var currentRevision = 0
    public var filterSet: Set<Filter> = Set()
    public var didUpdateHashPrefixes: Bool = false
    public var didUpdateFilterSet: Bool = false
    public var didCallIsMalicious: Bool = false
    var completionHandler: (() -> Void)?

    init() {
        self.mockClient = MockPhishingDetectionClient()
    }

    public func updateFilterSet() async {
        let response = await mockClient.getFilterSet(revision: currentRevision)
        if response.replace {
            currentRevision = response.revision
            filterSet = Set(response.insert)
        } else {
            currentRevision = response.revision
            response.insert.forEach { self.filterSet.insert($0) }
            response.delete.forEach { self.filterSet.remove($0) }
        }
        didUpdateFilterSet = true
        checkCompletion()
    }

    public func updateHashPrefixes() async {
        let response = await mockClient.getHashPrefixes(revision: currentRevision)
        if response.replace {
            currentRevision = response.revision
            hashPrefixes = Set(response.insert)
        } else {
            currentRevision = response.revision
            response.insert.forEach { self.hashPrefixes.insert($0) }
            response.delete.forEach { self.hashPrefixes.remove($0) }
        }
        didUpdateHashPrefixes = true
        checkCompletion()
    }
    
    private func checkCompletion() {
        if didUpdateFilterSet && didUpdateHashPrefixes {
            completionHandler?()
        }
    }

    public func getMatches(hashPrefix: String) async -> Set<Match> {
        let matches = await mockClient.getMatches(hashPrefix: hashPrefix)
        return Set(matches)
    }

    public func isMalicious(url: URL) async -> Bool {
        return url.absoluteString.contains("malicious")
    }
    
    public func loadData() {
        didUpdateHashPrefixes = true
        didUpdateFilterSet = true
        return
    }
    
    public func writeData() {
        return
    }
}
