//
//  UserContentControllerTests.swift
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

import Combine
import Common
import Foundation
import UserScript
import WebKit
import XCTest

@testable import BrowserServicesKit

final class UserContentControllerTests: XCTestCase {

    struct MockScriptSourceProvider {
    }
    class MockScriptProvider: UserScriptsProvider {
        var userScripts: [UserScript] { [] }
        func loadWKUserScripts() async -> [WKUserScript] {
            []
        }
    }

    struct NewContent: UserContentControllerNewContent {
        let rulesUpdate: ContentBlockerRulesManager.UpdateEvent
        let sourceProvider: MockScriptSourceProvider

        var makeUserScripts: @MainActor (MockScriptSourceProvider) -> MockScriptProvider {
            { sourceProvider in
                MockScriptProvider()
            }
        }
    }
    let assetsSubject = PassthroughSubject<NewContent, Never>()

    var ucc: UserContentController!
    typealias Assets = (contentRuleLists: [String: WKContentRuleList], userScripts: any UserScriptsProvider, updateEvent: ContentBlockerRulesManager.UpdateEvent)
    var onAssetsInstalled: ((Assets) -> Void)?

    @MainActor
    override func setUp() async throws {
        _=WKUserContentController.swizzleContentRuleListsMethodsOnce
        ucc = UserContentController(assetsPublisher: assetsSubject, privacyConfigurationManager: MockPrivacyConfigurationManager2())
        ucc.delegate = self
    }

    func assetsInstalledExpectation(onAssetsInstalled: ((Assets) -> Void)? = nil) -> XCTestExpectation {
        let e = expectation(description: "assets installed")
        self.onAssetsInstalled = {
            onAssetsInstalled?($0)
            e.fulfill()
        }
        return e
    }

    // MARK: - Tests

    @MainActor
    func testWhenContentBlockingAssetsPublished_contentRuleListsAreInstalled() async throws {
        let rules1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules2 = await ContentBlockingRulesHelper().makeFakeRules(name: "list2")!

        let e = assetsInstalledExpectation {
            XCTAssertEqual($0.contentRuleLists, [rules1.name: rules1.rulesList, rules2.name: rules2.rulesList])
        }
        assetsSubject.send(NewContent(rulesUpdate: .init(rules: [rules1, rules2], changes: [rules1.name: .all, rules2.name: .all], completionTokens: ["1"]), sourceProvider: MockScriptSourceProvider()))

        await fulfillment(of: [e], timeout: 1)
        XCTAssertEqual(ucc.installedContentRuleLists.sorted(by: { $0.identifier < $1.identifier }), [rules1.rulesList, rules2.rulesList])
    }

    @MainActor
    func testWhenLocalContentRuleListInstalled_contentRuleListIsInstalled() async throws {
        let rules1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules2 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules3 = await ContentBlockingRulesHelper().makeFakeRules(name: "list2")!

        // initial publish
        let e = assetsInstalledExpectation()
        assetsSubject.send(NewContent(rulesUpdate: .init(rules: [rules1], changes: [rules1.name: .all], completionTokens: ["1"]), sourceProvider: MockScriptSourceProvider()))
        await fulfillment(of: [e], timeout: 1)

        // install 2 local lists
        ucc.installLocalContentRuleList(rules2.rulesList, identifier: rules2.name)
        ucc.installLocalContentRuleList(rules3.rulesList, identifier: rules3.name)
        XCTAssertEqual(ucc.installedContentRuleLists, [rules1.rulesList, rules2.rulesList, rules3.rulesList])
    }

    @MainActor
    func testWhenLocalContentRuleListWithExistingIdInstalled_contentRuleListIsReplaced() async throws {
        let rules1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules2 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules3 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!

        // initial publish
        let e = assetsInstalledExpectation()
        assetsSubject.send(NewContent(rulesUpdate: .init(rules: [rules1], changes: [rules1.name: .all], completionTokens: ["1"]), sourceProvider: MockScriptSourceProvider()))
        await fulfillment(of: [e], timeout: 1)

        // install 2 local lists with same id
        ucc.installLocalContentRuleList(rules2.rulesList, identifier: rules2.name)
        ucc.installLocalContentRuleList(rules3.rulesList, identifier: rules2.name)
        XCTAssertEqual(ucc.installedContentRuleLists, [rules1.rulesList, rules3.rulesList])
    }

