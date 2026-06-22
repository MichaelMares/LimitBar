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
            let shellPath = Path(roundedRect: shell, cornerRadius: shell.height * 0.34)

            // Recessed track: a faint vertical gradient so the empty channel reads as inset.
            ctx.fill(shellPath, with: .linearGradient(
                Gradient(colors: [.primary.opacity(0.13), .primary.opacity(0.05)]),
                startPoint: CGPoint(x: shell.midX, y: shell.minY),
                endPoint: CGPoint(x: shell.midX, y: shell.maxY)))

            // Brand fill — solid base with a glassy sheen on top.
            let inset = shell.insetBy(dx: 1.6, dy: 1.6)
            let fillW = max(0, inset.width * CGFloat(clamped))
            if fillW > 1 {
                let fillRect = CGRect(x: inset.minX, y: inset.minY, width: fillW, height: inset.height)
                let fillPath = Path(roundedRect: fillRect, cornerRadius: inset.height * 0.34)

                ctx.drawLayer { layer in
                    layer.clip(to: fillPath)
                    layer.fill(Path(fillRect), with: .color(color))
                    // Sheen: a bright crown that fades out, then a touch of shade at the bottom so
                    // the cell looks like a rounded glass pill rather than a flat block.
                    layer.fill(Path(fillRect), with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .white.opacity(0.42), location: 0.0),
                            .init(color: .white.opacity(0.06), location: 0.40),
                            .init(color: .clear, location: 0.56),
                            .init(color: .black.opacity(0.13), location: 1.0),
                        ]),
                        startPoint: CGPoint(x: fillRect.midX, y: fillRect.minY),
                        endPoint: CGPoint(x: fillRect.midX, y: fillRect.maxY)))
                }
                // Soft frame so very dark/light brand colors keep a defined edge (replaces the old
                // hard contrast line, which read as an artifact).
                ctx.stroke(fillPath, with: .color(.primary.opacity(0.12)), lineWidth: 0.75)
            }

            // Shell outline.
            ctx.stroke(shellPath, with: .color(.primary.opacity(0.4)), lineWidth: 1)

            // Nub.
            let nub = Path(roundedRect: CGRect(x: shell.maxX + 0.5, y: size.height / 2 - 3, width: nubW, height: 6),
                           cornerRadius: 1)
            ctx.fill(nub, with: .color(.primary.opacity(0.45)))
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: clamped)
        .accessibilityElement()
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent remaining")
    }
}
