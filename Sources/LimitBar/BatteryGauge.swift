import SwiftUI

/// Horizontal Mac-style battery gauge used in the dropdown. Fill color is the brand identity;
/// fill width is the remaining fraction (0...1).
struct BatteryGauge: View {
    let remaining: Double
    let color: Color
    var height: CGFloat = 14

    var body: some View {
        Canvas { ctx, size in
            let nubW: CGFloat = 2
            let shell = CGRect(x: 0.5, y: 0.5, width: size.width - nubW - 1.5, height: size.height - 1)
            let shellPath = Path(roundedRect: shell, cornerRadius: 3)

            // Track.
            ctx.fill(shellPath, with: .color(.primary.opacity(0.10)))

            // Brand fill.
            let inset = shell.insetBy(dx: 1.8, dy: 1.8)
            let fillW = max(0, inset.width * CGFloat(min(max(remaining, 0), 1)))
            if fillW > 0.5 {
                let fill = Path(roundedRect: CGRect(x: inset.minX, y: inset.minY, width: fillW, height: inset.height),
                                cornerRadius: 1.5)
                ctx.fill(fill, with: .color(color))
                // Leading-edge contrast for very dark/light brand colors.
                ctx.fill(Path(CGRect(x: inset.minX + fillW - 0.6, y: inset.minY, width: 0.6, height: inset.height)),
                         with: .color(.primary.opacity(0.3)))
            }

            // Outline.
            ctx.stroke(shellPath, with: .color(.primary.opacity(0.55)), lineWidth: 1)

            // Nub.
            let nub = Path(roundedRect: CGRect(x: shell.maxX + 0.5, y: size.height / 2 - 3, width: nubW, height: 6),
                           cornerRadius: 1)
            ctx.fill(nub, with: .color(.primary.opacity(0.55)))
        }
        .frame(height: height)
    }
}
