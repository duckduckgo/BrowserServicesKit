//
//  APIResult.swift
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

import Foundation

/// A protocol representing a suggestion result
public protocol SuggestionResultProtocol: Codable {}

/// A structure representing a phrase suggestion
public struct Phrase: SuggestionResultProtocol {
    let phrase: String
    let isNav: Bool?
}

/// A structure representing an instant answer suggestion
public struct InstantAnswer: SuggestionResultProtocol {
    struct CurrentWeather: Codable {
        let conditionCode: String?
        let temperature: Double?
    }

    struct DayForecast: Codable {
        let temperatureMax: Double?
        let temperatureMin: Double?
    }

    struct ForecastDaily: Codable {
        let days: [DayForecast]?
    }

    struct IAAnswer: Codable {
        let currentWeather: CurrentWeather?
        let forecastDaily: ForecastDaily?
        let location: String?
    }

    let ia: String
    let answer: IAAnswer?
    let seeMore: String?
}

/// A structure representing the API result
public struct APIResult: Codable {
    var items = [SuggestionResultProtocol]()

    init() {}

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let iaResult = try? container.decode(InstantAnswer.self) {
                items.append(iaResult)
            } else if let suggestion = try? container.decode(Phrase.self) {
                items.append(suggestion)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for item in items {
            if let iaResult = item as? InstantAnswer {
                try container.encode(iaResult)
            } else if let suggestion = item as? Phrase {
                try container.encode(suggestion)
            }
        }
    }
}
