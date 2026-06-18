import SwiftUI

// MARK: - Daily Gem Full-Screen Splash (clay)

struct DailyGemView: View {
    let featuredPlace: Place
    let onDismiss: () -> Void

    @State private var showContent = false

    private var kind: ClayStyle.ClayAccentKind { featuredPlace.category.clayKind }

    var body: some View {
        ZStack {
            VerdureBackground()

            VStack(spacing: Spacing.xl) {
                Spacer()

                ZStack {
                    AmbientGlow(color: Palette.gold.base.opacity(0.4), size: 340, opacity: 0.8)
                    MedallionHero(size: 240, interactive: false)
                        .scaleEffect(showContent ? 1 : 0.5)
                        .opacity(showContent ? 1 : 0)
                    sparkle(14, x: -120, y: -20, delay: 0.3)
                    sparkle(10, x: 118, y: -54, delay: 0.5)
                    sparkle(8, x: 128, y: 40, delay: 0.7)
                    sparkle(11, x: -108, y: 70, delay: 0.9)
                }
                .frame(height: 280)

                VStack(spacing: Spacing.md) {
                    KickerLabel(text: "Today's discovery", color: Palette.gold.base, dot: Palette.gold.base)
                    Text("Daily Gem")
                        .font(VType.display(44, .bold))
                        .foregroundStyle(Palette.ink)
                    Text("Discover something new about your\nneighborhood, every single day.")
                        .font(VType.body(15))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 16)

                // Featured place clay card
                HStack(spacing: Spacing.md) {
                    ClayIconTile(systemImage: featuredPlace.imagePlaceholder, kind: kind, size: 54, radius: Radius.chip)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(featuredPlace.category.rawValue.uppercased())
                            .font(VType.body(10, .bold)).tracking(0.8)
                            .foregroundStyle(kind.accent.base)
                        Text(featuredPlace.name)
                            .font(VType.display(18, .semibold)).foregroundStyle(Palette.ink)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.spruce.base)
                }
                .padding(Spacing.md)
                .claySurface(.surface, radius: Radius.md, elevation: 1)
                .padding(.horizontal, Spacing.xl)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 24)

                Spacer()

                Text("Tap anywhere to continue")
                    .font(VType.body(13, .medium)).foregroundStyle(Palette.inkFaint)
                    .opacity(showContent ? 1 : 0)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Haptics.tap(); onDismiss() }
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.72).delay(0.15)) { showContent = true }
        }
    }

    private func sparkle(_ size: CGFloat, x: CGFloat, y: CGFloat, delay: Double) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Palette.gold.base)
            .offset(x: x, y: y)
            .opacity(showContent ? 0.9 : 0)
            .scaleEffect(showContent ? 1 : 0.4)
            .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(delay), value: showContent)
    }
}

#Preview {
    DailyGemView(featuredPlace: SampleData.places[0], onDismiss: {})
}
