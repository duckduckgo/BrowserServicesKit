//
//  APIResponseV2.swift
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
import os.log

public struct APIResponseV2 {
    let data: Data?
    let httpResponse: HTTPURLResponse
}

public extension APIResponseV2 {

    /// Decode the APIResponseV2 into the inferred `Decodable` type
    /// - Parameter decoder: A custom JSONDecoder, if not provided the default JSONDecoder() is used
    /// - Returns: An instance of a Decodable model of the type inferred
    func decodeBody<T: Decodable>(decoder: JSONDecoder = JSONDecoder()) throws -> T {

        guard let data = self.data else {
            throw APIRequestV2.Error.emptyResponseBody
        }

        Logger.networking.debug("Decoding APIResponse body as \(T.self)")
        switch T.self {
        case is String.Type:
            guard let resultString = String(data: data, encoding: .utf8) as? T else {
                let error = APIRequestV2.Error.invalidDataType
                Logger.networking.error("Error: \(error.localizedDescription)")
                throw error
            }
            return resultString
        default:
            return try decoder.decode(T.self, from: data)
        }
    }
}
