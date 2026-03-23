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
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(.subtleBorder, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func backgroundColorFor(_ style: ButtonStyle) -> Color {
        switch style {
        case .primary: return Color.connectifyGreen
        case .secondary: return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.15, green: 0.155, blue: 0.195, alpha: 1) : .white })
        case .ghost: return .clear
        }
    }

    private func foregroundColorFor(_ style: ButtonStyle) -> Color {
        switch style {
        case .primary: return .black
        case .secondary, .ghost: return Color(UIColor { $0.userInterfaceStyle == .dark ? .white : UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1) })
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
            .padding(.vertical, 8)
            .background(isSelected ? tint.opacity(0.15) : .cardSurface)
            .foregroundStyle(isSelected ? tint : .secondaryText)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? tint.opacity(0.4) : .subtleBorder, lineWidth: 1)
            }
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
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.connectifyGreen)

            Text(value)
                .font(CFont.title(22))
                .foregroundStyle(.primaryText)

            Text(label)
                .font(CFont.caption(11))
                .foregroundStyle(.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(.subtleBorder, lineWidth: 0.5)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
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
        .background(.greenSurface)
        .foregroundStyle(Color.connectifyGreen)
        .clipShape(Capsule())
    }
}

// MARK: - Place Image Placeholder

struct PlacePlaceholder: View {
    let icon: String
    let color: Color
    var height: CGFloat = 140

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [color.opacity(0.25), color.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(color.opacity(0.6))
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Avatar Circle

struct AvatarCircle: View {
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.connectifyGreen.opacity(0.7), Color.connectifyGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold, design: .default))
                .foregroundStyle(.black)
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
                .foregroundStyle(.tertiaryText)

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
                .stroke(.subtleBorder, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.connectifyGreen,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(CFont.label(size * 0.24))
                .foregroundStyle(.primaryText)
        }
        .frame(width: size, height: size)
    }
}
