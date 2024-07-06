//
//  Mocks.swift
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

import BrowserServicesKit
import Combine
import Common
import Foundation
import Gzip
import Persistence
import TestUtils

@testable import DDGSync

extension SyncAccount {
    static var mock: SyncAccount {
        SyncAccount(
            deviceId: "deviceId",
            deviceName: "deviceName",
            deviceType: "deviceType",
            userId: "userId",
            primaryKey: "primaryKey".data(using: .utf8)!,
            secretKey: "secretKey".data(using: .utf8)!,
            token: "token",
            state: .active
        )
    }
}

extension RegisteredDevice {
    static var mock: RegisteredDevice {
        RegisteredDevice(id: "1", name: "2", type: "3")
    }
}

extension LoginResult {
    static var mock: LoginResult {
        LoginResult(account: .mock, devices: [.mock])
    }
}

struct AccountManagingMock: AccountManaging {
    func createAccount(deviceName: String, deviceType: String) async throws -> SyncAccount {
        .mock
    }

    func deleteAccount(_ account: SyncAccount) async throws {}

    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> LoginResult {
        .mock
    }

    func refreshToken(_ account: SyncAccount, deviceName: String) async throws -> LoginResult {
        .mock
    }

    func logout(deviceId: String, token: String) async throws {}

    func fetchDevicesForAccount(_ account: SyncAccount) async throws -> [RegisteredDevice] {
        [.mock]
    }
}

final class SchedulerMock: SchedulingInternal {
    var isEnabled: Bool = false

    let startSyncPublisher: AnyPublisher<Void, Never>
    let cancelSyncPublisher: AnyPublisher<Void, Never>
    let resumeSyncPublisher: AnyPublisher<Void, Never>

    init() {
        startSyncPublisher = startSyncSubject.eraseToAnyPublisher()
        cancelSyncPublisher = cancelSyncSubject.eraseToAnyPublisher()
        resumeSyncPublisher = resumeSyncSubject.eraseToAnyPublisher()
    }

    func notifyDataChanged() {
        if isEnabled {
            startSyncSubject.send()
        }
    }

    func notifyAppLifecycleEvent() {
        if isEnabled {
            startSyncSubject.send()
        }
    }

    func requestSyncImmediately() {
        if isEnabled {
            startSyncSubject.send()
        }
    }

    func cancelSyncAndSuspendSyncQueue() {
        cancelSyncSubject.send()
    }

    func resumeSyncQueue() {
        resumeSyncSubject.send()
    }

    private var startSyncSubject = PassthroughSubject<Void, Never>()
    private var cancelSyncSubject = PassthroughSubject<Void, Never>()
    private var resumeSyncSubject = PassthroughSubject<Void, Never>()
}

class MockErrorHandler: EventMapping<SyncError> {

    private var _handledErrors: NSMutableArray?
    var handledErrors: [SyncError] {
        _handledErrors as? [SyncError] ?? []
    }

    convenience init() {
        let handledErrors = NSMutableArray()
        self.init { e, _, _, _ in
            handledErrors.add(e)
        }
        _handledErrors = handledErrors
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

class MockPrivacyConfigurationManager: PrivacyConfigurationManaging {
    var currentConfig: Data = .init()
    var updatesSubject = PassthroughSubject<Void, Never>()
    let updatesPublisher: AnyPublisher<Void, Never>
    var privacyConfig: PrivacyConfiguration = MockPrivacyConfiguration()
    let internalUserDecider: InternalUserDecider = DefaultInternalUserDecider()
    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        .downloaded
    }

    init() {
        updatesPublisher = updatesSubject.eraseToAnyPublisher()
    }
}

class MockPrivacyConfiguration: PrivacyConfiguration {

    func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> Bool { true }

    func stateFor(featureKey: BrowserServicesKit.PrivacyFeature, versionProvider: BrowserServicesKit.AppVersionProvider) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
        return .enabled
    }

    func isSubfeatureEnabled(
        _ subfeature: any PrivacySubfeature,
        versionProvider: AppVersionProvider,
        randomizer: (Range<Double>) -> Double
    ) -> Bool {
        true
    }

    func stateFor(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        return .enabled
    }

    var identifier: String = "abcd"
    var userUnprotectedDomains: [String] = []
    var tempUnprotectedDomains: [String] = []
    var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist = .init(json: ["state": "disabled"])!
    func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] { [] }
    func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool { true }
    func isProtected(domain: String?) -> Bool { false }
    func isUserUnprotected(domain: String?) -> Bool { false }
    func isTempUnprotected(domain: String?) -> Bool { false }
    func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool { false }
    func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings { .init() }
    func userEnabledProtection(forDomain: String) {}
    func userDisabledProtection(forDomain: String) {}
}

