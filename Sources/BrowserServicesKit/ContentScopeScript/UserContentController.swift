//
//  UserContentController.swift
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

import WebKit
import Combine
import UserScript

public protocol UserContentControllerDelegate: AnyObject {
    @MainActor
    func userContentController(_ userContentController: UserContentController,
                               didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
                               userScripts: UserScriptsProvider,
                               updateEvent: ContentBlockerRulesManager.UpdateEvent)
}

public protocol UserContentControllerNewContent {
    associatedtype SourceProvider
    associatedtype UserScripts: UserScriptsProvider

    var rulesUpdate: ContentBlockerRulesManager.UpdateEvent { get }
    var sourceProvider: SourceProvider { get }
    var makeUserScripts: @MainActor (SourceProvider) -> UserScripts { get }
}

@MainActor
final public class UserContentController: WKUserContentController {
    public let privacyConfigurationManager: PrivacyConfigurationManaging
    public weak var delegate: UserContentControllerDelegate?

    public struct ContentBlockingAssets {
        public let globalRuleLists: [String: WKContentRuleList]
        public let userScripts: UserScriptsProvider
        public let wkUserScripts: [WKUserScript]
        public let updateEvent: ContentBlockerRulesManager.UpdateEvent

        public init<Content: UserContentControllerNewContent>(content: Content) async {
            self.globalRuleLists = content.rulesUpdate.rules.reduce(into: [:]) { result, rules in
                result[rules.name] = rules.rulesList
            }
            let userScripts = await content.makeUserScripts(content.sourceProvider)
            self.userScripts = userScripts
            self.updateEvent = content.rulesUpdate

            self.wkUserScripts = await userScripts.loadWKUserScripts()
        }
    }

    @Published public private(set) var contentBlockingAssets: ContentBlockingAssets? {
        willSet {
            self.removeAllContentRuleLists()
            self.removeAllUserScripts()
        }
    }
    private func installContentBlockingAssets(_ contentBlockingAssets: ContentBlockingAssets) {
        // don‘t install ContentBlockingAssets (especially Message Handlers retaining `self`) after cleanUpBeforeClosing was called
        guard assetsPublisherCancellable != nil else { return }

        self.contentBlockingAssets = contentBlockingAssets

        self.installGlobalContentRuleLists(contentBlockingAssets.globalRuleLists)
        self.installUserScripts(contentBlockingAssets.wkUserScripts, handlers: contentBlockingAssets.userScripts.userScripts)

        delegate?.userContentController(self,
                                        didInstallContentRuleLists: contentBlockingAssets.globalRuleLists,
                                        userScripts: contentBlockingAssets.userScripts,
                                        updateEvent: contentBlockingAssets.updateEvent)
    }

    private var localRuleLists = [String: WKContentRuleList]()

    private var assetsPublisherCancellable: AnyCancellable?
    private let scriptMessageHandler = PermanentScriptMessageHandler()

    public init<Pub, Content>(assetsPublisher: Pub, privacyConfigurationManager: PrivacyConfigurationManaging)
    where Pub: Publisher, Content: UserContentControllerNewContent, Pub.Output == Content, Pub.Failure == Never {

        self.privacyConfigurationManager = privacyConfigurationManager
        super.init()

        assetsPublisherCancellable = assetsPublisher.sink { [weak self] content in
            Task.detached { [weak self] in
                let contentBlockingAssets = await ContentBlockingAssets(content: content)
                await self?.installContentBlockingAssets(contentBlockingAssets)
            }
        }

#if DEBUG
        // make sure delegate for UserScripts is set shortly after init
        DispatchQueue.main.async { [weak self] in
            assert(self == nil || self?.delegate != nil, "UserContentController delegate not set")
        }
#endif
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installGlobalContentRuleLists(_ contentRuleLists: [String: WKContentRuleList]) {
        guard self.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking) else {
            removeAllContentRuleLists()
            return
        }

        contentRuleLists.values.forEach(self.add)
    }

    public struct ContentRulesNotFoundError: Error {}
    public func enableGlobalContentRuleList(withIdentifier identifier: String) throws {
        guard let ruleList = self.contentBlockingAssets?.globalRuleLists[identifier] else {
            throw ContentRulesNotFoundError()
        }
        self.add(ruleList)
    }

    public struct ContentRulesNotEnabledError: Error {}
    public func disableGlobalContentRuleList(withIdentifier identifier: String) throws {
        guard let ruleList = self.contentBlockingAssets?.globalRuleLists[identifier] else {
            throw ContentRulesNotEnabledError()
        }
        self.remove(ruleList)
    }

    public func installLocalContentRuleList(_ ruleList: WKContentRuleList, identifier: String) {
        localRuleLists[identifier] = ruleList
        self.add(ruleList)
    }

    public func removeLocalContentRuleList(withIdentifier identifier: String) {
        guard let ruleList = localRuleLists.removeValue(forKey: identifier) else {
            return
        }
        self.remove(ruleList)
    }

    public override func removeAllContentRuleLists() {
        localRuleLists = [:]
        super.removeAllContentRuleLists()
    }

