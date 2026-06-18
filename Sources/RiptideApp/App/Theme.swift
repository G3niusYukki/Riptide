import SwiftUI
import AppKit

/// App theme colors and design tokens. Adapts to light/dark mode via `colorScheme`.
///
/// This is the single source of truth for all visual design tokens in the app.
/// Views should reference `Theme.*` tokens rather than hardcoding colors,
/// spacing, typography, shadows, or animations.
enum Theme {
    // MARK: - Accent Colors

    /// Primary accent color (cyan-blue). Used for tint, selected states, and CTAs.
    static let accent = Color(hex: "0fbcf9")
    /// Success state color (green). Used for healthy nodes, online status.
    static let success = Color(hex: "0be881")
    /// Danger state color (red). Used for errors, offline status, destructive actions.
    static let danger = Color(hex: "fd7272")
    /// Warning state color (amber). Used for high latency, expiring subscriptions.
    static let warning = Color(hex: "ffaa00")

    // MARK: - Legacy Background Colors

    /// Dark background base color (legacy — prefer `backgroundGradient`).
    static let background = Color(hex: "1a1a2e")
    /// Dark gradient end color (legacy — prefer `backgroundGradient`).
    static let backgroundEnd = Color(hex: "16213e")

    // MARK: - Semantic Colors (auto-adapt to color scheme)

    /// Primary text color — adapts to light/dark automatically.
    static let text = Color.primary
    /// Secondary text color — for labels, captions, and supporting text.
    static let subtext = Color.secondary
    /// Card background — use `.ultraThinMaterial` in views for translucency.
    static let card = Color.clear

    // MARK: - NSColor-adapted Semantic Colors (auto light/dark)

    /// Standard card background, derived from system control background.
    static let cardBackground = Color(nsColor: NSColor.controlBackgroundColor)
    /// Elevated card background, derived from system window background.
    static let elevatedCard = Color(nsColor: NSColor.windowBackgroundColor)
    /// Card border / divider color.
    static let cardBorder = Color(nsColor: NSColor.separatorColor)
    /// Additional semantic: tertiary text (placeholder, disabled).
    static let textTertiary = Color(nsColor: NSColor.tertiaryLabelColor)
    /// Additional semantic: separator / divider.
    static let separator = Color(nsColor: NSColor.separatorColor)
    /// Additional semantic: info blue (links, informational badges).
    static let info = Color(nsColor: NSColor.systemBlue)

    // MARK: - Corner Radius

    /// Standard card corner radius.
    static let cardRadius: CGFloat = 12
    /// Standard button corner radius.
    static let buttonRadius: CGFloat = 8
    /// Small corner radius — for badges, tags, and compact controls.
    static let smallRadius: CGFloat = 6
    /// Large corner radius — for sheets, modals, and prominent surfaces.
    static let largeRadius: CGFloat = 16

    // MARK: - Spacing Scale

    /// Design-token spacing scale. Use these instead of ad-hoc `.padding(N)`.
    ///
    /// ```swift
    /// // Instead of:
    /// .padding(16)
    /// // Use:
    /// .padding(Theme.Spacing.lg)
    /// ```
    enum Spacing {
        /// 4pt — tight spacing for inline elements, icon gaps.
        static let xs: CGFloat = 4
        /// 8pt — default spacing for compact layouts, button padding.
        static let sm: CGFloat = 8
        /// 12pt — standard spacing between related elements.
        static let md: CGFloat = 12
        /// 16pt — standard spacing between card sections.
        static let lg: CGFloat = 16
        /// 24pt — spacing between major sections.
        static let xl: CGFloat = 24
        /// 32pt — spacing between top-level groups.
        static let xxl: CGFloat = 32
    }

    // MARK: - Typography Scale

    /// Design-token typography scale. Use these instead of ad-hoc `.font(.system(...))`.
    ///
    /// ```swift
    /// // Instead of:
    /// .font(.system(.body))
    /// // Use:
    /// .font(Theme.Typography.body)
    ///
    /// // Instead of:
    /// .font(.system(size: 32, weight: .bold))
    /// // Use:
    /// .font(Theme.Typography.statLarge)
    /// ```
    enum Typography {
        // System text styles — adapt to Dynamic Type automatically
        /// Smallest text — fine print, timestamps.
        static let caption2 = Font.caption2
        /// Small text — captions, badges, secondary labels.
        static let caption = Font.caption
        /// Slightly larger than caption — helper text, descriptions.
        static let callout = Font.callout
        /// Default body text — the most common font.
        static let body = Font.body
        /// Section headers, card titles.
        static let headline = Font.headline
        /// Large section titles.
        static let title3 = Font.title3
        /// Page-level titles.
        static let title2 = Font.title2
        /// Hero titles.
        static let title = Font.title

