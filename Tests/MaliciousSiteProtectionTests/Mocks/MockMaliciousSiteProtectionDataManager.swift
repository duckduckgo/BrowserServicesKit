//
//  MockMaliciousSiteProtectionDataManager.swift
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

class MockMaliciousSiteProtectionDataManager: MaliciousSiteProtection.DataManaging {
    var store = [MaliciousSiteProtection.DataManager.StoredDataType: Any]()

    func dataSet<DataKey>(for key: DataKey) async -> DataKey.DataSet where DataKey : MaliciousSiteProtection.MaliciousSiteDataKey {
        store[key.dataType] as? DataKey.DataSet ?? .init(revision: 0, items: [])
    }

    func store<DataKey>(_ dataSet: DataKey.DataSet, for key: DataKey) async where DataKey : MaliciousSiteProtection.MaliciousSiteDataKey {
        store[key.dataType] = dataSet
    }

}
