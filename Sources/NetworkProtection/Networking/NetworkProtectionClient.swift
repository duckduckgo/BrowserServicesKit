//
//  NetworkProtectionClient.swift
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

public enum NetworkProtectionAuthenticationMethod {
    case inviteCode(String)
    case subscription(String)
}

protocol NetworkProtectionClient {
    func authenticate(withMethod method: NetworkProtectionAuthenticationMethod) async -> Result<String, NetworkProtectionClientError>
    func getLocations(authToken: String) async -> Result<[NetworkProtectionLocation], NetworkProtectionClientError>
    func getServers(authToken: String) async -> Result<[NetworkProtectionServer], NetworkProtectionClientError>
    func register(authToken: String,
                  requestBody: RegisterKeyRequestBody) async -> Result<[NetworkProtectionServer], NetworkProtectionClientError>
}

public enum NetworkProtectionClientError: Error, NetworkProtectionErrorConvertible {
    case failedToFetchLocationList(Error)
    case failedToParseLocationListResponse(Error)
    case failedToFetchServerList(Error)
    case failedToParseServerListResponse(Error)
    case failedToEncodeRegisterKeyRequest
    case failedToFetchRegisteredServers(Error)
    case failedToParseRegisteredServersResponse(Error)
    case failedToEncodeRedeemRequest
    case invalidInviteCode
    case failedToRedeemInviteCode(Error)
    case failedToRetrieveAuthToken(AuthenticationFailureResponse)
    case failedToParseRedeemResponse(Error)
    case invalidAuthToken
    case accessDenied

    var networkProtectionError: NetworkProtectionError {
        switch self {
        case .failedToFetchLocationList(let error): return .failedToFetchLocationList(error)
        case .failedToParseLocationListResponse(let error): return .failedToParseLocationListResponse(error)
        case .failedToFetchServerList(let error): return .failedToFetchServerList(error)
        case .failedToParseServerListResponse(let error): return .failedToParseServerListResponse(error)
        case .failedToEncodeRegisterKeyRequest: return .failedToEncodeRegisterKeyRequest
        case .failedToFetchRegisteredServers(let error): return .failedToFetchRegisteredServers(error)
        case .failedToParseRegisteredServersResponse(let error): return .failedToParseRegisteredServersResponse(error)
        case .failedToEncodeRedeemRequest: return .failedToEncodeRedeemRequest
        case .invalidInviteCode: return .invalidInviteCode
        case .failedToRedeemInviteCode(let error): return .failedToRedeemInviteCode(error)
        case .failedToRetrieveAuthToken(let response): return .failedToRetrieveAuthToken(response)
        case .failedToParseRedeemResponse(let error): return .failedToParseRedeemResponse(error)
        case .invalidAuthToken: return .invalidAuthToken
        case .accessDenied: return .vpnAccessRevoked
        }
    }
}

struct RegisterKeyRequestBody: Encodable {
    let publicKey: String
    let server: String?
    let country: String?
    let city: String?

    init(publicKey: PublicKey,
         serverSelection: RegisterServerSelection) {
        self.publicKey = publicKey.base64Key
        switch serverSelection {
        case .automatic:
            server = nil
            country = nil
            city = nil
        case .server(let name):
            server = name
            country = nil
            city = nil
        case .location(let country, let city):
            server = nil
            self.country = country
            self.city = city
        }
    }
}

enum RegisterServerSelection {
    case automatic
    case server(name: String)
    case location(country: String, city: String?)
}

struct RedeemInviteCodeRequestBody: Encodable {
    let code: String
}

struct ExchangeAccessTokenRequestBody: Encodable {
    let token: String
}

struct AuthenticationSuccessResponse: Decodable {
    let token: String
}

public struct AuthenticationFailureResponse: Decodable {
    public let message: String
}

final class NetworkProtectionBackendClient: NetworkProtectionClient {

