import AppKit

/// Draws the menu bar artwork: a row of horizontal Mac-style battery gauges (one per provider,
/// fill color = brand identity, fill level = remaining quota) followed by a bolt that lights up
/// while tokens are being processed.
enum MenuBarRenderer {

    // Layout (points)
    private static let batteryW: CGFloat = 24
    private static let batteryH: CGFloat = 11
    private static let batteryGap: CGFloat = 5
    private static let boltW: CGFloat = 11
    private static let sectionGap: CGFloat = 5
    private static let padding: CGFloat = 5

    static var barHeight: CGFloat { max(22, NSStatusBar.system.thickness) }

    static func render(statuses: [ProviderStatus],
                       live: LiveActivity,
                       frame: Int,
                       scale: CGFloat = 2,
                       isDark: Bool = true,
                       background: NSColor? = nil) -> NSImage {
        let height = barHeight
        let count = max(statuses.count, 0)
        let batteriesW = count == 0 ? batteryW : CGFloat(count) * batteryW + CGFloat(count - 1) * batteryGap
        let width = padding + batteriesW + sectionGap + boltW + padding

        return makeImage(width: width, height: height, scale: scale) { ctx in
            if let background {
                ctx.setFillColor(background.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            let cy = height / 2
            var x = padding

            if statuses.isEmpty {
                drawPlaceholder(ctx, at: CGPoint(x: x + batteryW / 2, y: cy), frame: frame, isDark: isDark)
            }
            for status in statuses {
                let body = CGRect(x: x, y: cy - batteryH / 2, width: batteryW, height: batteryH)
                drawBattery(ctx, body: body, status: status, frame: frame, isDark: isDark)
                x += batteryW + batteryGap
            }

            let boltRect = CGRect(x: padding + batteriesW + sectionGap, y: cy - 7, width: boltW, height: 14)
            drawBolt(ctx, in: boltRect, active: live.isActive, frame: frame, isDark: isDark)
        }
    }

    // MARK: - Battery

    private static func drawBattery(_ ctx: CGContext, body: CGRect, status: ProviderStatus, frame: Int, isDark: Bool) {
        let neutral = isDark ? NSColor.white : NSColor.black
        let radius: CGFloat = 2.5

        // Battery shell = body + terminal nub on the right.
        let nubW: CGFloat = 1.6
        let shell = CGRect(x: body.minX, y: body.minY, width: body.width - nubW - 0.5, height: body.height)
        let shellPath = CGPath(roundedRect: shell, cornerWidth: radius, cornerHeight: radius, transform: nil)

        let hasError = status.error != nil && status.windows.isEmpty
        let remaining = status.worstWindow.map { max(0, min(1, $0.remainingPercent / 100)) }

        // Track (unfilled interior).
        ctx.addPath(shellPath)
        ctx.setFillColor(neutral.withAlphaComponent(isDark ? 0.12 : 0.10).cgColor)
        ctx.fillPath()

        // Brand-colored fill from the left, proportional to remaining quota.
        if let remaining, !hasError {
            let inset = shell.insetBy(dx: 1.5, dy: 1.5)
            let fillW = max(0, inset.width * remaining)
            if fillW > 0.5 {
                let fill = CGRect(x: inset.minX, y: inset.minY, width: fillW, height: inset.height)
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: fill, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
                ctx.clip()
                ctx.setFillColor(Brand.ns(status.key).cgColor)
                ctx.fill(fill)
                // Subtle top highlight so even black/white reads as a filled cell.
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
                ctx.fill(CGRect(x: fill.minX, y: fill.maxY - inset.height * 0.4, width: fill.width, height: inset.height * 0.4))
                ctx.restoreGState()
                // Frame the filled cell so its extent is readable for any brand color — without
                // this, a near-black fill on a dark menu bar reads as an (inverted) empty cell.
                ctx.addPath(CGPath(roundedRect: fill, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
                ctx.setStrokeColor(neutral.withAlphaComponent(0.45).cgColor)
                ctx.setLineWidth(0.75)
                ctx.strokePath()
                // Bright leading edge at the fill boundary.
                ctx.setFillColor(neutral.withAlphaComponent(0.55).cgColor)
                ctx.fill(CGRect(x: fill.maxX - 0.5, y: inset.minY, width: 0.5, height: inset.height))
            }
        }

        // Shell outline.
        ctx.addPath(shellPath)
        ctx.setStrokeColor(neutral.withAlphaComponent(hasError ? 0.4 : 0.7).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        // Terminal nub.
        let nub = CGRect(x: shell.maxX + 0.3, y: body.midY - 2.5, width: nubW, height: 5)
        ctx.addPath(CGPath(roundedRect: nub, cornerWidth: 0.7, cornerHeight: 0.7, transform: nil))
        ctx.setFillColor(neutral.withAlphaComponent(0.7).cgColor)
        ctx.fillPath()

        if hasError {
            // Amber "!" hint.
            let cx = shell.midX
            ctx.setFillColor(NSColor.systemOrange.cgColor)
            ctx.fill(CGRect(x: cx - 0.6, y: shell.midY - 2, width: 1.2, height: 3))
            ctx.fillEllipse(in: CGRect(x: cx - 0.7, y: shell.midY + 1.6, width: 1.4, height: 1.4))
        }
    }

    private static func drawPlaceholder(_ ctx: CGContext, at center: CGPoint, frame: Int, isDark: Bool) {
        let pulse = 0.25 + 0.4 * (0.5 + 0.5 * sin(Double(frame) * 0.12))
        ctx.setFillColor((isDark ? NSColor.white : NSColor.black).withAlphaComponent(pulse).cgColor)
        let r: CGFloat = 2.5
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    // MARK: - Bolt (live activity)

    private static func drawBolt(_ ctx: CGContext, in r: CGRect, active: Bool, frame: Int, isDark: Bool) {
        // Classic lightning bolt polygon.
        let p = CGMutablePath()
        let pts: [(CGFloat, CGFloat)] = [
            (0.62, 1.0), (0.18, 0.46), (0.46, 0.46), (0.34, 0.0),
            (0.82, 0.58), (0.52, 0.58), (0.62, 1.0)
        ]
        for (i, pt) in pts.enumerated() {
            let point = CGPoint(x: r.minX + pt.0 * r.width, y: r.minY + pt.1 * r.height)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()

        if active {
            let pulse = 0.7 + 0.3 * sin(Double(frame) * 0.2)
            ctx.addPath(p)
            ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(pulse).cgColor)
            ctx.fillPath()
        } else {
            ctx.addPath(p)
            ctx.setStrokeColor((isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.28).cgColor)
            ctx.setLineWidth(0.8)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    // MARK: - Bitmap helper (retina-correct)

    private static func makeImage(width: CGFloat, height: CGFloat, scale: CGFloat,
                                  _ draw: (CGContext) -> Void) -> NSImage {
        let pxW = Int((width * scale).rounded())
        let pxH = Int((height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return NSImage(size: NSSize(width: width, height: height)) }
        rep.size = NSSize(width: width, height: height)

        // rep.size is in points while the backing store is `scale`× larger, so the context
        // already maps point-space → pixels. Drawing happens in points; no manual scaleBy.
        let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        let ctx = nsCtx.cgContext
        ctx.setShouldAntialias(true)
        draw(ctx)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    /// PNG bytes for the `--render-bar` debug flag (dark backdrop mimics the menu bar).
    static func png(statuses: [ProviderStatus], live: LiveActivity, frame: Int) -> Data? {
        let image = render(statuses: statuses, live: live, frame: frame,
                           scale: 6, isDark: true, background: NSColor(white: 0.13, alpha: 1))
        guard let rep = image.representations.first as? NSBitmapImageRep else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
