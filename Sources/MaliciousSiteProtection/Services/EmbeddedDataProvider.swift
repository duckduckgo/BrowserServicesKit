//
//  EmbeddedDataProvider.swift
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
import CryptoKit

public protocol EmbeddedDataProviding {
    func revision(for dataType: DataManager.StoredDataType) -> Int
    func url(for dataType: DataManager.StoredDataType) -> URL
    func hash(for dataType: DataManager.StoredDataType) -> String

    func loadDataSet<DataKey: MaliciousSiteDataKey>(for key: DataKey) -> DataKey.EmbeddedDataSet
}

extension EmbeddedDataProviding {

    public func loadDataSet<DataKey: MaliciousSiteDataKey>(for key: DataKey) -> DataKey.EmbeddedDataSet {
        let dataType = key.dataType
        let url = url(for: dataType)
        let data: Data
        do {
            data = try Data(contentsOf: url)
#if DEBUG
            assert(data.sha256 == hash(for: dataType), "SHA mismatch for \(url.path)")
#endif
        } catch {
            fatalError("Could not load embedded data set at \(url.path): \(error)")
        }
        do {
            let result = try JSONDecoder().decode(DataKey.EmbeddedDataSet.self, from: data)
            return result
        } catch {
            fatalError("Could not decode embedded data set at \(url.path): \(error)")
        }
    }

}
