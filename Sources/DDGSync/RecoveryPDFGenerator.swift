//
//  RecoveryPDFGenerator.swift
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

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#else
#error("Unsupported OS")
#endif

public struct RecoveryPDFGenerator {

    static let qrCodeSize = 175

#if os(macOS)
    typealias PDFFont = NSFont
    typealias PDFImage = NSImage
    typealias PDFColor = NSColor
#elseif os(iOS)
    typealias PDFFont = UIFont
    typealias PDFImage = UIImage
    typealias PDFColor = UIColor
#endif

    public static func generate(_ code: String) -> Data {
        let data = NSMutableData()

        let templateURL = Bundle.module.url(forResource: "SyncPDFTemplate", withExtension: "png")!
        guard let templateData = try? Data(contentsOf: templateURL) else {
            fatalError()
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &mediaBox, nil)

        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = .init(cgContext: context!, flipped: false)
        #elseif os(iOS)
        UIGraphicsPushContext(context!)
        #endif

        context!.beginPDFPage(nil)

        #if os(iOS)
        let flipVertical: CGAffineTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: mediaBox.size.height)
        context!.concatenate(flipVertical)
        #endif

        let image = PDFImage(data: templateData)
        image?.draw(in: CGRect(x: 0, y: 0, width: 612, height: 792))

        // Draw the text

        #if os(macOS)
        let textY = -480
        #elseif os(iOS)
        let textY = 280
        #endif

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.55
        code.draw(in: CGRect(x: 290, y: textY, width: 264, height: 1000), withAttributes: [
                .font: PDFFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: PDFColor.black,
                .paragraphStyle: paragraphStyle,
                .kern: 2
            ])

        // Draw the qrcode
        #if os(macOS)
        let qrCodeY = 335
        #elseif os(iOS)
        let qrCodeY = 280
        #endif

        qrcode(code, size: qrCodeSize)
            .draw(in: CGRect(x: 75, y: qrCodeY, width: qrCodeSize, height: qrCodeSize))

        // Flush the data to the PDF file
        context!.endPDFPage()
        context?.closePDF()

        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = .init(cgContext: context!, flipped: false)
        #elseif os(iOS)
        UIGraphicsPopContext()
        #endif

        return data as Data
    }

    static func qrcode(_ text: String, size: Int) -> PDFImage {
        var qrImage = PDFImage()

        let data = Data(text.utf8)
        let qrCodeFilter: CIFilter = CIFilter.init(name: "CIQRCodeGenerator")!
        qrCodeFilter.setValue(data, forKey: "inputMessage")
        qrCodeFilter.setValue("H", forKey: "inputCorrectionLevel")

        guard let naturalSize = qrCodeFilter.outputImage?.extent.width else {
            assertionFailure("Failed to generate qr code")
            return qrImage
        }

        let scale = CGFloat(size) / naturalSize

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        guard let outputImage = qrCodeFilter.outputImage?.transformed(by: transform) else {
            assertionFailure("transformation failed")
            return qrImage
        }

        let colorParameters: [String: Any] = [
            "inputColor0": CIColor.black,
            "inputColor1": CIColor.white
        ]
        let coloredImage = outputImage.applyingFilter("CIFalseColor", parameters: colorParameters)

        if let image = CIContext().createCGImage(coloredImage, from: outputImage.extent) {
            #if os(macOS)
                qrImage = PDFImage(cgImage: image, size: CGSize(width: size, height: size))
            #elseif os(iOS)
                qrImage = PDFImage(cgImage: image)
            #endif
        }

        return qrImage
    }

}
