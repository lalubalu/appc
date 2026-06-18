import SwiftUI

/// Full-screen overlay shown when a place is collected.
/// Displays rarity-colored particles, card animation, and point counter.
struct CollectionCelebrationView: View {
    let collectible: CollectiblePlace
    let pointsEarned: Int
    let onDismiss: () -> Void

    @State private var showCard = false
    @State private var showText = false
    @State private var showPoints = false
    @State private var particles: [Particle] = []
    @State private var particlesVisible = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Particles
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particlesVisible ? particle.endX : 0,
                            y: particlesVisible ? particle.endY : 0)
                    .opacity(particlesVisible ? 0 : 1)
                    .scaleEffect(particlesVisible ? 0.3 : 1)
            }
            .animation(.easeOut(duration: 1.5), value: particlesVisible)

            // Content
            VStack(spacing: Spacing.lg) {
                // Rarity badge
                RarityBadge(rarity: collectible.rarity, size: .large)
                    .scaleEffect(showCard ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2), value: showCard)

                // Place card
                VStack(spacing: Spacing.md) {
                    PlacePlaceholder(
                        icon: collectible.place.imagePlaceholder,
                        color: collectible.place.accentColor,
                        height: 160
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .shadow(color: collectible.rarity.color.opacity(0.5), radius: 20, y: 4)

                    Text(collectible.place.name)
                        .font(CFont.title(20))
                        .foregroundStyle(.white)
                }
                .frame(width: 220)
                .scaleEffect(showCard ? 1 : 0.3)
                .opacity(showCard ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.65), value: showCard)

                // COLLECTED text
                Text("COLLECTED!")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(collectible.rarity.color)
                    .shadow(color: collectible.rarity.color.opacity(0.5), radius: 8)
                    .scaleEffect(showText ? 1 : 0.5)
                    .opacity(showText ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.4), value: showText)

                // Points
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 20))
                    Text("+\(pointsEarned) pts")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.accentAmber)
                .scaleEffect(showPoints ? 1 : 0)
                .opacity(showPoints ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.6), value: showPoints)
            }
        }
        .onAppear {
            generateParticles()
            showCard = true
            showText = true
            showPoints = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                particlesVisible = true
            }

            // Auto dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                onDismiss()
            }
        }
    }

    private func generateParticles() {
        particles = (0..<20).map { _ in
            Particle(
                color: [collectible.rarity.color, Color.connectifyGreen, .white, Color.accentAmber].randomElement()!,
                size: CGFloat.random(in: 6...14),
                endX: CGFloat.random(in: -180...180),
                endY: CGFloat.random(in: -250...250)
            )
        }
    }
}

private struct Particle: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    let endX: CGFloat
    let endY: CGFloat
}

#Preview {
    CollectionCelebrationView(
        collectible: SampleData.collectiblePlaces[6], // Overlook Bluff - Legendary
        pointsEarned: 1000
    ) {}
}
