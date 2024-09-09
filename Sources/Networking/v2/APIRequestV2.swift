//
//  APIRequestV2.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct APIRequestV2: CustomDebugStringConvertible {
    let requirements: [APIResponseRequirementV2]
    let urlRequest: URLRequest
    let configuration: APIRequestV2.ConfigurationV2

    public init?(configuration: APIRequestV2.ConfigurationV2,
                 requirements: [APIResponseRequirementV2] = []) {
        guard let request = configuration.urlRequest else {
            return nil
        }
        self.urlRequest = request
        self.requirements = requirements
        self.configuration = configuration
    }

    public var debugDescription: String {
        "Configuration: \(configuration) - Requirements: \(requirements)"
    }
}
