//
//  PrivacyConfigurationManager.swift
//  DuckDuckGo
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
import Combine

public protocol EmbeddedDataProvider {

    var embeddedDataEtag: String { get }
    var embeddedData: Data { get }
}

public protocol PrivacyConfigurationManaging {

    var currentConfig: Data { get }
    var updatesPublisher: AnyPublisher<Void, Never> { get }
    var privacyConfig: PrivacyConfiguration { get }

    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult
}

public class PrivacyConfigurationManager: PrivacyConfigurationManaging {
    
    public enum ReloadResult: Equatable {
        case embedded
        case embeddedFallback
        case downloaded
    }

    enum ParsingError: Error {
        case dataMismatch
    }
    
    public typealias ConfigurationData = (rawData: Data, data: PrivacyConfigurationData, etag: String)
    
    private let lock = NSLock()
    private let embeddedDataProvider: EmbeddedDataProvider
    private let localProtection: DomainsProtectionStore
    
    private let updatesSubject = PassthroughSubject<Void, Never>()
    public var updatesPublisher: AnyPublisher<Void, Never> {
        updatesSubject.eraseToAnyPublisher()
    }
    
    private var _fetchedConfigData: ConfigurationData?
    private(set) public var fetchedConfigData: ConfigurationData? {
        get {
            lock.lock()
            let data = _fetchedConfigData
            lock.unlock()
            return data
        }
        set {
            lock.lock()
            _fetchedConfigData = newValue
            lock.unlock()
        }
    }
    
    private var _embeddedConfigData: ConfigurationData!
    private(set) public var embeddedConfigData: ConfigurationData {
        get {
            lock.lock()

            let data: ConfigurationData
            // List is loaded lazily when needed
            if let embedded = _embeddedConfigData {
                data = embedded
            } else {
                let jsonData = embeddedDataProvider.embeddedData
                let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                let configData = PrivacyConfigurationData(json: json!)
                _embeddedConfigData = (jsonData, configData, embeddedDataProvider.embeddedDataEtag)
                data = _embeddedConfigData
            }
            lock.unlock()
            return data
        }
        set {
            lock.lock()
            _embeddedConfigData = newValue
            lock.unlock()
        }
    }

    private let errorReporting: EventMapping<ContentBlockerDebugEvents>?

    public init(fetchedETag: String?,
                fetchedData: Data?,
                embeddedDataProvider: EmbeddedDataProvider,
                localProtection: DomainsProtectionStore,
                errorReporting: EventMapping<ContentBlockerDebugEvents>? = nil) {
        self.embeddedDataProvider = embeddedDataProvider
        self.localProtection = localProtection
        self.errorReporting = errorReporting

        reload(etag: fetchedETag, data: fetchedData)
    }
    
    public var privacyConfig: PrivacyConfiguration {
//        if let fetchedData = fetchedConfigData {
//            return AppPrivacyConfiguration(data: fetchedData.data,
//                                           identifier: fetchedData.etag,
//                                           localProtection: localProtection)
//        }

        return AppPrivacyConfiguration(data: embeddedConfigData.data,
                                       identifier: embeddedConfigData.etag,
                                       localProtection: localProtection)
    }
    
    public var currentConfig: Data {
        if let fetchedData = fetchedConfigData {
            return fetchedData.rawData
        }
        return embeddedConfigData.rawData
    }

    @discardableResult
    public func reload(etag: String?, data: Data?) -> ReloadResult {
        
        defer { self.updatesSubject.send() }
        
        let result: ReloadResult
        
        if let etag = etag, let data = data {
            result = .downloaded
            
            do {
                // This might fail if the downloaded data is corrupt or format has changed unexpectedly
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let configData = PrivacyConfigurationData(json: json)
                    fetchedConfigData = (data, configData, etag)
                } else {
                    throw ParsingError.dataMismatch
                }
            } catch {
                errorReporting?.fire(.privacyConfigurationParseFailed, error: error)
                fetchedConfigData = nil
                return .embeddedFallback
            }
        } else {
            fetchedConfigData = nil
            result = .embedded
        }
        
        return result
    }
}
