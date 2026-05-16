// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  QRCode.swift
//  DevPad
//
//  Two helpers around Apple's native frameworks:
//    • `generate(_:)` — turns a text payload into a crisp NSImage QR code
//      via CoreImage's `CIQRCodeGenerator`.
//    • `decode(_:)`   — reads any QR code(s) out of an NSImage via the
//      Vision framework (`VNDetectBarcodesRequest`).
//
//  Both calls run synchronously. Vision is already optimised internally
//  and the work is tiny (single small image, single barcode kind), so we
//  don't bother dispatching off the main thread.
//

import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

enum QRCodeError: LocalizedError {
    case empty
    case generationFailed
    case noQR
    case invalidImage
    case tooLong

    var errorDescription: String? {
        switch self {
        case .empty:            return "Input is empty."
        case .generationFailed: return "Could not generate QR image."
        case .noQR:             return "No QR code found in the image."
        case .invalidImage:     return "Couldn't read the image."
        case .tooLong:          return "Text is too long for a QR code."
        }
    }
}

enum QRCode {

    enum ErrorCorrection: String, CaseIterable, Identifiable {
        case low      = "L"
        case medium   = "M"
        case quartile = "Q"
        case high     = "H"

        var id: String { rawValue }

        var labelKey: String {
            switch self {
            case .low:      return "qr.errorCorrection.L"
            case .medium:   return "qr.errorCorrection.M"
            case .quartile: return "qr.errorCorrection.Q"
            case .high:     return "qr.errorCorrection.H"
            }
        }
    }

    // MARK: - Generate

    /// Produces an NSImage of a QR code that's at least `pixelSize` wide,
    /// using nearest-neighbour scaling so the modules stay sharp. When
    /// `centerIcon` is non-nil the image is composited over the centre of
    /// the QR with a small rounded white pad — branding-style.
    static func generate(_ text: String,
                         errorCorrection: ErrorCorrection = .medium,
                         pixelSize: CGFloat = 1024,
                         centerIcon: NSImage? = nil) throws -> NSImage {
        guard !text.isEmpty else { throw QRCodeError.empty }
        guard let data = text.data(using: .utf8) else {
            throw QRCodeError.generationFailed
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = errorCorrection.rawValue

        guard let ciImage = filter.outputImage else {
            // CoreImage returns nil for inputs the encoder can't fit at
            // the requested correction level — usually "too long".
            throw QRCodeError.tooLong
        }

        // Scale to roughly `pixelSize` px wide while keeping modules crisp.
        let scale = max(1, pixelSize / ciImage.extent.width)
        let scaled = ciImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        let rep = NSCIImageRep(ciImage: scaled)
        let qrImage = NSImage(size: rep.size)
        qrImage.addRepresentation(rep)

        if let icon = centerIcon {
            return composite(qrImage: qrImage, withCenterIcon: icon)
        }
        return qrImage
    }

    /// Overlays `icon` on the centre of `qrImage`. The icon sits inside a
    /// rounded-white pad so it stays legible against the QR modules. The
    /// icon's drawing rect is ~22 % of the QR's side, which is small
    /// enough that medium-or-higher error correction can still recover
    /// the obscured modules.
    private static func composite(qrImage: NSImage, withCenterIcon icon: NSImage) -> NSImage {
        let size = qrImage.size
        let iconRatio: CGFloat = 0.22
        let iconSize = NSSize(
            width: size.width * iconRatio,
            height: size.height * iconRatio
        )
        let pad: CGFloat = max(8, iconSize.width * 0.12)
        let cornerRadius: CGFloat = pad

        let iconRect = NSRect(
            x: (size.width - iconSize.width) / 2,
            y: (size.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        let padRect = iconRect.insetBy(dx: -pad, dy: -pad)

        let output = NSImage(size: size)
        output.lockFocus()
        defer { output.unlockFocus() }

        // Background QR.
        qrImage.draw(in: NSRect(origin: .zero, size: size))

        // White rounded pad behind the icon for legibility.
        NSColor.white.setFill()
        NSBezierPath(roundedRect: padRect,
                     xRadius: cornerRadius,
                     yRadius: cornerRadius).fill()

        // The icon itself — aspect-fit inside the pad.
        icon.draw(in: iconRect,
                  from: .zero,
                  operation: .sourceOver,
                  fraction: 1.0,
                  respectFlipped: true,
                  hints: nil)

        return output
    }

    /// PNG-encodes an NSImage (e.g. one returned by `generate`).
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Decode

    /// Reads the first QR-code payload found in the image, or throws.
    static func decode(_ image: NSImage) throws -> String {
        guard let cgImage = image.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ) else { throw QRCodeError.invalidImage }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            throw QRCodeError.invalidImage
        }

        guard let observations = request.results,
              let first = observations.first(where: { $0.payloadStringValue != nil }),
              let payload = first.payloadStringValue else {
            throw QRCodeError.noQR
        }
        return payload
    }
}
