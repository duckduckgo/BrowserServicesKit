//
//  UserDefaultsSyncHandler.swift
//  DuckDuckGo
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
import BrowserServicesKit
import Combine
import DDGSync
import Persistence

public class UserDefaultsSyncHandler: SettingsSyncHandling {

    public let setting: SettingsProvider.Setting
    public weak var delegate: SettingsSyncHandlingDelegate?

    public func getValue() throws -> String? {
        userDefaults.string(forKey: userDefaultsKey)
    }

    public func setValue(_ value: String?) throws {
        userDefaults.set(value, forKey: userDefaultsKey)
    }

    public init(
        setting: SettingsProvider.Setting,
        userDefaults: UserDefaults,
        userDefaultsKey: String,
        didChangePublisher: AnyPublisher<Void, Never>
    ) {
        self.setting = setting
        self.userDefaults = userDefaults
        self.userDefaultsKey = userDefaultsKey

        didChangeCancellable = didChangePublisher
            .sink { [weak self] in
                guard let self else {
                    return
                }
                assert(self.delegate != nil, "delegate has not been set for \(type(of: self))")
                self.delegate?.syncHandlerDidUpdateSettingValue(self)
            }
    }

    private let userDefaultsKey: String
    private let userDefaults: UserDefaults
    private var didChangeCancellable: AnyCancellable?
}
