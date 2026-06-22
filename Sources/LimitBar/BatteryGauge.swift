import SwiftUI

/// Horizontal Mac-style battery gauge used in the dropdown. Fill color is the brand identity;
/// fill width is the remaining fraction (0...1).
struct BatteryGauge: View {
    let remaining: Double
    let color: Color
    var height: CGFloat = 14

    private var clamped: Double { min(max(remaining, 0), 1) }

    var body: some View {
        Canvas { ctx, size in
            let nubW: CGFloat = 2
            let shell = CGRect(x: 0.5, y: 0.5, width: size.width - nubW - 1.5, height: size.height - 1)
            let shellPath = Path(roundedRect: shell, cornerRadius: shell.height * 0.32)

            // Track.
            ctx.fill(shellPath, with: .color(.primary.opacity(0.08)))

            // Brand fill with a soft vertical gradient for depth.
            let inset = shell.insetBy(dx: 1.8, dy: 1.8)
            let fillW = max(0, inset.width * CGFloat(clamped))
            if fillW > 0.5 {
                let fillRect = CGRect(x: inset.minX, y: inset.minY, width: fillW, height: inset.height)
                let fill = Path(roundedRect: fillRect, cornerRadius: inset.height * 0.3)
                ctx.fill(fill, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.92), color]),
                    startPoint: CGPoint(x: fillRect.midX, y: fillRect.minY),
                    endPoint: CGPoint(x: fillRect.midX, y: fillRect.maxY)
                ))
                // Glossy top highlight.
                let gloss = Path(roundedRect: CGRect(x: fillRect.minX, y: fillRect.minY,
                                                     width: fillRect.width, height: fillRect.height * 0.45),
                                 cornerRadius: inset.height * 0.3)
                ctx.fill(gloss, with: .color(.white.opacity(0.18)))
                // Leading-edge contrast so very dark/light brand colors stay legible.
                ctx.fill(Path(CGRect(x: fillRect.maxX - 0.6, y: fillRect.minY, width: 0.6, height: fillRect.height)),
                         with: .color(.primary.opacity(0.28)))
            }

            // Outline.
            ctx.stroke(shellPath, with: .color(.primary.opacity(0.5)), lineWidth: 1)

            // Nub.
            let nub = Path(roundedRect: CGRect(x: shell.maxX + 0.5, y: size.height / 2 - 3, width: nubW, height: 6),
                           cornerRadius: 1)
            ctx.fill(nub, with: .color(.primary.opacity(0.5)))
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: clamped)
        .accessibilityElement()
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent remaining")
    }
}
