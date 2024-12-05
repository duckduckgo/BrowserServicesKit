//
//  MockEventMapping.swift
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

import Common
import Foundation
import MaliciousSiteProtection
import PixelKit

public class MockEventMapping: EventMapping<MaliciousSiteProtection.Event> {
    static var events: [MaliciousSiteProtection.Event] = []
    static var clientSideHitParam: String?
    static var errorParam: Error?

    public init() {
        super.init { event, error, params, _ in
            Self.events.append(event)
            switch event {
            case .errorPageShown:
                Self.clientSideHitParam = params?[PixelKit.Parameters.clientSideHit]
            case .updateTaskFailed48h(error: let error):
                Self.errorParam = error
            default:
                break
            }
        }
    }

    override init(mapping: @escaping EventMapping<MaliciousSiteProtection.Event>.Mapping) {
        fatalError("Use init()")
    }
}
