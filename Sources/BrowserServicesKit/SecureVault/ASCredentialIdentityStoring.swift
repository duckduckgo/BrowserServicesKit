//
//  ASCredentialIdentityStoring.swift
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
import AuthenticationServices

// This is used to abstract the ASCredentialIdentityStore for testing purposes
public protocol ASCredentialIdentityStoring {
    func state() async -> ASCredentialIdentityStoreState
    func saveCredentialIdentities(_ credentials: [ASPasswordCredentialIdentity]) async throws
    func removeCredentialIdentities(_ credentials: [ASPasswordCredentialIdentity]) async throws
    func replaceCredentialIdentities(with newCredentials: [ASPasswordCredentialIdentity]) async throws

    @available(iOS 17.0, macOS 14.0, *)
    func saveCredentialIdentities(_ credentials: [ASCredentialIdentity]) async throws
    @available(iOS 17.0, macOS 14.0, *)
    func removeCredentialIdentities(_ credentials: [ASCredentialIdentity]) async throws
    @available(iOS 17.0, macOS 14.0, *)
    func replaceCredentialIdentities(_ newCredentials: [ASCredentialIdentity]) async throws
}

extension ASCredentialIdentityStore: ASCredentialIdentityStoring {}
