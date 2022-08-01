//
//  JsonRemoteMessageMapper.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import os.log

private enum AttributesKey: CaseIterable {
    static let locale             = "locale"
    static let osApi              = "osApi"
    static let flavor             = "flavor"
    static let appId              = "appId"
    static let appVersion         = "appVersion"
    static let atb                = "atb"
    static let appAtb             = "appAtb"
    static let searchAtb          = "searchAtb"
    static let expVariant         = "expVariant"
    static let emailEnabled       = "emailEnabled"
    static let widgetAdded        = "widgetAdded"
    static let bookmarks          = "bookmarks"
    static let favorites          = "favorites"
    static let appTheme           = "appTheme"
    static let daysSinceInstalled = "daysSinceInstalled"
}

struct JsonRemoteMessageMapper {

    static func maps(jsonRemoteMessages: [RemoteMessageResponse.JsonRemoteMessage]) -> [RemoteMessage] {
        var remoteMessages: [RemoteMessage] = []
        jsonRemoteMessages.forEach { message in
            var remoteMessage = RemoteMessage(id: message.id,
                                              content: mapToContent(content: message.content),
                                              matchingRules: message.matchingRules ?? [],
                                              exclusionRules: message.exclusionRules ?? [])

            if let translation = getTranslation(from: message.translations, for: Locale.current) {
                remoteMessage.localizeContent(translation: translation)
            }

            remoteMessages.append(remoteMessage)
        }
        return remoteMessages
    }

    // swiftlint:disable function_body_length
    static func mapToContent(content: RemoteMessageResponse.JsonContent) -> RemoteMessageType? {
        switch RemoteMessageResponse.JsonMessageType(rawValue: content.messageType) {
        case .small:
            guard !content.titleText.isEmpty, !content.descriptionText.isEmpty else {
                return nil
            }

            return .small(titleText: content.titleText,
                          descriptionText: content.descriptionText)
        case .medium:
            guard !content.titleText.isEmpty, !content.descriptionText.isEmpty else {
                return nil
            }

            return .medium(titleText: content.titleText,
                           descriptionText: content.descriptionText,
                           placeholder: mapToPlaceholder(content.placeholder))
        case .bigSingleAction:
            guard let primaryActionText = content.primaryActionText,
                  !primaryActionText.isEmpty,
                  let action = mapToAction(content.primaryAction)
            else {
                return nil
            }

            return .bigSingleAction(titleText: content.titleText,
                                    descriptionText: content.descriptionText,
                                    placeholder: mapToPlaceholder(content.placeholder),
                                    primaryActionText: primaryActionText,
                                    primaryAction: action)
        case .bigTwoAction:
            guard let primaryActionText = content.primaryActionText,
                  !primaryActionText.isEmpty,
                  let primaryAction = mapToAction(content.primaryAction),
                  let secondaryActionText = content.secondaryActionText,
                  !secondaryActionText.isEmpty,
                  let secondaryAction = mapToAction(content.secondaryAction)
            else {
                return nil
            }

            return .bigTwoAction(titleText: content.titleText,
                                 descriptionText: content.descriptionText,
                                 placeholder: mapToPlaceholder(content.placeholder),
                                 primaryActionText: primaryActionText,
                                 primaryAction: primaryAction,
                                 secondaryActionText: secondaryActionText,
                                 secondaryAction: secondaryAction)
        case .none:
            return nil
        }
    }
    // swiftlint:enable function_body_length

    static func mapToAction(_ jsonAction: RemoteMessageResponse.JsonMessageAction?) -> RemoteAction? {
        guard let jsonAction = jsonAction else {
            return nil
        }

        switch RemoteMessageResponse.JsonActionType(rawValue: jsonAction.type) {
        case .url:
            return .url(value: jsonAction.value)
        case .appStore:
            return .appStore
        case .dismiss:
            return .dismiss
        case .none:
            return nil
        }
    }

    static func mapToPlaceholder(_ jsonPlaceholder: String?) -> RemotePlaceholder {
        guard let jsonPlaceholder = jsonPlaceholder else {
            return .announce
        }

        switch RemoteMessageResponse.JsonPlaceholder(rawValue: jsonPlaceholder) {
        case .announce:
            return .announce
        case .appUpdate:
            return .appUpdate
        case .ddgAnnounce:
            return .ddgAnnounce
        case .criticalUpdate:
            return .criticalUpdate
        case .none:
            return .announce
        }
    }

    // swiftlint:disable cyclomatic_complexity
    static func maps(jsonRemoteRules: [RemoteMessageResponse.JsonMatchingRule]) -> [Int: [MatchingAttribute]] {
        var rules: [Int: [MatchingAttribute]] = [:]
        jsonRemoteRules.forEach { rule in
            var matchingAttributes: [MatchingAttribute] = []
            rule.attributes.forEach { attribute in
                switch attribute.key {
                case AttributesKey.locale:
                    matchingAttributes.append(JsonRulesMapper.localeMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.osApi:
                    matchingAttributes.append(JsonRulesMapper.osApiMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.flavor:
                    matchingAttributes.append(JsonRulesMapper.flavorMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.appId:
                    matchingAttributes.append(JsonRulesMapper.appIdMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.appVersion:
                    matchingAttributes.append(JsonRulesMapper.appVersionMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.atb:
                    matchingAttributes.append(JsonRulesMapper.atbMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.appAtb:
                    matchingAttributes.append(JsonRulesMapper.appAtbMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.searchAtb:
                    matchingAttributes.append(JsonRulesMapper.searchAtbMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.expVariant:
                    matchingAttributes.append(JsonRulesMapper.expVariantMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.emailEnabled:
                    matchingAttributes.append(JsonRulesMapper.emailEnabledMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.widgetAdded:
                    matchingAttributes.append(JsonRulesMapper.widgetAddedMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.bookmarks:
                    matchingAttributes.append(JsonRulesMapper.bookmarksMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.favorites:
                    matchingAttributes.append(JsonRulesMapper.favoritesMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.appTheme:
                    matchingAttributes.append(JsonRulesMapper.appThemeMapper(jsonMatchingAttribute: attribute.value))
                case AttributesKey.daysSinceInstalled:
                    matchingAttributes.append(JsonRulesMapper.daysSinceInstalledMapper(jsonMatchingAttribute: attribute.value))
                default:
                    os_log("Unknown attribute key %s", log: .remoteMessaging, type: .debug, attribute.key)
                    matchingAttributes.append(JsonRulesMapper.unknownMapper(jsonMatchingAttribute: attribute.value))
                }
            }
            rules[rule.id] = matchingAttributes
        }
        return rules
    }
    // swiftlint:enable cyclomatic_complexity

    static func getTranslation(from translations: [String: RemoteMessageResponse.JsonContentTranslation]?,
                               for locale: Locale) -> RemoteMessageResponse.JsonContentTranslation? {
        guard let translations = translations else {
            return nil
        }

        if let translation = translations[LocaleMatchingAttribute.localeIdentifierAsJsonFormat(locale.identifier)] {
            return translation
        }

        return nil
    }
}
