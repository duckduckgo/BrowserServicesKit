//
//  VPNLocationSelectionUseCase.swift
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

public enum VPNLocationSelectionError: Error {
    case countryNotFound
    case cityNotFound
    case fetchingLocationsFailed(Error)
}

public protocol VPNLocationSelecting {
    @discardableResult
    func select(_ selectedLocation: VPNSettings.SelectedLocation) async -> Result<Void, VPNLocationSelectionError>
}

public protocol VPNLocationSelectionSanitizing {
    func sanitizeCurrentSelection() async -> Result<Void, VPNLocationSelectionError>
}

public final class VPNLocationSelectionUseCase: VPNLocationSelecting, VPNLocationSelectionSanitizing {
    private let locationListRepository: NetworkProtectionLocationListRepository
    private let vpnSettings: VPNSettings

    public init(locationListRepository: NetworkProtectionLocationListRepository, vpnSettings: VPNSettings) {
        self.locationListRepository = locationListRepository
        self.vpnSettings = vpnSettings
    }

    public func select(_ selectedLocation: VPNSettings.SelectedLocation) async -> Result<Void, VPNLocationSelectionError> {
        switch selectedLocation {
        case .nearest:
            self.vpnSettings.selectedLocation = selectedLocation
            return .success(())
        case .location(let location):
            return await sanitizeSelectionAgainstAvailableLocations(location)
        }
    }

    public func sanitizeCurrentSelection() async -> Result<Void, VPNLocationSelectionError> {
        let currentSelection = vpnSettings.selectedLocation
        if let location = currentSelection.location {
            return await sanitizeSelectionAgainstAvailableLocations(location)
        } else {
            return .success(())
        }
    }

    private func sanitizeSelectionAgainstAvailableLocations(_ selection: NetworkProtectionSelectedLocation) async -> Result<Void, VPNLocationSelectionError> {
        let availableLocations: [NetworkProtectionLocation]
        do {
            availableLocations = try await locationListRepository.fetchLocationListIgnoringCache()
        } catch {
            return .failure(.fetchingLocationsFailed(error))
        }

        let availableSelections = availableLocations.flatMap { location in
            location.cities.map { city in  NetworkProtectionSelectedLocation(country: location.country, city: city.name) }
        }

        guard availableSelections.contains(selection) else {
            let selectedCountry = NetworkProtectionSelectedLocation(country: selection.country)
            if availableSelections.contains(selectedCountry) {
                vpnSettings.selectedLocation = .location(selectedCountry)
                return .failure(.cityNotFound)
            } else {
                vpnSettings.selectedLocation = .nearest
                return .failure(.countryNotFound)
            }
        }
        return .success(())
    }
}
