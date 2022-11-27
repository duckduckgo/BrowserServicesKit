//
//  EventMapping.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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

open class EventMapping<Event> {
    public typealias Mapping = (_ event: Event,
                                _ error: Error?,
                                _ params: [String: String]?, _ onComplete: @escaping (Error?) -> Void) -> Void

    private let eventMapper: Mapping

    public init(mapping: @escaping Mapping) {
        eventMapper = mapping
    }

    public func fire(_ event: Event, error: Error? = nil, parameters: [String: String]? = nil, onComplete: @escaping (Error?) -> Void = {_ in }) {
        eventMapper(event, error, parameters, onComplete)
    }
}
