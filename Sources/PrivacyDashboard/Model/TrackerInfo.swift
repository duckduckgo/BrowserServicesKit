//
//  TrackerInfo.swift
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
import TrackerRadarKit
import ContentBlocking

public struct TrackerInfo: Encodable {
    
    enum CodingKeys: String, CodingKey {
        case requests
        case installedSurrogates
    }
    
    public private (set) var trackers = Set<DetectedRequest>()
    private(set) var thirdPartyRequests = Set<DetectedRequest>()
    public private(set) var installedSurrogates = Set<String>()
    
    public init() { }
    
    // MARK: - Collecting detected elements
    
    public mutating func addDetectedTracker(_ tracker: DetectedRequest, onPageWithURL url: URL) {
        guard tracker.pageUrl == url.absoluteString else { return }
        trackers.insert(tracker)
    }
    
    public mutating func add(detectedThirdPartyRequest request: DetectedRequest) {
        thirdPartyRequests.insert(request)
    }
    
    public mutating func addInstalledSurrogateHost(_ host: String, for tracker: DetectedRequest, onPageWithURL url: URL) {
        guard tracker.pageUrl == url.absoluteString else { return }
        installedSurrogates.insert(host)
    }
    
    // MARK: - Helper accessors
    
    public var trackersBlocked: [DetectedRequest] {
        trackers.filter { $0.state == .blocked }
    }
    
    public var trackersDetected: [DetectedRequest] {
        trackers.filter { $0.state != .blocked }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        let allRequests = [] + trackers + thirdPartyRequests
        
        try container.encode(allRequests, forKey: .requests)
        try container.encode(installedSurrogates, forKey: .installedSurrogates)
    }
    
}
