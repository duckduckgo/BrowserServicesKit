//
//  SpecialErrorData.swift
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

public enum SpecialErrorKind: String, Encodable {

    case ssl

}

public struct SpecialErrorData: Encodable, Equatable {

    var kind: SpecialErrorKind
    var errorType: String?
    var domain: String?
    var eTldPlus1: String?

    public init(kind: SpecialErrorKind, errorType: String? = nil, domain: String? = nil, eTldPlus1: String? = nil) {
        self.kind = kind
        self.errorType = errorType
        self.domain = domain
        self.eTldPlus1 = eTldPlus1
    }

}
