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
@testable import MaliciousSiteProtection

class MockMaliciousSiteProtectionEmbeddedDataProvider: MaliciousSiteProtection.EmbeddedDataProviding {
    var embeddedRevision: Int = 65
    var loadHashPrefixesCalled: Bool = false
    var loadFilterSetCalled: Bool = true
    var hashPrefixes = Set(["aabb"])
    var filterSet = Set([Filter(hash: "dummyhash", regex: "dummyregex")])

    func revision(for detectionKind: MaliciousSiteProtection.DataManager.StoredDataType) -> Int {
        embeddedRevision
    }

    func url(for detectionKind: MaliciousSiteProtection.DataManager.StoredDataType) -> URL {
        URL.empty
    }

    public func hash(for detectionKind: MaliciousSiteProtection.DataManager.StoredDataType) -> String {
        ""
    }

    func loadDataSet<DataKey>(for key: DataKey) -> DataKey.EmbeddedDataSet where DataKey: MaliciousSiteDataKey {
        switch key.dataType {
        case .filterSet:
            self.loadFilterSetCalled = true
            return Array(filterSet) as! DataKey.EmbeddedDataSet
        case .hashPrefixSet:
            self.loadHashPrefixesCalled = true
            return Array(hashPrefixes) as! DataKey.EmbeddedDataSet
        }
    }

}