    @MainActor
    func testWhenLocalContentRuleListRemoved_contentRuleListIsRemoved() async throws {
        let rules1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules2 = await ContentBlockingRulesHelper().makeFakeRules(name: "list2")!
        let rules3 = await ContentBlockingRulesHelper().makeFakeRules(name: "list3")!

        // initial publish
        let e = assetsInstalledExpectation { [unowned self] _ in
            // install 2 local lists
            ucc.installLocalContentRuleList(rules2.rulesList, identifier: rules2.name)
            ucc.installLocalContentRuleList(rules3.rulesList, identifier: rules3.name)
        }
        assetsSubject.send(NewContent(rulesUpdate: .init(rules: [rules1], changes: [rules1.name: .all], completionTokens: ["1"]), sourceProvider: MockScriptSourceProvider()))
        await fulfillment(of: [e], timeout: 1)

        ucc.removeLocalContentRuleList(withIdentifier: rules2.name)
        ucc.removeLocalContentRuleList(withIdentifier: rules3.name)

        XCTAssertEqual(ucc.installedContentRuleLists, [rules1.rulesList])
    }

    @MainActor
    func testWhenGlobalContentRuleListDisabled_itIsRemoved() async throws {
        let rules1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules2 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!

        let e = assetsInstalledExpectation { [unowned self] _ in
            // install local rule list during the delegate call
            ucc.installLocalContentRuleList(rules2.rulesList, identifier: rules2.rulesList.identifier)
            // disable global content rule list
            try! ucc.disableGlobalContentRuleList(withIdentifier: "list1")
        }
        assetsSubject.send(NewContent(rulesUpdate: .init(rules: [rules1, rules2], changes: [rules1.name: .all], completionTokens: ["1"]), sourceProvider: MockScriptSourceProvider()))

        await fulfillment(of: [e], timeout: 1)
        XCTAssertEqual(ucc.installedContentRuleLists, [rules2.rulesList])
    }

    @MainActor
    func testWhenGlobalContentRuleListEnabled_itIsAdded() async throws {
        let rules1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules2 = await ContentBlockingRulesHelper().makeFakeRules(name: "list2")!

        let e = assetsInstalledExpectation { [unowned self] _ in
            // disable global content rule lists
            try! ucc.disableGlobalContentRuleList(withIdentifier: "list2")
        }
        assetsSubject.send(NewContent(rulesUpdate: .init(rules: [rules1, rules2], changes: [rules1.name: .all, rules2.name: .all], completionTokens: ["1"]), sourceProvider: MockScriptSourceProvider()))

        await fulfillment(of: [e], timeout: 1)

        // re-enable global content rule list
        try ucc.enableGlobalContentRuleList(withIdentifier: "list2")
        XCTAssertEqual(ucc.installedContentRuleLists, [rules1.rulesList, rules2.rulesList])
    }

    @MainActor
    func testWhenContentBlockingAssetsUpdated_allContentRuleListsAreReistalled() async throws {
        let rules1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules2 = await ContentBlockingRulesHelper().makeFakeRules(name: "list2")!
        let rules3 = await ContentBlockingRulesHelper().makeFakeRules(name: "list3")!
        let rules4 = await ContentBlockingRulesHelper().makeFakeRules(name: "list4")!

        // initial publish
        let e = assetsInstalledExpectation { [unowned self] _ in
            ucc.installLocalContentRuleList(rules3.rulesList, identifier: rules3.name)
        }
        assetsSubject.send(NewContent(rulesUpdate: .init(rules: [rules1, rules2], changes: [rules1.name: .all], completionTokens: ["1"]), sourceProvider: MockScriptSourceProvider()))
        await fulfillment(of: [e], timeout: 1)
        ucc.installLocalContentRuleList(rules4.rulesList, identifier: rules4.name)

        XCTAssertEqual(ucc.installedContentRuleLists.sorted(by: { $0.identifier < $1.identifier }), [rules1.rulesList, rules2.rulesList, rules3.rulesList, rules4.rulesList])

        let rules1_1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list1")!
        let rules2_1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list2_1")!
        let rules3_1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list3")!
        let rules4_1 = await ContentBlockingRulesHelper().makeFakeRules(name: "list4_1")!

        let e2 = assetsInstalledExpectation { [unowned self] _ in
            ucc.installLocalContentRuleList(rules3_1.rulesList, identifier: rules3_1.name)
        }
        assetsSubject.send(NewContent(rulesUpdate: .init(rules: [rules1_1, rules2_1], changes: [rules1_1.name: .all], completionTokens: ["1"]), sourceProvider: MockScriptSourceProvider()))
        await fulfillment(of: [e2], timeout: 1)
        ucc.installLocalContentRuleList(rules4_1.rulesList, identifier: rules4_1.name)

        XCTAssertEqual(ucc.installedContentRuleLists.sorted(by: { $0.identifier < $1.identifier }), [rules1_1.rulesList, rules2_1.rulesList, rules3_1.rulesList, rules4_1.rulesList])
    }

}

