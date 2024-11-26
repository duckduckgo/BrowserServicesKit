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

import Combine
import Foundation
import MaliciousSiteProtection

public actor MockMaliciousSiteProtectionDataManager: MaliciousSiteProtection.DataManaging {
    
    @Published var store = [MaliciousSiteProtection.DataManager.StoredDataType: Any]()
    func publisher<DataKey>(for key: DataKey) -> AnyPublisher<DataKey.DataSetType, Never> where DataKey: MaliciousSiteProtection.MaliciousSiteDataKeyProtocol {
        $store.map { $0[key.dataType] as? DataKey.DataSetType ?? .init(revision: 0, items: []) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public func dataSet<DataKey>(for key: DataKey) -> DataKey.DataSetType where DataKey: MaliciousSiteProtection.MaliciousSiteDataKeyProtocol {
        return store[key.dataType] as? DataKey.DataSetType ?? .init(revision: 0, items: [])
    }

    public func store<DataKey>(_ dataSet: DataKey.DataSetType, for key: DataKey) where DataKey: MaliciousSiteProtection.MaliciousSiteDataKeyProtocol {
        store[key.dataType] = dataSet
    }

}