    enum Constants {
        static let productionEndpoint = URL(string: "https://controller.netp.duckduckgo.com")!
        static let stagingEndpoint = URL(string: "https://staging1.netp.duckduckgo.com")!
    }

    private enum DecoderError: Error {
        case failedToDecode(key: String)
    }

    var serversURL: URL {
        endpointURL.appending("/servers")
    }

    var locationsURL: URL {
        endpointURL.appending("/locations")
    }

    var registerKeyURL: URL {
        endpointURL.appending("/register")
    }

    var redeemURL: URL {
        endpointURL.appending("/redeem")
    }

    var authorizeURL: URL {
        endpointURL.appending("/authorize")
    }

    private let decoder: JSONDecoder = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom({ decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            guard let date = formatter.date(from: dateString) else {
                throw DecoderError.failedToDecode(key: container.codingPath.last?.stringValue ?? String(describing: container.codingPath))
            }

            return date
        })

        return decoder
    }()

    private let endpointURL: URL
    private let isSubscriptionEnabled: Bool

    init(environment: VPNSettings.SelectedEnvironment = .default, isSubscriptionEnabled: Bool) {
        self.isSubscriptionEnabled = isSubscriptionEnabled
        self.endpointURL = environment.endpointURL
    }

    public enum GetLocationsError: CustomNSError {
        case noResponse
        case unexpectedStatus(status: Int)

        var errorCode: Int {
            switch self {
            case .noResponse:
                return 0
            case .unexpectedStatus(let status):
                // Adding a large number so that we can get a somewhat reasonable status code
                return 100000 + status
            }
        }
    }

    func getLocations(authToken: String) async -> Result<[NetworkProtectionLocation], NetworkProtectionClientError> {
        var request = URLRequest(url: locationsURL)
        request.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")
        let downloadedData: Data

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GetLocationsError.noResponse
            }
            switch response.statusCode {
            case 200: downloadedData = data
            case 401: return .failure(.invalidAuthToken)
            default:
                throw GetLocationsError.unexpectedStatus(status: response.statusCode)
            }
        } catch {
            return .failure(NetworkProtectionClientError.failedToFetchLocationList(error))
        }

        do {
            let decodedLocations = try decoder.decode([NetworkProtectionLocation].self, from: downloadedData)
            return .success(decodedLocations)
        } catch {
            return .failure(NetworkProtectionClientError.failedToParseLocationListResponse(error))
        }
    }

    public enum GetServersError: CustomNSError {
        case noResponse
        case unexpectedStatus(status: Int)

        var errorCode: Int {
            switch self {
            case .noResponse:
                return 0
            case .unexpectedStatus(let status):
                // Adding a large number so that we can get a somewhat reasonable status code
                return 100000 + status
            }
        }
    }

    func getServers(authToken: String) async -> Result<[NetworkProtectionServer], NetworkProtectionClientError> {
        var request = URLRequest(url: serversURL)
        request.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")
        let downloadedData: Data

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GetServersError.noResponse
            }
            switch response.statusCode {
            case 200: downloadedData = data
            case 401: return .failure(.invalidAuthToken)
            default:
                throw GetServersError.unexpectedStatus(status: response.statusCode)
            }
        } catch {
            return .failure(NetworkProtectionClientError.failedToFetchServerList(error))
        }

        do {
            let decodedServers = try decoder.decode([NetworkProtectionServer].self, from: downloadedData)
            return .success(decodedServers)
        } catch {
            return .failure(NetworkProtectionClientError.failedToParseServerListResponse(error))
        }
    }

    public enum RegisterError: CustomNSError {
        case noResponse
        case unexpectedStatus(status: Int)

        var errorCode: Int {
            switch self {
            case .noResponse:
                return 0
            case .unexpectedStatus(let status):
                // Adding a large number so that we can get a somewhat reasonable status code
                return 100000 + status
            }
        }
    }

    func register(authToken: String,
                  requestBody: RegisterKeyRequestBody) async -> Result<[NetworkProtectionServer], NetworkProtectionClientError> {
        let requestBodyData: Data

        do {
            requestBodyData = try JSONEncoder().encode(requestBody)
        } catch {
            return .failure(NetworkProtectionClientError.failedToEncodeRegisterKeyRequest)
        }

        var request = URLRequest(url: registerKeyURL)
        request.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = requestBodyData

        let responseData: Data

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw RegisterError.noResponse
            }
            switch response.statusCode {
            case 200:
                responseData = data
            case 401:
                return .failure(.invalidAuthToken)
            case 403 where isSubscriptionEnabled:
                return .failure(.accessDenied)
            default:
                throw RegisterError.unexpectedStatus(status: response.statusCode)
            }
        } catch {
            return .failure(NetworkProtectionClientError.failedToFetchRegisteredServers(error))
        }

        do {
            let decodedServers = try decoder.decode([NetworkProtectionServer].self, from: responseData)
            return .success(decodedServers)
        } catch {
            return .failure(NetworkProtectionClientError.failedToParseRegisteredServersResponse(error))
        }
    }

    public func authenticate(withMethod method: NetworkProtectionAuthenticationMethod) async -> Result<String, NetworkProtectionClientError> {
        switch method {
        case .inviteCode(let code):
            return await redeem(inviteCode: code)
        case .subscription(let accessToken):
            return await exchange(accessToken: accessToken)
        }
    }

    public enum AuthTokenError: CustomNSError {
        case noResponse
        case unexpectedStatus(status: Int)

        var errorCode: Int {
            switch self {
            case .noResponse:
                return 0
            case .unexpectedStatus(let status):
                // Adding a large number so that we can get a somewhat reasonable status code
                return 100000 + status
            }
        }
    }

    private func redeem(inviteCode: String) async -> Result<String, NetworkProtectionClientError> {
        let requestBody = RedeemInviteCodeRequestBody(code: inviteCode)
        return await retrieveAuthToken(requestBody: requestBody, endpoint: redeemURL)
    }

    private func exchange(accessToken: String) async -> Result<String, NetworkProtectionClientError> {
        let requestBody = ExchangeAccessTokenRequestBody(token: accessToken)
        return await retrieveAuthToken(requestBody: requestBody, endpoint: authorizeURL)
    }

    private func retrieveAuthToken<RequestBody: Encodable>(
        requestBody: RequestBody,
        endpoint: URL
    ) async -> Result<String, NetworkProtectionClientError> {
        let requestBodyData: Data

        do {
            requestBodyData = try JSONEncoder().encode(requestBody)
        } catch {
            return .failure(.failedToEncodeRedeemRequest)
        }

        var request = URLRequest(url: endpoint)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = requestBodyData

        let responseData: Data

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw AuthTokenError.noResponse
            }
            switch response.statusCode {
            case 200:
                responseData = data
            case 400:
                return .failure(.invalidInviteCode)
            default:
                do {
                    // Try to redeem the subscription backend error response first:
                    let decodedRedemptionResponse = try decoder.decode(AuthenticationFailureResponse.self, from: data)
                    return .failure(.failedToRetrieveAuthToken(decodedRedemptionResponse))
                } catch {
                    throw AuthTokenError.unexpectedStatus(status: response.statusCode)
                }
            }
        } catch {
            return .failure(NetworkProtectionClientError.failedToRedeemInviteCode(error))
        }

        do {
            let decodedRedemptionResponse = try decoder.decode(AuthenticationSuccessResponse.self, from: responseData)
            return .success(decodedRedemptionResponse.token)
        } catch {
            return .failure(NetworkProtectionClientError.failedToParseRedeemResponse(error))
        }
    }

}

extension URL {

    func appending(_ path: String) -> URL {
        if #available(macOS 13.0, iOS 16.0, *) {
            return appending(path: path)
        } else {
            return appendingPathComponent(path)
        }
    }

}
