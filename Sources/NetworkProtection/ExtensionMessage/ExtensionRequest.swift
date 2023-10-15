//
//  File.swift
//  
//
//  Created by ddg on 14/10/2023.
//

import Foundation

public enum ExtensionRequest: Codable {
    case changeTunnelSetting(_ change: TunnelSettings.Change)
}
