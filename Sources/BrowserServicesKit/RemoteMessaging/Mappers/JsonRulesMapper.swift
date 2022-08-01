//
//  JsonRulesMapper.swift
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

struct JsonRulesMapper {

    static func localeMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = LocaleMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func osApiMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = OSMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func flavorMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = FlavorMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func appIdMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = AppIdMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func appVersionMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = AppVersionMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func atbMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = AtbMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func appAtbMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = AppAtbMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func searchAtbMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = SearchAtbMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func expVariantMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = ExpVariantMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func emailEnabledMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = EmailEnabledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func widgetAddedMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = WidgetAddedMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func bookmarksMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = BookmarksMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func favoritesMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = FavoritesMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func appThemeMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = AppThemeMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func daysSinceInstalledMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = DaysSinceInstalledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }

    static func unknownMapper(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        let matchingAttribute = UnknownMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        return matchingAttribute
    }
}