struct MockSyncDependencies: SyncDependencies, SyncDependenciesDebuggingSupport {
    var endpoints: Endpoints = Endpoints(baseURL: URL(string: "https://dev.null")!)
    var account: AccountManaging = AccountManagingMock()
    var api: RemoteAPIRequestCreating = RemoteAPIRequestCreatingMock()
    var payloadCompressor: SyncPayloadCompressing = SyncGzipPayloadCompressorMock()
    var secureStore: SecureStoring = SecureStorageStub()
    var crypter: CryptingInternal = CryptingMock()
    var scheduler: SchedulingInternal = SchedulerMock()
    var log: OSLog = .default
    var privacyConfigurationManager: PrivacyConfigurationManaging = MockPrivacyConfigurationManager()
    var errorEvents: EventMapping<SyncError> = MockErrorHandler()
    var keyValueStore: KeyValueStoring = MockKeyValueStore()

    var request = HTTPRequestingMock()

    init() {
        (api as! RemoteAPIRequestCreatingMock).request = request
    }

    func createRemoteConnector(_ connectInfo: ConnectInfo) throws -> RemoteConnecting {
        try RemoteConnector(crypter: crypter, api: api, endpoints: endpoints, connectInfo: connectInfo)
    }

    func createRecoveryKeyTransmitter() throws -> RecoveryKeyTransmitting {
        RecoveryKeyTransmitter(endpoints: endpoints, api: api, storage: secureStore, crypter: crypter)
    }

    func updateServerEnvironment(_ serverEnvironment: ServerEnvironment) {}
}

final class MockDataProvidersSource: DataProvidersSource {
    var dataProviders: [DataProviding] = []

    func makeDataProviders() -> [DataProviding] {
        dataProviders
    }
}

class HTTPRequestingMock: HTTPRequesting {

    init(result: HTTPResult = .init(data: Data(), response: HTTPURLResponse())) {
        self.result = result
    }

    var executeCallCount = 0
    var error: SyncError?
    var result: HTTPResult

    func execute() async throws -> HTTPResult {
        executeCallCount += 1
        if let error {
            throw error
        }
        return result
    }
}

class RemoteAPIRequestCreatingMock: RemoteAPIRequestCreating {
    var createRequestCallCount = 0
    var createRequestCallArgs: [CreateRequestCallArgs] = []
    var request: HTTPRequesting = HTTPRequestingMock()
    var fakeRequests: [URL: HTTPRequestingMock] = [:]
    private let lock = NSLock()

    struct CreateRequestCallArgs: Equatable {
        let url: URL
        let method: HTTPRequestMethod
        let headers: [String: String]
        let parameters: [String: String]
        let body: Data?
        let contentType: String?
    }

    func createRequest(url: URL, method: HTTPRequestMethod, headers: [String: String], parameters: [String: String], body: Data?, contentType: String?) -> HTTPRequesting {
        lock.lock()
        defer { lock.unlock() }
        createRequestCallCount += 1
        createRequestCallArgs.append(CreateRequestCallArgs(url: url, method: method, headers: headers, parameters: parameters, body: body, contentType: contentType))
        return fakeRequests[url] ?? request
    }
}

class InspectableSyncRequestMaker: SyncRequestMaking {

    struct MakePatchRequestCallArgs {
        let result: SyncRequest
        let clientTimestamp: Date
        let isCompressed: Bool
    }

    func makeGetRequest(with result: SyncRequest) throws -> HTTPRequesting {
        try requestMaker.makeGetRequest(with: result)
    }

    func makePatchRequest(with result: SyncRequest, clientTimestamp: Date, isCompressed: Bool) throws -> HTTPRequesting {
        makePatchRequestCallCount += 1
        makePatchRequestCallArgs.append(.init(result: result, clientTimestamp: clientTimestamp, isCompressed: isCompressed))
        return try requestMaker.makePatchRequest(with: result, clientTimestamp: clientTimestamp, isCompressed: isCompressed)
    }

    let requestMaker: SyncRequestMaker

    init(requestMaker: SyncRequestMaker) {
        self.requestMaker = requestMaker
    }

    var makePatchRequestCallCount = 0
    var makePatchRequestCallArgs: [MakePatchRequestCallArgs] = []
}

