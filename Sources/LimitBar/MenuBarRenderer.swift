import AppKit

/// Draws the compact menu bar artwork: one "liquid battery" chip per provider (fill level =
/// remaining quota, brand glyph + brand underline for identity) followed by an animated
/// waterfall of recent live token throughput. Pure drawing — no app state.
enum MenuBarRenderer {

    // Layout (points)
    private static let chipW: CGFloat = 16
    private static let chipGap: CGFloat = 7
    private static let bodyInsetY: CGFloat = 4
    private static let waterfallW: CGFloat = 46
    private static let sectionGap: CGFloat = 7
    private static let padding: CGFloat = 5
    private static let maxProviders = 4

    static var barHeight: CGFloat { max(22, NSStatusBar.system.thickness) }

    static func render(statuses: [ProviderStatus],
                       live: LiveActivity,
                       waterfall: [Double],
                       frame: Int,
                       scale: CGFloat = 2,
                       background: NSColor? = nil) -> NSImage {
        let providers = Array(statuses.prefix(maxProviders))
        let height = barHeight
        let chipsW = providers.isEmpty
            ? chipW
            : CGFloat(providers.count) * chipW + CGFloat(providers.count - 1) * chipGap
        let width = padding + chipsW + sectionGap + waterfallW + padding

        return makeImage(width: width, height: height, scale: scale) { ctx in
            if let background {
                ctx.setFillColor(background.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            var x = padding
            if providers.isEmpty {
                drawPlaceholder(ctx, CGRect(x: x, y: bodyInsetY, width: chipW, height: height - bodyInsetY * 2), frame: frame)
            }
            for status in providers {
                let body = CGRect(x: x, y: bodyInsetY, width: chipW, height: height - bodyInsetY * 2)
                drawChip(ctx, body: body, status: status, frame: frame)
                x += chipW + chipGap
            }
            let wfX = padding + chipsW + sectionGap
            let wfRect = CGRect(x: wfX, y: bodyInsetY - 1, width: waterfallW, height: height - (bodyInsetY - 1) * 2)
            drawWaterfall(ctx, rect: wfRect, samples: waterfall, active: live.isActive, frame: frame)
        }
    }

    // MARK: - Chip

    private static func drawChip(_ ctx: CGContext, body: CGRect, status: ProviderStatus, frame: Int) {
        let radius: CGFloat = 4
        // Reserve 2px at the bottom for the brand underline.
        let underlineH: CGFloat = 2
        let tank = CGRect(x: body.minX, y: body.minY + underlineH + 1,
                          width: body.width, height: body.height - underlineH - 1)
        let tankPath = CGPath(roundedRect: tank, cornerWidth: radius, cornerHeight: radius, transform: nil)

        let hasError = status.error != nil && status.windows.isEmpty
        let remaining = status.worstWindow.map { max(0, min(1, $0.remainingPercent / 100)) }

        // Battery terminal nub.
        let nub = CGRect(x: tank.midX - 3, y: tank.maxY - 0.5, width: 6, height: 1.5)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.45).cgColor)
        ctx.addPath(CGPath(roundedRect: nub, cornerWidth: 0.75, cornerHeight: 0.75, transform: nil))
        ctx.fillPath()

        // Liquid fill (clipped to the tank), with a wavy animated surface.
        if let remaining, !hasError {
            ctx.saveGState()
            ctx.addPath(tankPath); ctx.clip()
            let color = levelColor(remaining)
            let yLevel = tank.minY + remaining * tank.height
            let wave = CGMutablePath()
            wave.move(to: CGPoint(x: tank.minX, y: tank.minY))
            let steps = 26
            let phase = Double(frame) * 0.22
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let px = tank.minX + tank.width * CGFloat(t)
                let py = yLevel + CGFloat(sin(t * Double.pi * 3 + phase)) * 0.8
                wave.addLine(to: CGPoint(x: px, y: py))
            }
            wave.addLine(to: CGPoint(x: tank.maxX, y: tank.minY))
            wave.closeSubpath()
            ctx.addPath(wave)
            ctx.setFillColor(color.withAlphaComponent(0.92).cgColor)
            ctx.fillPath()
            // Soft surface highlight line.
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(0.75)
            ctx.addPath(wave); ctx.strokePath()
            ctx.restoreGState()
        }

        // Tank outline.
        ctx.addPath(tankPath)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(hasError ? 0.3 : 0.55).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        // Brand glyph centered in the tank.
        let g = min(tank.width, tank.height) * 0.58
        let glyphRect = CGRect(x: tank.midX - g / 2, y: tank.midY - g / 2, width: g, height: g)
        drawGlyph(ctx, ProviderGlyph.forKey(status.key), in: glyphRect,
                  alpha: hasError ? 0.4 : 0.95)

        // Brand underline (identity), or an amber warning bar on error.
        let underline = CGRect(x: body.minX + 1, y: body.minY, width: body.width - 2, height: underlineH)
        ctx.addPath(CGPath(roundedRect: underline, cornerWidth: 1, cornerHeight: 1, transform: nil))
        ctx.setFillColor(hasError ? NSColor.systemOrange.cgColor : brandColor(status.key))
        ctx.fillPath()

