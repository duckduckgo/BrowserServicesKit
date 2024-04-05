//
//  VPNServerSelectionSanitizer.swift
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

public enum VPNServerSelectionError: Error {
    case countryNotFound
    case fetchingLocationsFailed(Error)
}

public protocol VPNServerSelectionSanitizing {
    func sanitizedServerSelectionMethod() async -> NetworkProtectionServerSelectionMethod
}

public final class VPNServerSelectionSanitizer: VPNServerSelectionSanitizing {
    private let locationListRepository: NetworkProtectionLocationListRepository
    private let vpnSettings: VPNSettings

    public init(locationListRepository: NetworkProtectionLocationListRepository, vpnSettings: VPNSettings) {
        self.locationListRepository = locationListRepository
        self.vpnSettings = vpnSettings
    }

    public func sanitizedServerSelectionMethod() async -> NetworkProtectionServerSelectionMethod {
        switch currentServerSelectionMethod {
        case .automatic, .preferredServer, .avoidServer:
            return currentServerSelectionMethod
        case .preferredLocation(let networkProtectionSelectedLocation):
            do {
                let location = try await sanitizeSelectionAgainstAvailableLocations(networkProtectionSelectedLocation)
                return .preferredLocation(location)
            } catch let error as VPNServerSelectionError {
                switch error {
                case .countryNotFound:
                    return .automatic
                case .fetchingLocationsFailed:
                    return currentServerSelectionMethod
                }
            } catch {
                return currentServerSelectionMethod
            }
        }
    }

    private func sanitizeSelectionAgainstAvailableLocations(_ selection: NetworkProtectionSelectedLocation) async throws -> NetworkProtectionSelectedLocation {
        let availableLocations: [NetworkProtectionLocation]
        do {
            availableLocations = try await locationListRepository.fetchLocationListIgnoringCache()
        } catch {
            throw VPNServerSelectionError.fetchingLocationsFailed(error)
        }

        let availableCitySelections = availableLocations.flatMap { location in
            location.cities.map { city in  NetworkProtectionSelectedLocation(country: location.country, city: city.name) }
        }

        let availableCountrySelections = availableLocations.map { NetworkProtectionSelectedLocation(country: $0.country) }

        let availableSelections = availableCitySelections + availableCountrySelections

        guard availableSelections.contains(selection) else {
            let selectedCountry = NetworkProtectionSelectedLocation(country: selection.country)
            if availableCitySelections.contains(selectedCountry) {
                return selectedCountry
            } else {
                throw VPNServerSelectionError.countryNotFound
            }
        }
        return selection
    }

    private var currentServerSelectionMethod: NetworkProtectionServerSelectionMethod {
        var serverSelectionMethod: NetworkProtectionServerSelectionMethod

        switch vpnSettings.selectedLocation {
        case .nearest:
            serverSelectionMethod = .automatic
        case .location(let networkProtectionSelectedLocation):
            serverSelectionMethod = .preferredLocation(networkProtectionSelectedLocation)
        }

        switch vpnSettings.selectedServer {
        case .automatic:
            break
        case .endpoint(let string):
            // Selecting a specific server will override locations setting
            // Only available in debug
            serverSelectionMethod = .preferredServer(serverName: string)
        }

        return serverSelectionMethod
    }
}
