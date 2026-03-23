import SwiftUI

// MARK: - Rarity Badge (capsule showing tier)

struct RarityBadge: View {
    let rarity: PlaceRarity
    var size: RarityBadgeSize = .regular

    enum RarityBadgeSize {
        case small, regular, large

        var iconSize: CGFloat {
            switch self {
            case .small: return 8
            case .regular: return 10
            case .large: return 14
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 9
            case .regular: return 11
            case .large: return 14
            }
        }

        var hPadding: CGFloat {
            switch self {
            case .small: return 6
            case .regular: return 8
            case .large: return 12
            }
        }

        var vPadding: CGFloat {
            switch self {
            case .small: return 3
            case .regular: return 4
            case .large: return 6
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: rarity.icon)
                .font(.system(size: size.iconSize, weight: .bold))
            Text(rarity.rawValue.uppercased())
                .font(CFont.label(size.fontSize))
                .tracking(0.5)
        }
        .padding(.horizontal, size.hPadding)
        .padding(.vertical, size.vPadding)
        .background(rarity.color.opacity(0.15))
        .foregroundStyle(rarity.color)
        .clipShape(Capsule())
    }
}

// MARK: - Points Badge (for displaying point values)

struct PointsBadge: View {
    let points: Int
    var prefix: String = "+"

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 10))
            Text("\(prefix)\(points) pts")
                .font(CFont.label(11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentAmber.opacity(0.15))
        .foregroundStyle(Color.accentAmber)
        .clipShape(Capsule())
    }
}

// MARK: - Rarity Dot (inline indicator for lists)

struct RarityDot: View {
    let rarity: PlaceRarity

    var body: some View {
        Image(systemName: rarity.icon)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(rarity.color)
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach(PlaceRarity.allCases) { rarity in
            HStack {
                RarityBadge(rarity: rarity, size: .small)
                RarityBadge(rarity: rarity)
                RarityBadge(rarity: rarity, size: .large)
                RarityDot(rarity: rarity)
            }
        }
        PointsBadge(points: 150)
    }
    .padding()
}
