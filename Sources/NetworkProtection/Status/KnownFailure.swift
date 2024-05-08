//
//  KnownFailure.swift
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

@objc
final public class KnownFailure: NSObject, Codable {
    public let domain: String
    public let code: Int
    public let localizedDescription: String

    public init?(_ error: Error?) {
        guard let nsError = error as? NSError else { return nil }

        domain = nsError.domain
        code = nsError.code
        localizedDescription = nsError.localizedDescription
    }

    public override var description: String {
        "Error domain=\(domain) code=\(code)\n\(localizedDescription)"
    }
}
