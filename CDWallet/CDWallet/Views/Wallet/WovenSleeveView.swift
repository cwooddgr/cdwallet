import SwiftUI

/// Simulates the woven dark gray plastic texture of a 90s CD wallet sleeve
struct WovenSleeveView: View {
    var body: some View {
        Canvas { context, size in
            // Dark gray base
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(white: 0.20))
            )

            // Cross-hatch pattern for woven texture
            let spacing: CGFloat = 8
            let lineWidth: CGFloat = 1.0
            let lineColor = Color(white: 0.25)

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
            let horizLineColor = Color(white: 0.15)
            var yHoriz: CGFloat = 0
            while yHoriz < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: yHoriz))
                path.addLine(to: CGPoint(x: size.width, y: yHoriz))
                context.stroke(path, with: .color(horizLineColor), lineWidth: 0.6)
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
