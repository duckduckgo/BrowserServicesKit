//
//  ConfigurationManagerTests.swift
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

import XCTest
import Persistence
@testable import Configuration
@testable import Networking
@testable import TestUtils

final class MockConfigurationManager: DefaultConfigurationManager {

    var dependencyProvider: MockDependencyProvider = MockDependencyProvider()
    var name: String?

    override func refreshNow(isDebug: Bool = false) async {
        let configFetched = await fetchConfigDependencies(isDebug: isDebug)
        if configFetched {
            updateConfigDependencies()
        }
    }

    func fetchConfigDependencies(isDebug: Bool) async -> Bool {
        do {
            try await fetcher.fetch(.privacyConfiguration, isDebug: isDebug)
            return true
        } catch {
            return false
        }
    }

    var onDependenciesUpdated: (() -> Void)?
    func updateConfigDependencies() {
        dependencyProvider.privacyConfigData = store.loadData(for: .privacyConfiguration)
        dependencyProvider.privacyConfigEtag = store.loadEtag(for: .privacyConfiguration)
        onDependenciesUpdated?()
    }

    override var presentedItemURL: URL? {
        return store.fileUrl(for: .privacyConfiguration).deletingLastPathComponent()
    }

    override func presentedSubitemDidAppear(at url: URL) {
        guard url == store.fileUrl(for: .privacyConfiguration) else { return }
        updateConfigDependencies()
    }

    override func presentedSubitemDidChange(at url: URL) {
        guard url == store.fileUrl(for: .privacyConfiguration) else { return }
        updateConfigDependencies()
    }
}

struct MockDependencyProvider {
    var privacyConfigEtag: String?
    var privacyConfigData: Data?
}

final class ConfigurationManagerTests: XCTestCase {

    // Shared "UserDefaults" to mock app group defaults
    var sharedDefaults = MockKeyValueStore()

    override func setUp() {
        APIRequest.Headers.setUserAgent("")
        Configuration.setURLProvider(MockConfigurationURLProvider())
        sharedDefaults.clearAll()
        MockStoreWithStorage.clearTempConfigs()
    }

    func makeConfigurationFetcher(store: ConfigurationStoring,
                                  validator: ConfigurationValidating = MockValidator()) -> ConfigurationFetcher {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return ConfigurationFetcher(store: store,
                                    validator: validator,
                                    urlSession: URLSession(configuration: testConfiguration))
    }

    func makeConfigurationManager(name: String? = nil) -> MockConfigurationManager {
        let configStore = MockStoreWithStorage(etagStorage: sharedDefaults)
        let manager = MockConfigurationManager(fetcher: makeConfigurationFetcher(store: configStore),
                                               store: configStore,
                                               defaults: sharedDefaults)
        manager.name = name
        return manager
    }

    func testWhenConfigIsFetchedAndStoredDependencyIsUpdated() async {
        let configurationManager = makeConfigurationManager()

        let configData = Data("Privacy Config".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, configData) }
        await configurationManager.refreshNow()

        XCTAssertEqual(configurationManager.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(configurationManager.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)
    }

    func testWhenConfigIsNotModifiedThenDependencyIsNotUpdated() async {
        let configurationManager = makeConfigurationManager()

        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.notModified, nil) }
        await configurationManager.refreshNow()

        XCTAssertNil(configurationManager.dependencyProvider.privacyConfigData)
        XCTAssertNil(configurationManager.dependencyProvider.privacyConfigEtag)
    }

    func testWhenManagerAIsUpdatedManagerBIsAlsoUpdated() async throws {
        let managerA = makeConfigurationManager(name: "A")
        let managerB = makeConfigurationManager(name: "B")

        var e: XCTestExpectation? = expectation(description: "ConfigManager B updated")
        managerB.onDependenciesUpdated = {
            e?.fulfill()
            e = nil
        }

        let configData = Data("Privacy Config".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, configData) }
        await managerA.refreshNow()
        await fulfillment(of: [e!], timeout: 2)

        XCTAssertEqual(managerB.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)
    }

    func testWhenManagerBReceivesNewDataManagerAHasDataAfter304Response() async throws {
        let managerA = makeConfigurationManager()
        let managerB = makeConfigurationManager()

        var e: XCTestExpectation? = expectation(description: "ConfigManager B updated")
        managerB.onDependenciesUpdated = {
            e?.fulfill()
            e = nil
        }

        var configData = Data("Privacy Config".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, configData) }
        await managerA.refreshNow()
        await fulfillment(of: [e!], timeout: 2)

        XCTAssertEqual(managerB.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)

        e = expectation(description: "ConfigManager A updated")
        managerB.onDependenciesUpdated = nil
        managerA.onDependenciesUpdated = {
            e?.fulfill()
            e = nil
        }

        configData = Data("Privacy Config 2".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, configData) }
        await managerB.refreshNow()
        await fulfillment(of: [e!], timeout: 2)

        XCTAssertEqual(managerA.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerA.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)

        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.notModified, nil) }
        await managerA.refreshNow()
        XCTAssertEqual(managerA.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerA.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)
    }

    func testWhenManagerBReceivesAnErrorItKeepsDataFromManagerA() async throws {
        let managerA = makeConfigurationManager()
        let managerB = makeConfigurationManager()

        var e: XCTestExpectation? = expectation(description: "ConfigManager B updated")
        managerB.onDependenciesUpdated = {
            e?.fulfill()
            e = nil
        }

        let configData = Data("Privacy Config".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, configData) }
        await managerA.refreshNow()
        await fulfillment(of: [e!], timeout: 2)

        XCTAssertEqual(managerB.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)

        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        await managerB.refreshNow()

        XCTAssertEqual(managerB.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)
    }

}