    private func installUserScripts(_ wkUserScripts: [WKUserScript], handlers: [UserScript]) {
        handlers.forEach { self.addHandler($0) }
        wkUserScripts.forEach(self.addUserScript)
    }

    public func cleanUpBeforeClosing() {
        self.removeAllUserScripts()

        if #available(macOS 11.0, *) {
            self.removeAllScriptMessageHandlers()
        } else {
            self.scriptMessageHandler.registeredMessageNames.forEach(self.removeScriptMessageHandler)
        }

        self.scriptMessageHandler.clear()
        self.assetsPublisherCancellable = nil

        self.removeAllContentRuleLists()
    }

    func addHandler(_ userScript: UserScript) {
        for messageName in userScript.messageNames {
            assert(scriptMessageHandler.messageHandler(for: messageName) == nil || type(of: scriptMessageHandler.messageHandler(for: messageName)!) == type(of: userScript),
                   "\(scriptMessageHandler.messageHandler(for: messageName)!) already registered for message \(messageName)")

            defer {
                scriptMessageHandler.register(userScript, for: messageName)
            }
            guard !scriptMessageHandler.isMessageHandlerRegistered(for: messageName) else { continue }

            if #available(macOS 11.0, iOS 14.0, *) {
                let contentWorld: WKContentWorld = userScript.getContentWorld()
                if userScript is WKScriptMessageHandlerWithReply {
                    addScriptMessageHandler(scriptMessageHandler, contentWorld: contentWorld, name: messageName)
                } else {
                    add(scriptMessageHandler, contentWorld: contentWorld, name: messageName)
                }
            } else {
                add(scriptMessageHandler, name: messageName)
            }
        }
    }

}

public extension UserContentController {

    var contentBlockingAssetsInstalled: Bool {
        contentBlockingAssets != nil
    }

    // func awaitContentBlockingAssetsInstalled() async non-retaining `self`
    var awaitContentBlockingAssetsInstalled: () async -> Void {
        guard !contentBlockingAssetsInstalled else { return {} }
        return { [weak self] in
            // merge $contentBlockingAssets with Task cancellation completion event publisher
            let taskCancellationSubject = PassthroughSubject<ContentBlockingAssets?, Error>()
            guard let assetsPublisher = self?.$contentBlockingAssets else { return }

            // throw an error when current Task is cancelled
            let throwingPublisher = assetsPublisher
                .mapError({ _ -> Error in })
                .merge(with: taskCancellationSubject)
                .receive(on: DispatchQueue.main)

            // send completion to the throwingPublisher if current Task is cancelled
            try? await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { c in
                    var cancellable: AnyCancellable!
                    cancellable = throwingPublisher.sink /* completion: */ { _ in
                        withExtendedLifetime(cancellable) {
                            c.resume(with: .failure(CancellationError()))
                            cancellable.cancel()
                        }
                    } receiveValue: { assets in
                        guard assets != nil else { return }
                        withExtendedLifetime(cancellable) {
                            c.resume(with: .success( () ))
                            cancellable.cancel()
                        }
                    }
                } as Void

            } onCancel: {
                taskCancellationSubject.send(completion: .failure(CancellationError()))
            }
        }
    }

}

/// Script Message Handler only added once per UserScriptController for all the Message Names (to avoid race conditions for re-added User Scripts)
private class PermanentScriptMessageHandler: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {

    private struct WeakScriptMessageHandlerBox {
        weak var handler: WKScriptMessageHandler?
    }
    private var registeredMessageHandlers = [String: WeakScriptMessageHandlerBox]()

    var registeredMessageNames: [String] {
        Array(registeredMessageHandlers.keys)
    }

    func clear() {
        self.registeredMessageHandlers.removeAll()
    }

    func isMessageHandlerRegistered(for messageName: String) -> Bool {
        return self.registeredMessageHandlers[messageName] != nil
    }

    func messageHandler(for messageName: String) -> WKScriptMessageHandler? {
        return self.registeredMessageHandlers[messageName]?.handler
    }

    func register(_ handler: WKScriptMessageHandler, for messageName: String) {
        self.registeredMessageHandlers[messageName] = .init(handler: handler)
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let box = self.registeredMessageHandlers[message.messageName] else {
            assertionFailure("no registered message handler for \(message.messageName)")
            return
        }
        guard let handler = box.handler else {
            assertionFailure("handler for \(message.messageName) has been unregistered")
            return
        }
        handler.userContentController(userContentController, didReceive: message)
    }

    @available(macOS 11.0, iOS 14.0, *)
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let box = self.registeredMessageHandlers[message.messageName] else {
            assertionFailure("no registered message handler for \(message.messageName)")
            return
        }
        guard let handler = box.handler else {
            assertionFailure("handler for \(message.messageName) has been unregistered")
            return
        }
        assert(handler is WKScriptMessageHandlerWithReply)
        (handler as? WKScriptMessageHandlerWithReply)?.userContentController(userContentController, didReceive: message, replyHandler: replyHandler)
    }

}
