//
//  MockMaliciousSiteProtectionEmbeddedDataProvider.swift
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
import MaliciousSiteProtection

public class MockMaliciousSiteProtectionEmbeddedDataProvider: MaliciousSiteProtection.EmbeddedDataProviding {
    public var embeddedRevision: Int = 65
    var loadHashPrefixesCalled: Bool = false
    var loadFilterSetCalled: Bool = true
    var hashPrefixes: Set<String> = ["aabb"]
    var filterSet: Set<Filter> = [Filter(hash: "dummyhash", regex: "dummyregex")]

    public func shouldReturnFilterSet(set: Set<Filter>) {
        self.filterSet = set
    }

    public func shouldReturnHashPrefixes(set: Set<String>) {
        self.hashPrefixes = set
    }

    public func loadEmbeddedFilterSet() -> Set<Filter> {
        self.loadHashPrefixesCalled = true
        return self.filterSet
    }

    public func loadEmbeddedHashPrefixes() -> Set<String> {
        self.loadFilterSetCalled = true
        return self.hashPrefixes
    }

}