        // Monospaced variants — for data display (bytes, latency, timestamps)
        /// Monospaced caption — for compact data display.
        static let monoCaption = Font.system(.caption, design: .monospaced)
        /// Monospaced body — for data tables, code snippets.
        static let monoBody = Font.system(.body, design: .monospaced)
        /// Monospaced headline — for data table headers.
        static let monoHeadline = Font.system(.headline, design: .monospaced)

        // Custom sizes — for specific UI elements
        /// 9pt — micro text for tiny badges, status indicators.
        static let micro = Font.system(size: 9)
        /// 32pt bold rounded — large stat numbers (speed, counters).
        static let statLarge = Font.system(size: 32, weight: .bold, design: .rounded)
        /// 48pt bold rounded — hero stat numbers (onboarding, empty states).
        static let statExtraLarge = Font.system(size: 48, weight: .bold, design: .rounded)
    }

    // MARK: - Shadow / Elevation

    /// Design-token shadow scale. Use these for consistent depth cues.
    ///
    /// ```swift
    /// // Instead of:
    /// .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    /// // Use:
    /// .shadow(color: Theme.Shadow.md.color, radius: Theme.Shadow.md.radius, x: Theme.Shadow.md.x, y: Theme.Shadow.md.y)
    /// ```
    struct ShadowToken: Sendable {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    enum Shadow {
        /// Subtle elevation — for cards resting on the background.
        static let sm = ShadowToken(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        /// Standard elevation — for raised cards, popovers.
        static let md = ShadowToken(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        /// Prominent elevation — for modals, floating panels.
        static let lg = ShadowToken(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // MARK: - Animation

    /// Design-token animation scale. Use these for consistent motion.
    ///
    /// ```swift
    /// // Instead of:
    /// withAnimation(.easeInOut(duration: 0.2)) { ... }
    /// // Use:
    /// withAnimation(Theme.Animation.normal) { ... }
    /// ```
    enum Animation {
        /// 0.15s — quick transitions (toggle, tap feedback).
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        /// 0.2s — standard transitions (expand/collapse, selection).
        static let normal = SwiftUI.Animation.easeInOut(duration: 0.2)
        /// 0.3s — slow transitions (sheet, page transition).
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.3)
        /// Default spring — responsive with slight bounce.
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
        /// Bouncy spring — playful (node selection, toggle).
        static let springBouncy = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.6)
        /// Smooth spring — gentle (panel expand, detail reveal).
        static let springSmooth = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.85)
    }

    // MARK: - Background Gradient

    /// Background gradient that adapts to the current color scheme.
    static func backgroundGradient(for colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .dark:
            return LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            return LinearGradient(
                colors: [Color(hex: "f0f2f5"), Color(hex: "e8ecf1")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        @unknown default:
            return LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Legacy gradient. Auto-detects dark/light from the current window / system setting.
    static var backgroundGradient: LinearGradient {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return backgroundGradient(for: isDark ? .dark : .light)
    }
}

// MARK: - ViewModifiers

extension View {
    /// Applies the standard card style: frosted material background + rounded corners + subtle shadow.
    ///
    /// ```swift
    /// VStack { ... }
    ///     .cardStyle()
    /// ```
    func cardStyle(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.cardBorder.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(
                color: Theme.Shadow.sm.color,
                radius: Theme.Shadow.sm.radius,
                x: Theme.Shadow.sm.x,
                y: Theme.Shadow.sm.y
            )
    }

    /// Applies the elevated card style: solid background + rounded corners + medium shadow.
    func elevatedCardStyle(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.elevatedCard, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.cardBorder.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(
                color: Theme.Shadow.md.color,
                radius: Theme.Shadow.md.radius,
                x: Theme.Shadow.md.x,
                y: Theme.Shadow.md.y
            )
    }

    /// Applies a standard shadow from the design token scale.
    func themeShadow(_ token: Theme.ShadowToken) -> some View {
        self.shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let alpha: UInt64, red: UInt64, green: UInt64, blue: UInt64
        switch hex.count {
        case 3: (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (alpha, red, green, blue) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: Double(alpha) / 255)
    }
}
