//
//  MockMaliciousSiteDetector.swift
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
import MaliciousSiteProtection

public class MockMaliciousSiteDetector: MaliciousSiteDetecting {
    private var mockClient: MaliciousSiteProtection.APIClientProtocol
    public var didCallIsMalicious: Bool = false

    init() {
        self.mockClient = MockMaliciousSiteProtectionAPIClient()
    }

    public func getMatches(hashPrefix: String) async -> Set<Match> {
        let matches = await mockClient.getMatches(hashPrefix: hashPrefix)
        return Set(matches)
    }

    public func evaluate(_ url: URL) async -> ThreatKind? {
        return url.absoluteString.contains("malicious") ? .phishing : nil
    }
}
