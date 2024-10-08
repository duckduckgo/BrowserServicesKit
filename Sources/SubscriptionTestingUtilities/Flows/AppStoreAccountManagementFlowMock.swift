//
//  AppStoreAccountManagementFlowMock.swift
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
import Subscription

public final class AppStoreAccountManagementFlowMock: AppStoreAccountManagementFlow {
    public var refreshAuthTokenIfNeededResult: Result<String, AppStoreAccountManagementFlowError>?
    public var onRefreshAuthTokenIfNeeded: (() -> Void)?
    public var refreshAuthTokenIfNeededCalled: Bool = false

    public init() { }

    public func refreshAuthTokenIfNeeded() async -> Result<String, AppStoreAccountManagementFlowError> {
        refreshAuthTokenIfNeededCalled = true
        onRefreshAuthTokenIfNeeded?()
        return refreshAuthTokenIfNeededResult!
    }
}
