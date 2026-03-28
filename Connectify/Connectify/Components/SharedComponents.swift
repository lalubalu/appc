import SwiftUI

// MARK: - Connectify Button

struct ConnectifyButton: View {
    let title: String
    var icon: String? = nil
    var style: ButtonStyle = .primary
    let action: () -> Void

    enum ButtonStyle {
        case primary, secondary, ghost
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(CFont.headline(16))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(backgroundColorFor(style))
            .foregroundStyle(foregroundColorFor(style))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(Color.connectifyGreen.opacity(0.25), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func backgroundColorFor(_ style: ButtonStyle) -> Color {
        switch style {
        case .primary: return Color.connectifyGreen
        case .secondary: return .greenSurface
        case .ghost: return .clear
        }
    }

    private func foregroundColorFor(_ style: ButtonStyle) -> Color {
        switch style {
        case .primary: return .white
        case .secondary: return Color.connectifyGreen
        case .ghost: return Color.connectifyGreen
        }
    }
}

// MARK: - Category Pill

struct CategoryPill: View {
    let label: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(CFont.caption(13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? Color.connectifyGreen : .cardSurface)
            .foregroundStyle(isSelected ? .white : .secondaryText)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.connectifyGreen)

            Text(value)
                .font(CFont.mono(24))
                .foregroundStyle(.primaryText)

            Text(label)
                .font(CFont.caption(11))
                .foregroundStyle(.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(.greenCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.connectifyGreen)
                .frame(width: 3, height: 18)

            Text(title)
                .font(CFont.title(20))
                .foregroundStyle(.primaryText)

            Spacer()

            if let action {
                Button(action) {
                    onAction?()
                }
                .font(CFont.caption(14))
                .foregroundStyle(Color.connectifyGreen)
            }
        }
    }
}

// MARK: - XP Badge

struct XPBadge: View {
    let xp: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10))
            Text("+\(xp) XP")
                .font(CFont.label(11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.connectifyGreen)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Place Image Placeholder

struct PlacePlaceholder: View {
    let icon: String
    let color: Color
    var height: CGFloat = 140

    var body: some View {
        ZStack {
            // Richer background with green undertone
            LinearGradient(
                colors: [
                    Color.connectifyGreen.opacity(0.08),
                    color.opacity(0.20),
                    color.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle pattern overlay
            GeometryReader { geo in
                Path { path in
                    let w = geo.size.width
                    let h = geo.size.height
                    for i in stride(from: 0, through: w, by: 40) {
                        path.move(to: CGPoint(x: i, y: 0))
                        path.addLine(to: CGPoint(x: i + h * 0.5, y: h))
                    }
                }
                .stroke(color.opacity(0.06), lineWidth: 1)
            }

            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(color.opacity(0.45))
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}

// MARK: - Avatar Circle

struct AvatarCircle: View {
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.connectifyGreen)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .default))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.connectifyGreen.opacity(0.4))

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(CFont.headline())
                    .foregroundStyle(.primaryText)
                Text(subtitle)
                    .font(CFont.body(14))
                    .foregroundStyle(.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.xxl)
    }
}

// MARK: - Progress Ring

struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 44
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.connectifyGreen.opacity(0.12), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.connectifyGreen,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(CFont.label(size * 0.24))
                .foregroundStyle(Color.connectifyGreen)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Green Accent Card modifier

extension View {
    /// Wraps the view in a card with a green left-edge accent bar
    func greenAccentCard() -> some View {
        self
            .padding(Spacing.md)
            .background(
                HStack(spacing: 0) {
                    Color.connectifyGreen
                        .frame(width: 3)
                    Color.cardSurface
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}
