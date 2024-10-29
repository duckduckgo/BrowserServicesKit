//
//  SubscriptionKeychainManager+TokensStoring.swift
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
import Networking
import Common
import os.log

extension SubscriptionKeychainManager: TokensStoring {

    public var tokenContainer: TokenContainer? {
        get {
            queue.sync {
                guard let data = try? retrieveData(forField: .tokens) else {
                    return nil
                }
                return CodableHelper.decode(jsonData: data)
            }
        }
        set {
            queue.sync { [weak self] in
                guard let strongSelf = self else { return }

                do {
                    guard let newValue else {
                        Logger.subscription.log("removing TokenContainer")
                        try strongSelf.deleteItem(forField: .tokens)
                        return
                    }

                    if let data = CodableHelper.encode(newValue) {
                        if (try? strongSelf.retrieveData(forField: .tokens)) != nil {
                            try strongSelf.updateData(data, forField: .tokens)
                        } else {
                            try strongSelf.store(data: data, forField: .tokens)
                        }
                    } else {
                        Logger.subscription.fault("Failed to encode TokenContainer")
                        assertionFailure("Failed to encode TokenContainer")
                    }
                } catch {
                    Logger.subscription.fault("Failed to set TokenContainer: \(error, privacy: .public)")
                    assertionFailure("Failed to set TokenContainer")
                }
            }
        }
    }
}