class SyncGzipPayloadCompressorMock: SyncPayloadCompressing {
    var error: Error?

    func compress(_ payload: Data) throws -> Data {
        if let error {
            throw error
        }
        return try payload.gzipped()
    }
}

struct CryptingMock: CryptingInternal {
    var _encryptAndBase64Encode: (String) throws -> String = { "encrypted_\($0)" }
    var _base64DecodeAndDecrypt: (String) throws -> String = { $0.dropping(prefix: "encrypted_") }

    func fetchSecretKey() throws -> Data {
        .init()
    }

    func encryptAndBase64Encode(_ value: String) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }

    func encryptAndBase64Encode(_ value: String, using secretKey: Data) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String, using secretKey: Data) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }

    func seal(_ data: Data, secretKey: Data) throws -> Data {
        data
    }

    func unseal(encryptedData: Data, publicKey: Data, secretKey: Data) throws -> Data {
        encryptedData
    }

    func createAccountCreationKeys(userId: String, password: String) throws -> AccountCreationKeys {
        AccountCreationKeys(primaryKey: Data(), secretKey: Data(), protectedSecretKey: Data(), passwordHash: Data())
    }

    func extractLoginInfo(recoveryKey: SyncCode.RecoveryKey) throws -> ExtractedLoginInfo {
        ExtractedLoginInfo(userId: "user", primaryKey: Data(), passwordHash: Data(), stretchedPrimaryKey: Data())
    }

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data {
        Data()
    }

    func prepareForConnect() throws -> ConnectInfo {
        ConnectInfo(deviceID: "1234", publicKey: Data(), secretKey: Data())
    }

}

class SyncMetadataStoreMock: SyncMetadataStore {
    struct FeatureInfo: Equatable {
        var timestamp: String?
        var localTimestamp: Date?
        var state: FeatureSetupState
    }

    var features: [String: FeatureInfo] = [:]

    func isFeatureRegistered(named name: String) -> Bool {
        features.keys.contains(name)
    }

    func registerFeature(named name: String, setupState: FeatureSetupState) throws {
        features[name] = .init(state: setupState)
    }

    func deregisterFeature(named name: String) throws {
        features.removeValue(forKey: name)
    }

    func timestamp(forFeatureNamed name: String) -> String? {
        features[name]?.timestamp
    }

    func updateTimestamp(_ timestamp: String?, forFeatureNamed name: String) {
        features[name]?.timestamp = timestamp
    }

    func localTimestamp(forFeatureNamed name: String) -> Date? {
        features[name]?.localTimestamp
    }

    func state(forFeatureNamed name: String) -> FeatureSetupState {
        features[name]?.state ?? .readyToSync
    }

    func updateLocalTimestamp(_ localTimestamp: Date?, forFeatureNamed name: String) {
        features[name]?.localTimestamp = localTimestamp
    }

    func update(_ serverTimestamp: String?, _ localTimestamp: Date?, _ state: FeatureSetupState, forFeatureNamed name: String) {
        features[name]?.state = state
        features[name]?.timestamp = serverTimestamp
        features[name]?.localTimestamp = localTimestamp
    }
}

class DataProvidingMock: DataProvider {

    init(feature: Feature, syncDidUpdateData: @escaping () -> Void = {}) {
        super.init(feature: feature, metadataStore: SyncMetadataStoreMock(), syncDidUpdateData: syncDidUpdateData)
    }

    var _prepareForFirstSync: () throws -> Void = {}
    var _fetchChangedObjects: (Crypting) async throws -> [Syncable] = { _ in return [] }
    var handleInitialSyncResponse: ([Syncable], Date, String?, Crypting) async throws -> Void = { _, _, _, _ in }
    var handleSyncResponse: ([Syncable], [Syncable], Date, String?, Crypting) async throws -> Void = { _, _, _, _, _ in }
    var _handleSyncError: (Error) -> Void = { _ in }

    override func prepareForFirstSync() throws {
        try _prepareForFirstSync()
    }

    override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        try await _fetchChangedObjects(crypter)
    }

    override func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleInitialSyncResponse(received, clientTimestamp, serverTimestamp, crypter)
        updateSyncTimestamps(server: serverTimestamp, local: clientTimestamp)
    }

    override func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(sent, received, clientTimestamp, serverTimestamp, crypter)
        updateSyncTimestamps(server: serverTimestamp, local: clientTimestamp)
    }

    override func handleSyncError(_ error: Error) {
        _handleSyncError(error)
    }
}
