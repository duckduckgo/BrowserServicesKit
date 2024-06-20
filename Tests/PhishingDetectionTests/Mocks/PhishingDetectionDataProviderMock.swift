//
//  PhishingDetectionDataProviderMock.swift
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

public class MockPhishingDetectionDataProvider: PhishingDetectionDataProviding {
    public var embeddedRevision: Int = 0
    var loadHashPrefixesCalled: Bool = false
    var loadFilterSetCalled: Bool = true
    
    public func loadEmbeddedFilterSet() -> Set<PhishingDetection.Filter> {
        self.loadHashPrefixesCalled = true
        return [Filter(hashValue: "dummyhash", regex: "dummyregex")]
    }
    
    public func loadEmbeddedHashPrefixes() -> Set<String> {
        self.loadFilterSetCalled = true
        return ["aabb"]
    }
    
}
