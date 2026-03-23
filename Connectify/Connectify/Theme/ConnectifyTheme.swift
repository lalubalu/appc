import SwiftUI

// MARK: - Brand Colors

extension Color {
    // Primary brand green — identical in both modes
    static let connectifyGreen = Color(hue: 155/360, saturation: 1.0, brightness: 0.50)
    static let connectifyGreenBright = Color(hue: 155/360, saturation: 1.0, brightness: 1.0)

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
// These provide programmatic fallbacks.

extension ShapeStyle where Self == Color {
    // Card background
    static var cardSurface: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.15, green: 0.155, blue: 0.195, alpha: 1) // hsl(231,8%,16%)
                : UIColor.white
        })
    }

    // Page background
    static var pageSurface: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.075, green: 0.08, blue: 0.10, alpha: 1)  // hsl(231,15%,9%)
                : UIColor(red: 0.965, green: 0.97, blue: 0.975, alpha: 1) // warm off-white
        })
    }

    // Elevated surface (popovers, sheets)
    static var elevatedSurface: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.105, blue: 0.135, alpha: 1) // hsl(231,11%,12%)
                : UIColor.white
        })
    }

    // Primary text
    static var primaryText: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        })
    }

    // Secondary text
    static var secondaryText: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.62, green: 0.64, blue: 0.66, alpha: 1)
                : UIColor(red: 0.42, green: 0.44, blue: 0.48, alpha: 1)
        })
    }

    // Tertiary / placeholder text
    static var tertiaryText: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.42, green: 0.44, blue: 0.46, alpha: 1)
                : UIColor(red: 0.62, green: 0.64, blue: 0.66, alpha: 1)
        })
    }

    // Border / divider
    static var subtleBorder: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.235, blue: 0.28, alpha: 1)
                : UIColor(red: 0.90, green: 0.91, blue: 0.92, alpha: 1)
        })
    }

    // Green tinted background for badges / tags
    static var greenSurface: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.0, green: 0.25, blue: 0.15, alpha: 1)
                : UIColor(red: 0.90, green: 0.99, blue: 0.94, alpha: 1)
        })
    }
}

// MARK: - Typography

struct CFont {
    // Display — large hero text
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    // Title
    static func title(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .semibold, design: .default)
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
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let pill: CGFloat = 100
}
