import AppKit
import CryptoKit
import Foundation

enum ArtworkGenerator {
    static func textIconPNG(title: String, side: Int = 48) throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ConversionError.invalidResource("default icon")
        }
        let label = iconLabel(for: title)
        let digest = Data(SHA256.hash(data: Data(title.utf8)))
        let hue = CGFloat(digest[0]) / 255
        let background = NSColor(calibratedHue: hue, saturation: 0.62, brightness: 0.58, alpha: 1)
        let inset = CGFloat(side) * 0.08

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        background.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: side, height: side),
                     xRadius: CGFloat(side) * 0.18, yRadius: CGFloat(side) * 0.18).fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let border = NSBezierPath(roundedRect: NSRect(x: inset / 2, y: inset / 2,
                                                      width: CGFloat(side) - inset,
                                                      height: CGFloat(side) - inset),
                                  xRadius: CGFloat(side) * 0.14, yRadius: CGFloat(side) * 0.14)
        border.lineWidth = max(1, CGFloat(side) * 0.035)
        border.stroke()

        let fontSize = CGFloat(side) * (label.count > 1 ? 0.39 : 0.53)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: label, attributes: attributes)
        let size = string.size()
        string.draw(in: NSRect(x: 0, y: (CGFloat(side) - size.height) / 2 - 1,
                               width: CGFloat(side), height: size.height + 2))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ConversionError.invalidResource("default icon PNG")
        }
        return png
    }

    static func iconLabel(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        if first.isASCII { return String(trimmed.prefix(2)).uppercased() }
        return String(first)
    }
}
