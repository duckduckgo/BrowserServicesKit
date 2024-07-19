//
//  URLRequestAttribution.swift
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
import Common

public enum URLRequestAttribution {

    case unattributed
    case developer
    case user

    @available(iOS 15.0, macOS 12.0, *)
    public var urlRequestAttribution: URLRequest.Attribution? {
        switch self {
        case .developer:
            return .developer
        case .user:
            return .user
        case .unattributed:
            return nil
        }
    }

}
