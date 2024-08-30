//
//  DecodableHelper.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public struct DecodableHelper {
    public static func decode<Input: Any, Target: Decodable>(from input: Input) -> Target? {
        do {
            let json = try JSONSerialization.data(withJSONObject: input)
            return try JSONDecoder().decode(Target.self, from: json)
        } catch {
            Logger.general.error("Error decoding message body: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
