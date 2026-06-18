import SwiftUI

// MARK: - Brand Colors

extension Color {
    // Primary brand green — punchy and vivid
    static let connectifyGreen = Color(hue: 155/360, saturation: 0.85, brightness: 0.65)
    static let connectifyGreenBright = Color(hue: 155/360, saturation: 0.75, brightness: 0.95)
    static let connectifyGreenDeep = Color(hue: 160/360, saturation: 0.90, brightness: 0.35)

    // Adaptive surface colors
    static let surfaceBackground = Color("SurfaceBackground")
    static let surfaceCard = Color("SurfaceCard")
    static let surfaceElevated = Color("SurfaceElevated")

    // Adaptive text colors
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")

    // Semantic colors
    static let connectifyDestructive = Color(hue: 349/360, saturation: 1.0, brightness: 0.62)
    static let connectifyBorder = Color("BorderColor")

    // Accent tints for categories
    static let accentCoral = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let accentAmber = Color(red: 1.0, green: 0.76, blue: 0.28)
    static let accentSky = Color(red: 0.30, green: 0.70, blue: 1.0)
    static let accentLavender = Color(red: 0.68, green: 0.52, blue: 1.0)
    static let accentMint = Color(red: 0.20, green: 0.90, blue: 0.70)
}

// MARK: - Adaptive Color Definitions (used when Asset Catalog is not set up)

extension ShapeStyle where Self == Color {
    // Card background
    static var cardSurface: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.13, green: 0.145, blue: 0.16, alpha: 1)
                : UIColor.white
        })
    }

    // Page background — warm with a hint of green in light mode
    static var pageSurface: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.06, green: 0.075, blue: 0.08, alpha: 1)
                : UIColor(red: 0.955, green: 0.975, blue: 0.965, alpha: 1)
        })
    }

    // Elevated surface (popovers, sheets)
    static var elevatedSurface: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.105, blue: 0.135, alpha: 1)
                : UIColor.white
        })
    }

    // Primary text
    static var primaryText: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
        })
    }

    // Secondary text
    static var secondaryText: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.58, green: 0.62, blue: 0.63, alpha: 1)
                : UIColor(red: 0.36, green: 0.40, blue: 0.42, alpha: 1)
        })
    }

    // Tertiary / placeholder text
    static var tertiaryText: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.38, green: 0.42, blue: 0.43, alpha: 1)
                : UIColor(red: 0.58, green: 0.62, blue: 0.63, alpha: 1)
        })
    }

    // Border / divider
    static var subtleBorder: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.20, green: 0.22, blue: 0.24, alpha: 1)
                : UIColor(red: 0.89, green: 0.91, blue: 0.90, alpha: 1)
        })
    }

    // Green tinted background for badges / tags / success states
    static var greenSurface: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.04, green: 0.18, blue: 0.12, alpha: 1)
                : UIColor(red: 0.91, green: 0.98, blue: 0.94, alpha: 1)
        })
    }

    // Green-tinted card — for featured/highlighted cards
    static var greenCard: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.14, blue: 0.11, alpha: 1)
                : UIColor(red: 0.95, green: 0.995, blue: 0.97, alpha: 1)
        })
    }
}

// MARK: - Typography

struct CFont {
    // Display — large hero text
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .black, design: .serif)
    }

    // Title — bolder weight for authority
    static func title(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    // Headline
    static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    // Body
    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    // Caption
    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    // Label — small all-caps
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    // Mono — for numbers/stats
    static func mono(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

// MARK: - Spacing Constants

struct Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius

struct Radius {
    static let sm: CGFloat = 2
    static let md: CGFloat = 4
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
    static let pill: CGFloat = 100
}
