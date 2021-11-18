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

public protocol PrivacyConfigurationDataProvider {

    var embeddedPrivacyConfigEtag: String { get }
    var embeddedPrivacyConfig: Data { get }
}

public class PrivacyConfigurationManager {
    
    public enum ReloadResult {
        case embedded
        case embeddedFallback
        case downloaded
    }

    enum ParsingError: Error {
        case dataMismatch
    }
    
    public typealias ConfigurationData = (data: PrivacyConfigurationData, etag: String)
    
    private let lock = NSLock()
    private let dataProvider: PrivacyConfigurationDataProvider
    private let localProtection: DomainsProtectionStore
    
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
                let jsonData = dataProvider.embeddedPrivacyConfig
                let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                let configData = PrivacyConfigurationData(json: json!)
                _embeddedConfigData = (configData, dataProvider.embeddedPrivacyConfigEtag)
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

    public init(dataProvider: PrivacyConfigurationDataProvider, localProtection: DomainsProtectionStore) {
        self.dataProvider = dataProvider
        self.localProtection = localProtection

//        reload(etag: UserDefaultsETagStorage().etag(for: .privacyConfiguration)) FIXME
    }
    
//    public static let shared = PrivacyConfigurationManager()
    
    public var privacyConfig: PrivacyConfiguration {
        if let fetchedData = fetchedConfigData {
            return AppPrivacyConfiguration(data: fetchedData.data,
                                           identifier: fetchedData.etag,
                                           localProtection: localProtection)
        }

        return AppPrivacyConfiguration(data: embeddedConfigData.data,
                                       identifier: embeddedConfigData.etag,
                                       localProtection: localProtection)
    }
    
    @discardableResult
    public func reload(etag: String?, data: Data?) -> ReloadResult {
        
        let result: ReloadResult
        
        if let etag = etag, let data = data {
            result = .downloaded
            
            do {
                // This might fail if the downloaded data is corrupt or format has changed unexpectedly
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let configData = PrivacyConfigurationData(json: json)
                    fetchedConfigData = (configData, etag)
                } else {
                    throw ParsingError.dataMismatch
                }
            } catch {
//                Pixel.fire(pixel: .privacyConfigurationParseFailed, error: error)
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