        if hasError {
            // Pulsing dot to flag the issue.
            let pulse = 0.5 + 0.5 * sin(Double(frame) * 0.18)
            let r: CGFloat = 1.6
            ctx.setFillColor(NSColor.systemOrange.withAlphaComponent(0.5 + 0.5 * pulse).cgColor)
            ctx.fillEllipse(in: CGRect(x: tank.maxX - r * 2, y: tank.maxY - r * 2, width: r * 2, height: r * 2))
        }
    }

    private static func drawPlaceholder(_ ctx: CGContext, _ rect: CGRect, frame: Int) {
        let pulse = 0.3 + 0.4 * (0.5 + 0.5 * sin(Double(frame) * 0.12))
        ctx.setFillColor(NSColor.white.withAlphaComponent(pulse).cgColor)
        let r: CGFloat = 3
        ctx.fillEllipse(in: CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2))
    }

    // MARK: - Waterfall

    private static func drawWaterfall(_ ctx: CGContext, rect: CGRect, samples: [Double], active: Bool, frame: Int) {
        guard !samples.isEmpty else { return }
        let peak = max(samples.max() ?? 0, 1)
        let n = samples.count
        let barW = rect.width / CGFloat(n)
        let baseline = rect.minY + 1

        if peak <= 1 {
            // Idle: a dim flat baseline with a slow travelling sparkle.
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
            ctx.fill(CGRect(x: rect.minX, y: baseline, width: rect.width, height: 1))
            let sx = rect.minX + rect.width * CGFloat((Double(frame) * 0.01).truncatingRemainder(dividingBy: 1))
            ctx.setFillColor(NSColor.cyan.withAlphaComponent(0.5).cgColor)
            ctx.fillEllipse(in: CGRect(x: sx, y: baseline - 0.5, width: 2, height: 2))
            return
        }

        for (i, sample) in samples.enumerated() {
            let frac = max(0, min(1, sample / peak))
            let h = frac * (rect.height - 2)
            guard h > 0.2 else { continue }
            let x = rect.minX + CGFloat(i) * barW
            // Recent samples (right side) are brighter.
            let recency = CGFloat(i) / CGFloat(n - 1)
            let alpha = (active ? 0.35 : 0.22) + recency * 0.55
            let bar = CGRect(x: x, y: baseline, width: max(barW - 0.6, 0.8), height: h)
            ctx.setFillColor(waterfallColor(frac).withAlphaComponent(alpha).cgColor)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 0.6, cornerHeight: 0.6, transform: nil))
            ctx.fillPath()
        }
    }

    private static func waterfallColor(_ frac: CGFloat) -> NSColor {
        // Cyan → magenta as throughput climbs.
        NSColor(srgbRed: 0.25 + frac * 0.65, green: 0.85 - frac * 0.35, blue: 0.95, alpha: 1)
    }

    // MARK: - Glyphs

    private enum ProviderGlyph {
        case claude, codex, openrouter, generic
        static func forKey(_ key: String) -> ProviderGlyph {
            switch key {
            case "claude": return .claude
            case "codex": return .codex
            case "openrouter": return .openrouter
            default: return .generic
            }
        }
    }

    private static func drawGlyph(_ ctx: CGContext, _ glyph: ProviderGlyph, in r: CGRect, alpha: CGFloat) {
        let white = NSColor.white.withAlphaComponent(alpha).cgColor
        let cx = r.midX, cy = r.midY
        switch glyph {
        case .claude:
            // Four-point sparkle.
            let outer = r.width / 2
            let inner = outer * 0.34
            let path = CGMutablePath()
            for i in 0..<8 {
                let radius = i % 2 == 0 ? outer : inner
                let angle = Double(i) * .pi / 4 + .pi / 2
                let p = CGPoint(x: cx + CGFloat(cos(angle)) * radius, y: cy + CGFloat(sin(angle)) * radius)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.addPath(path); ctx.setFillColor(white); ctx.fillPath()

        case .codex:
            // Solid hexagon (OpenAI-ish six-fold mark).
            let radius = r.width / 2
            let path = CGMutablePath()
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3 + .pi / 6
                let p = CGPoint(x: cx + CGFloat(cos(angle)) * radius, y: cy + CGFloat(sin(angle)) * radius)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.addPath(path); ctx.setFillColor(white); ctx.fillPath()

        case .openrouter:
            // Routing node: ring with a centre dot.
            ctx.setStrokeColor(white); ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: r.insetBy(dx: 0.6, dy: 0.6))
            ctx.setFillColor(white)
            let d: CGFloat = r.width * 0.28
            ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))

        case .generic:
            ctx.setFillColor(white)
            ctx.fillEllipse(in: r.insetBy(dx: 1, dy: 1))
        }
    }

    private static func levelColor(_ remaining: CGFloat) -> NSColor {
        if remaining >= 0.5 { return .systemGreen }
        if remaining >= 0.2 { return .systemYellow }
        return .systemRed
    }

    private static func brandColor(_ key: String) -> CGColor {
        switch key {
        case "claude": return NSColor(srgbRed: 0.85, green: 0.46, blue: 0.34, alpha: 1).cgColor      // terracotta
        case "codex": return NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1).cgColor        // OpenAI green
        case "openrouter": return NSColor(srgbRed: 0.42, green: 0.42, blue: 0.95, alpha: 1).cgColor   // indigo
        default: return NSColor.systemGray.cgColor
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
    static func png(statuses: [ProviderStatus], live: LiveActivity, waterfall: [Double], frame: Int) -> Data? {
        let image = render(statuses: statuses, live: live, waterfall: waterfall, frame: frame,
                           scale: 6, background: NSColor(white: 0.13, alpha: 1))
        guard let rep = image.representations.first as? NSBitmapImageRep else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
