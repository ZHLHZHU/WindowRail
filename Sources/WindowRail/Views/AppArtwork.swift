import AppKit

/// The approved rail-and-windows mark, shared by the app icon and template image.
enum AppArtwork {
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawMark(in: context, rect: rect, color: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "WindowRail"
        return image
    }

    static func drawMark(in context: CGContext, rect: CGRect, color: CGColor) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 24, y: rect.height / 24)
        context.setStrokeColor(color)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: CGPoint(x: 2.5, y: 3))
        context.addLine(to: CGPoint(x: 2.5, y: 21))
        context.strokePath()

        let back = CGPath(roundedRect: CGRect(x: 6.5, y: 8.5, width: 12, height: 11),
                          cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        let front = CGPath(roundedRect: CGRect(x: 10, y: 4.5, width: 12, height: 11),
                           cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        // Occlude the rear outline without filling the foreground's transparent interior.
        context.saveGState()
        context.addRect(CGRect(x: 0, y: 0, width: 24, height: 24))
        context.addPath(front)
        context.clip(using: .evenOdd)
        context.addPath(back)
        context.strokePath()
        context.restoreGState()
        context.addPath(front)
        context.strokePath()
    }

    static func drawAppIcon(in context: CGContext, rect: CGRect) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 1024, y: rect.height / 1024)
        let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 184, cornerHeight: 184, transform: nil)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [CGColor(srgbRed: 0, green: 0.31, blue: 0.88, alpha: 1),
                      CGColor(srgbRed: 0.025, green: 0.49, blue: 1, alpha: 1)]
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
        context.saveGState()
        context.addPath(tile)
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100),
                                   end: CGPoint(x: 512, y: 924), options: [])
        context.restoreGState()
        drawMark(in: context, rect: CGRect(x: 210, y: 210, width: 604, height: 604),
                 color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    }
}
