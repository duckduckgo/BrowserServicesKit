//
//  RemoteMessageModel.swift
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

public struct RemoteMessageModel: Equatable, Codable {

    public let id: String
    public var content: RemoteMessageModelType?
    public let matchingRules: [Int]
    public let exclusionRules: [Int]

    public init(id: String, content: RemoteMessageModelType?, matchingRules: [Int], exclusionRules: [Int]) {
        self.id = id
        self.content = content
        self.matchingRules = matchingRules
        self.exclusionRules = exclusionRules
    }

    mutating func localizeContent(translation: RemoteMessageResponse.JsonContentTranslation) {
        guard let content = content else {
            return
        }

        switch content {
        case .small(let titleText, let descriptionText):
            self.content = .small(titleText: translation.titleText ?? titleText,
                                  descriptionText: translation.descriptionText ?? descriptionText)
        case .medium(let titleText, let descriptionText, let placeholder, let image):
            self.content = .medium(titleText: translation.titleText ?? titleText,
                                   descriptionText: translation.descriptionText ?? descriptionText,
                                   placeholder: placeholder,
                                   image: image)
        case .bigSingleAction(let titleText, let descriptionText, let placeholder, let image, let primaryActionText, let primaryAction):
            self.content = .bigSingleAction(titleText: translation.titleText ?? titleText,
                                            descriptionText: translation.descriptionText ?? descriptionText,
                                            placeholder: placeholder,
                                            image: image,
                                            primaryActionText: translation.primaryActionText ?? primaryActionText,
                                            primaryAction: primaryAction)
        case .bigTwoAction(let titleText, let descriptionText, let placeholder, let image, let primaryActionText, let primaryAction,
                           let secondaryActionText, let secondaryAction):
            self.content = .bigTwoAction(titleText: translation.titleText ?? titleText,
                                         descriptionText: translation.descriptionText ?? descriptionText,
                                         placeholder: placeholder,
                                         image: image,
                                         primaryActionText: translation.primaryActionText ?? primaryActionText,
                                         primaryAction: primaryAction,
                                         secondaryActionText: translation.secondaryActionText ?? secondaryActionText,
                                         secondaryAction: secondaryAction)
        case .promoSingleAction(let titleText, let descriptionText, let placeholder, let image, let actionText, let action):
            self.content = .promoSingleAction(titleText: translation.titleText ?? titleText,
                                              descriptionText: translation.descriptionText ?? descriptionText,
                                              placeholder: placeholder,
                                              image: image,
                                              actionText: translation.primaryActionText ?? actionText,
                                              action: action)

        }
    }
}

public enum RemoteMessageModelType: Codable, Equatable {
    case small(titleText: String, descriptionText: String)
    case medium(titleText: String, descriptionText: String, placeholder: RemotePlaceholder, image: RemoteImage?)
    case bigSingleAction(titleText: String, descriptionText: String, placeholder: RemotePlaceholder, image: RemoteImage?,
                         primaryActionText: String, primaryAction: RemoteAction)
    case bigTwoAction(titleText: String, descriptionText: String, placeholder: RemotePlaceholder, image: RemoteImage?,
                      primaryActionText: String, primaryAction: RemoteAction, secondaryActionText: String,
                      secondaryAction: RemoteAction)
    case promoSingleAction(titleText: String, descriptionText: String, placeholder: RemotePlaceholder, image: RemoteImage?,
                           actionText: String, action: RemoteAction)
}

public enum RemoteAction: Codable, Equatable {
    case share(value: String, title: String?)
    case url(value: String)
    case surveyURL(value: String)
    case appStore
    case dismiss
}

public enum RemotePlaceholder: String, Codable {
    case announce = "RemoteMessageAnnouncement"
    case ddgAnnounce = "RemoteMessageDDGAnnouncement"
    case criticalUpdate = "RemoteMessageCriticalAppUpdate"
    case appUpdate = "RemoteMessageAppUpdate"
    case macComputer = "RemoteMessageMacComputer"
    case newForMacAndWindows = "RemoteMessageNewForMacAndWindows"
    case vpnAnnounce = "RemoteMessageVPNAnnounce"
}

public struct RemoteImage: Codable, Equatable {

    public struct ImageURLs: Codable, Equatable {

        public let light: String
        public let dark: String?

    }

    let highRes: ImageURLs?

}
