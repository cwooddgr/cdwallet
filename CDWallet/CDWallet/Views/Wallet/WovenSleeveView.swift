import SwiftUI

/// Simulates the semi-transparent woven white plastic texture of a 90s CD wallet sleeve
struct WovenSleeveView: View {
    var body: some View {
        Canvas { context, size in
            // Base translucent white
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.white.opacity(0.35))
            )

            // Cross-hatch pattern for woven texture
            let spacing: CGFloat = 4
            let lineWidth: CGFloat = 0.5
            let lineColor = Color.white.opacity(0.15)

            // Diagonal lines (top-left to bottom-right)
            var y: CGFloat = -size.height
            while y < size.height + size.width {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y + size.width))
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
                y += spacing
            }

            // Diagonal lines (top-right to bottom-left)
            y = 0
            while y < size.height + size.width {
                var path = Path()
                path.move(to: CGPoint(x: size.width, y: y - size.width))
                path.addLine(to: CGPoint(x: 0, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
                y += spacing
            }

            // Horizontal lines for additional weave texture
            var yHoriz: CGFloat = 0
            while yHoriz < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: yHoriz))
                path.addLine(to: CGPoint(x: size.width, y: yHoriz))
                context.stroke(path, with: .color(Color.gray.opacity(0.08)), lineWidth: 0.3)
                yHoriz += spacing * 2
            }
        }
    }
}

#Preview {
    ZStack {
        Color(white: 0.15)
        WovenSleeveView()
            .frame(width: 300, height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