extension WKUserContentController {

    private static let contentRuleListsKey = UnsafeRawPointer(bitPattern: "contentRuleListsKey".hashValue)!
    var installedContentRuleLists: [WKContentRuleList] {
        get {
            objc_getAssociatedObject(self, Self.contentRuleListsKey) as? [WKContentRuleList] ?? []
        }
        set {
            objc_setAssociatedObject(self, Self.contentRuleListsKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    static var swizzleContentRuleListsMethodsOnce: Void = {
        let originalAddMethod = class_getInstanceMethod(WKUserContentController.self, NSSelectorFromString("addContentRuleList:"))!
        let swizzledAddMethod = class_getInstanceMethod(WKUserContentController.self, #selector(swizzled_addContentRuleList))!
        method_exchangeImplementations(originalAddMethod, swizzledAddMethod)

        let originalRemoveMethod = class_getInstanceMethod(WKUserContentController.self, NSSelectorFromString("removeContentRuleList:"))!
        let swizzledRemoveMethod = class_getInstanceMethod(WKUserContentController.self, #selector(swizzled_removeContentRuleList))!
        method_exchangeImplementations(originalRemoveMethod, swizzledRemoveMethod)

        let originalRemoveAllMethod = class_getInstanceMethod(WKUserContentController.self, #selector(removeAllContentRuleLists))!
        let swizzledRemoveAllMethod = class_getInstanceMethod(WKUserContentController.self, #selector(swizzled_removeAllContentRuleLists))!
        method_exchangeImplementations(originalRemoveAllMethod, swizzledRemoveAllMethod)
    }()

    @objc dynamic private func swizzled_addContentRuleList(_ contentRuleList: WKContentRuleList) {
        installedContentRuleLists.append(contentRuleList)
        self.swizzled_addContentRuleList(contentRuleList) // call the original
    }

    @objc dynamic private func swizzled_removeContentRuleList(_ contentRuleList: WKContentRuleList) {
        installedContentRuleLists.remove(at: installedContentRuleLists.firstIndex(of: contentRuleList)!)
        self.swizzled_removeContentRuleList(contentRuleList) // call the original
    }

    @objc dynamic private func swizzled_removeAllContentRuleLists() {
        installedContentRuleLists.removeAll()
        self.swizzled_removeAllContentRuleLists() // call the original
    }
}

extension UserContentControllerTests: UserContentControllerDelegate {
    func userContentController(_ userContentController: UserContentController, didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList], userScripts: any UserScriptsProvider, updateEvent: ContentBlockerRulesManager.UpdateEvent) {
        onAssetsInstalled?((contentRuleLists, userScripts, updateEvent))
    }
}

class MockPrivacyConfigurationManager2: PrivacyConfigurationManaging {
    var currentConfig: Data = .init()
    var updatesSubject = PassthroughSubject<Void, Never>()
    let updatesPublisher: AnyPublisher<Void, Never>
    var privacyConfig: PrivacyConfiguration = MockPrivacyConfiguration2()
    let internalUserDecider: InternalUserDecider = DefaultInternalUserDecider()
    var toggleProtectionsCounter = ToggleProtectionsCounter(eventReporting: EventMapping<ToggleProtectionsCounterEvent> { _, _, _, _ in })
    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        .downloaded
    }

    init() {
        updatesPublisher = updatesSubject.eraseToAnyPublisher()
    }
}

class MockPrivacyConfiguration2: PrivacyConfiguration {

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
