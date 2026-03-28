import SwiftUI

// MARK: - Daily Gem Full-Screen Splash

struct DailyGemView: View {
    let featuredPlace: Place
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var shimmer = false

    private let bgColor = Color(hue: 0.38, saturation: 0.07, brightness: 0.96)
    private let titleGreen = Color(hue: 0.40, saturation: 0.38, brightness: 0.62)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Gem with glow and sparkles
                ZStack {
                    // Soft backglow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hue: 0.40, saturation: 0.15, brightness: 0.90).opacity(0.6),
                                    bgColor.opacity(0)
                                ],
                                center: .center,
                                startRadius: 40,
                                endRadius: 140
                            )
                        )
                        .frame(width: 280, height: 280)

                    // The gem
                    GemstoneView(shimmer: shimmer)
                        .frame(width: 180, height: 200)

                    // Sparkles
                    SparkleStarView()
                        .frame(width: 20, height: 20)
                        .offset(x: -82, y: 8)
                        .opacity(showContent ? 0.85 : 0)

                    SparkleStarView()
                        .frame(width: 14, height: 14)
                        .offset(x: 78, y: -28)
                        .opacity(showContent ? 1.0 : 0)

                    SparkleStarView()
                        .frame(width: 10, height: 10)
                        .offset(x: 88, y: 22)
                        .opacity(showContent ? 0.7 : 0)
                }
                .scaleEffect(showContent ? 1.0 : 0.5)
                .opacity(showContent ? 1.0 : 0)

                Spacer().frame(height: 44)

                // Title
                Text("Daily Gem")
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundStyle(titleGreen)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 16)

                Spacer().frame(height: 28)

                // Subtitle
                Text("\u{201C}Discover new things every day about your\nneighborhood!\u{201D}")
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(Color(white: 0.52))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 12)

                Spacer()
                Spacer()
            }
        }
        .onTapGesture { onDismiss() }
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.72).delay(0.15)) {
                showContent = true
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(0.5)) {
                shimmer = true
            }
        }
    }
}

// MARK: - Gemstone (Polished Multi-Facet Diamond)

private struct GemstoneView: View {
    var shimmer: Bool

    // Gem palette — soft mints to mid-greens, no harsh darks
    private let lightMint = Color(hue: 0.40, saturation: 0.22, brightness: 0.88)
    private let mint = Color(hue: 0.40, saturation: 0.32, brightness: 0.78)
    private let midGreen = Color(hue: 0.40, saturation: 0.42, brightness: 0.68)
    private let green = Color(hue: 0.40, saturation: 0.48, brightness: 0.58)
    private let deepGreen = Color(hue: 0.40, saturation: 0.52, brightness: 0.50)

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Diamond geometry
            let top = CGPoint(x: w * 0.50, y: h * 0.0)
            let topLeft = CGPoint(x: w * 0.14, y: h * 0.05)
            let topRight = CGPoint(x: w * 0.86, y: h * 0.05)
            let left = CGPoint(x: w * 0.02, y: h * 0.36)
            let right = CGPoint(x: w * 0.98, y: h * 0.36)
            let bottom = CGPoint(x: w * 0.50, y: h * 1.0)

            // Belt points (girdle)
            let bL = CGPoint(x: w * 0.20, y: h * 0.36)
            let bML = CGPoint(x: w * 0.38, y: h * 0.36)
            let bC = CGPoint(x: w * 0.50, y: h * 0.36)
            let bMR = CGPoint(x: w * 0.62, y: h * 0.36)
            let bR = CGPoint(x: w * 0.80, y: h * 0.36)

            // Crown inner points
            let cL = CGPoint(x: w * 0.30, y: h * 0.18)
            let cR = CGPoint(x: w * 0.70, y: h * 0.18)

            // --- CROWN (upper facets) ---

            // Far left crown facet
            fill(context, points: [topLeft, left, bL, cL], color: green)

            // Left-center crown
            fill(context, points: [topLeft, cL, bML, top], color: midGreen)

            // Center-left crown (lightest — catches light)
            fill(context, points: [top, cL, bML, bC], color: lightMint)

            // Center triangle highlight
            fill(context, points: [top, bC, cR], color: mint.opacity(0.9))

