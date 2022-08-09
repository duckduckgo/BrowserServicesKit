//
//  AdClickAttributionDebugEvents.swift
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

public enum AdClickAttributionEvents {
    
    public enum Parameters {
        public static let domainDetection = "domainDetection"
        public static let heuristicDetectionEnabled = "heuristicDetectionEnabled"
        public static let domainDetectionEnabled = "domainDetectionEnabled"
    }
 
    case adAttributionDetected
    case adAttributionActive
}

// swiftlint:disable identifier_name

public enum AdClickAttributionDebugEvents {
 
    case adAttributionGlobalAttributedRulesDoNotExist
    case adAttributionCompilationFailedForAttributedRulesList
    case adAttributionLogicUnexpectedStateOnInheritedAttribution
    case adAttributionLogicUnexpectedStateOnRulesCompiled
    case adAttributionLogicUnexpectedStateOnRulesCompilationFailed
    case adAttributionDetectionInvalidDomainInParameter
    case adAttributionDetectionHeuristicsDidNotMatchDomain
    
}

// swiftlint:enable identifier_name
