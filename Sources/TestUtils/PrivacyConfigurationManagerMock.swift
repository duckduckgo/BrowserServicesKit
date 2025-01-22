//
//  PrivacyConfigurationManagerMock.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Combine

public class PrivacyConfigurationManagerMock: PrivacyConfigurationManaging {

    public init() {
    }

    var embeddedConfigData: BrowserServicesKit.PrivacyConfigurationManager.ConfigurationData {
        fatalError("not implemented")
    }

    var fetchedConfigData: BrowserServicesKit.PrivacyConfigurationManager.ConfigurationData? {
        fatalError("not implemented")
    }

    public var currentConfig: Data {
        Data()
    }

    public var updatesSubject = PassthroughSubject<Void, Never>()
    public var updatesPublisher: AnyPublisher<Void, Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    public var privacyConfig: PrivacyConfiguration = PrivacyConfigurationMock()
    public var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider()

    public var reloadFired = [(etag: String?, data: Data?)]()
    public var reloadResult: PrivacyConfigurationManager.ReloadResult = .embedded
    public func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        reloadFired.append((etag, data))
        return reloadResult
    }

}

final class MockInternalUserStoring: InternalUserStoring {
    var isInternalUser: Bool = false
}

extension DefaultInternalUserDecider {
    convenience init(mockedStore: MockInternalUserStoring = MockInternalUserStoring()) {
        self.init(store: mockedStore)
    }
}