            // Center-right crown
            fill(context, points: [top, cR, bMR, bC], color: mint)

            // Right-center crown
            fill(context, points: [topRight, cR, bMR, top], color: midGreen.opacity(0.85))

            // Far right crown facet
            fill(context, points: [topRight, right, bR, cR], color: green.opacity(0.8))

            // --- PAVILION (lower facets) ---

            // Far left pavilion
            fill(context, points: [left, bL, bottom], color: deepGreen.opacity(0.85))

            // Left pavilion
            fill(context, points: [bL, bML, bottom], color: green.opacity(0.9))

            // Center-left pavilion
            fill(context, points: [bML, bC, bottom], color: midGreen.opacity(0.85))

            // Center-right pavilion
            fill(context, points: [bC, bMR, bottom], color: mint.opacity(0.75))

            // Right pavilion
            fill(context, points: [bMR, bR, bottom], color: midGreen.opacity(0.8))

            // Far right pavilion
            fill(context, points: [bR, right, bottom], color: green.opacity(0.75))

            // --- Subtle facet lines (very faint) ---
            let lineColor: Color = .white.opacity(0.12)
            let lineWidth: CGFloat = 0.6

            strokeLine(context, from: top, to: bC, color: lineColor, width: lineWidth)
            strokeLine(context, from: top, to: cL, color: lineColor, width: lineWidth)
            strokeLine(context, from: top, to: cR, color: lineColor, width: lineWidth)
            strokeLine(context, from: cL, to: bML, color: lineColor, width: lineWidth)
            strokeLine(context, from: cR, to: bMR, color: lineColor, width: lineWidth)
            strokeLine(context, from: left, to: right, color: .white.opacity(0.08), width: 0.8)
            strokeLine(context, from: bL, to: bottom, color: lineColor, width: lineWidth)
            strokeLine(context, from: bML, to: bottom, color: lineColor, width: lineWidth)
            strokeLine(context, from: bMR, to: bottom, color: lineColor, width: lineWidth)
            strokeLine(context, from: bR, to: bottom, color: lineColor, width: lineWidth)
        }
        .shadow(color: Color(hue: 0.40, saturation: 0.30, brightness: 0.55).opacity(0.3), radius: 24, y: 12)
        // Shimmer overlay
        .overlay {
            LinearGradient(
                colors: [
                    .white.opacity(shimmer ? 0.15 : 0.0),
                    .clear,
                    .white.opacity(shimmer ? 0.08 : 0.0),
                ],
                startPoint: shimmer ? .topTrailing : .topLeading,
                endPoint: shimmer ? .bottomLeading : .bottomTrailing
            )
            .mask {
                GemOutlineShape()
            }
        }
    }

    private func fill(_ context: GraphicsContext, points: [CGPoint], color: Color) {
        var path = Path()
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private func strokeLine(_ context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: width)
    }
}

// MARK: - Gem Outline (for masking shimmer)

private struct GemOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.50, y: 0))
        path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.36))
        path.addLine(to: CGPoint(x: w * 0.50, y: h))
        path.addLine(to: CGPoint(x: w * 0.02, y: h * 0.36))
        path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.05))
        path.closeSubpath()
        return path
    }
}

// MARK: - Sparkle Star

private struct SparkleStarView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let t: CGFloat = 0.15

            var path = Path()
            path.move(to: CGPoint(x: cx, y: 0))
            path.addLine(to: CGPoint(x: cx + w * t, y: cy - h * t))
            path.addLine(to: CGPoint(x: w, y: cy))
            path.addLine(to: CGPoint(x: cx + w * t, y: cy + h * t))
            path.addLine(to: CGPoint(x: cx, y: h))
            path.addLine(to: CGPoint(x: cx - w * t, y: cy + h * t))
            path.addLine(to: CGPoint(x: 0, y: cy))
            path.addLine(to: CGPoint(x: cx - w * t, y: cy - h * t))
            path.closeSubpath()

            context.fill(path, with: .color(.white.opacity(0.9)))
        }
    }
}

// MARK: - Preview

#Preview {
    DailyGemView(
        featuredPlace: SampleData.places[0],
        onDismiss: {}
    )
}
