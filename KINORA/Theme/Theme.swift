import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    // Графитовая база
    static let bg = Color(hex: 0x08070C)
    static let bg2 = Color(hex: 0x0F0D16)
    static let card = Color(hex: 0x15131E)
    static let cardHi = Color(hex: 0x1C1928)
    static let stroke = Color.white.opacity(0.08)
    static let strokeHi = Color.white.opacity(0.14)

    // Фиолетовые акценты
    static let accent = Color(hex: 0x8B5CF6)
    static let accent2 = Color(hex: 0xA855F7)
    static let accentDeep = Color(hex: 0x6D28D9)
    static let accentSoft = Color(hex: 0xC4B5FD)
    static let pink = Color(hex: 0xEC4899)
    static let gold = Color(hex: 0xFBBF24)
    static let green = Color(hex: 0x4ADE80)
    static let red = Color(hex: 0xF87171)

    static let text = Color.white
    static let text2 = Color(hex: 0xA19DB0)
    static let text3 = Color(hex: 0x6E6A7C)

    static let accentGradient = LinearGradient(colors: [Color(hex: 0x7C3AED), Color(hex: 0xA855F7)],
                                               startPoint: .leading, endPoint: .trailing)
    static let logoGradient = LinearGradient(colors: [Color(hex: 0xC4B5FD), Color(hex: 0xA855F7), Color(hex: 0xE879F9)],
                                             startPoint: .leading, endPoint: .trailing)
    static let plusGradient = LinearGradient(colors: [Color(hex: 0x2E1065), Color(hex: 0x581C87), Color(hex: 0x3B0764)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    static let corner: CGFloat = 18
    static let hPad: CGFloat = 16
}

// MARK: - Background

struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.accentDeep.opacity(0.35), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(hex: 0x4C1D95).opacity(0.18), .clear],
                           center: .bottomLeading, startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass modifiers

struct GlassCard: ViewModifier {
    var radius: CGFloat = Theme.corner
    var highlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Material.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card.opacity(0.86))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(highlighted ? Theme.accent.opacity(0.9) : Theme.stroke, lineWidth: highlighted ? 1.4 : 1)
            )
            .shadow(color: highlighted ? Theme.accent.opacity(0.35) : .clear, radius: 12)
    }
}

extension View {
    func glass(radius: CGFloat = Theme.corner, highlighted: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, highlighted: highlighted))
    }
}

@MainActor
func hapticTap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - Time formatting

enum TimeFmt {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    static func hours(_ seconds: Double) -> String {
        let h = seconds / 3600
        if h >= 1000 { return String(format: "%.1fk", h / 1000) }
        if h >= 10 { return "\(Int(h))" }
        return String(format: "%.1f", h)
    }

    static func relative(_ date: Date) -> String {
        let cal = Calendar.current
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "ru_RU")
        tf.dateFormat = "HH:mm"
        if cal.isDateInToday(date) { return "Сегодня, \(tf.string(from: date))" }
        if cal.isDateInYesterday(date) { return "Вчера, \(tf.string(from: date))" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMM, HH:mm"
        return df.string(from: date)
    }
}
