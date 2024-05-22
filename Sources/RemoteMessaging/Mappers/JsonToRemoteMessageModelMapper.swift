//
//  JsonToRemoteMessageModelMapper.swift
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

import Common
import Foundation

// swiftlint:disable cyclomatic_complexity
private enum AttributesKey: String, CaseIterable {
    case locale
    case osApi
    case isInternalUser
    case appId
    case appVersion
    case atb
    case appAtb
    case searchAtb
    case expVariant
    case emailEnabled
    case widgetAdded
    case bookmarks
    case favorites
    case appTheme
    case daysSinceInstalled
    case daysSinceNetPEnabled

    func matchingAttribute(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        switch self {
        case .locale: return LocaleMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .osApi: return OSMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .isInternalUser: return IsInternalUserMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .appId: return AppIdMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .appVersion: return AppVersionMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .atb: return AtbMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .appAtb: return AppAtbMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .searchAtb: return SearchAtbMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .expVariant: return ExpVariantMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .emailEnabled: return EmailEnabledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .widgetAdded: return WidgetAddedMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .bookmarks: return BookmarksMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .favorites: return FavoritesMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .appTheme: return AppThemeMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .daysSinceInstalled: return DaysSinceInstalledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .daysSinceNetPEnabled: return DaysSinceNetPEnabledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        }
    }
}
// swiftlint:enable cyclomatic_complexity

struct JsonToRemoteMessageModelMapper {

    static func maps(jsonRemoteMessages: [RemoteMessageResponse.JsonRemoteMessage]) -> [RemoteMessageModel] {
        var remoteMessages: [RemoteMessageModel] = []
        jsonRemoteMessages.forEach { message in
            var remoteMessage = RemoteMessageModel(id: message.id,
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

    // swiftlint:disable cyclomatic_complexity function_body_length
    static func mapToContent(content: RemoteMessageResponse.JsonContent) -> RemoteMessageModelType? {
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
        case .promoSingleAction:
            guard let actionText = content.actionText,
                  !actionText.isEmpty,
                  let action = mapToAction(content.action)
            else {
                return nil
            }

            return .promoSingleAction(titleText: content.titleText,
                                      descriptionText: content.descriptionText,
                                      placeholder: mapToPlaceholder(content.placeholder),
                                      actionText: actionText,
                                      action: action)

        case .none:
            return nil
        }
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    static func mapToAction(_ jsonAction: RemoteMessageResponse.JsonMessageAction?) -> RemoteAction? {
        guard let jsonAction = jsonAction else {
            return nil
        }

        switch RemoteMessageResponse.JsonActionType(rawValue: jsonAction.type) {
        case .share:
            return .share(value: jsonAction.value, title: jsonAction.additionalParameters?["title"])
        case .url:
            return .url(value: jsonAction.value)
        case .surveyURL:
            return .surveyURL(value: jsonAction.value)
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
        case .macComputer:
            return .macComputer
        case .newForMacAndWindows:
            return .newForMacAndWindows
        case .vpnAnnounce:
            return .vpnAnnounce
        case .none:
            return .announce
        }
    }

    static func maps(jsonRemoteRules: [RemoteMessageResponse.JsonMatchingRule]) -> [RemoteConfigRule] {
        return jsonRemoteRules.map { jsonRule in
            let mappedAttributes = jsonRule.attributes.map { attribute in
                if let key = AttributesKey(rawValue: attribute.key) {
                    return key.matchingAttribute(jsonMatchingAttribute: attribute.value)
                } else {
                    os_log("Unknown attribute key %s", log: .remoteMessaging, type: .debug, attribute.key)
                    return UnknownMatchingAttribute(jsonMatchingAttribute: attribute.value)
                }
            }

            var mappedTargetPercentile: RemoteConfigTargetPercentile?

            if let jsonTargetPercentile = jsonRule.targetPercentile {
                mappedTargetPercentile = .init(before: jsonTargetPercentile.before)
            }

            return RemoteConfigRule(
                id: jsonRule.id,
                targetPercentile: mappedTargetPercentile,
                attributes: mappedAttributes
            )
        }
    }

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
