import Foundation

enum Currency: String, Codable, CaseIterable, Identifiable {
    case czk, usd, eur, rub, uah

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .czk: return "Kč"
        case .usd: return "$"
        case .eur: return "€"
        case .rub: return "₽"
        case .uah: return "грн"
        }
    }

    var code: String { rawValue.uppercased() }

    func format(_ value: Double) -> String {
        let isWhole = value.rounded() == value
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.decimalSeparator = self == .usd ? "." : ","
        f.minimumFractionDigits = isWhole ? 0 : 2
        f.maximumFractionDigits = isWhole ? 0 : 2
        let num = f.string(from: NSNumber(value: value)) ?? "\(value)"
        switch self {
        case .usd: return "$\(num)"
        case .eur: return "\(num) €"
        default: return "\(num) \(symbol)"
        }
    }
}

enum PlanPeriod: String, Codable, CaseIterable, Identifiable {
    case month, quarter, halfYear, year, lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "1 месяц"
        case .quarter: return "3 месяца"
        case .halfYear: return "6 месяцев"
        case .year: return "1 год"
        case .lifetime: return "Навсегда"
        }
    }

    var perText: String {
        switch self {
        case .month: return "/ мес."
        case .quarter: return "/ 3 мес."
        case .halfYear: return "/ 6 мес."
        case .year: return "/ год"
        case .lifetime: return "разово"
        }
    }

    var months: Int? {
        switch self {
        case .month: return 1
        case .quarter: return 3
        case .halfYear: return 6
        case .year: return 12
        case .lifetime: return nil
        }
    }

    var icon: String {
        switch self {
        case .month: return "calendar"
        case .quarter: return "calendar.badge.clock"
        case .halfYear: return "calendar.circle"
        case .year: return "crown.fill"
        case .lifetime: return "infinity"
        }
    }
}

enum Pricing {
    /// Цены подобраны вручную (психологическое округление), а не по живому курсу.
    static let table: [Currency: [PlanPeriod: Double]] = [
        .czk: [.month: 79,   .quarter: 219,  .halfYear: 399,   .year: 699,   .lifetime: 1999],
        .usd: [.month: 3.49, .quarter: 9.49, .halfYear: 16.99, .year: 29.99, .lifetime: 84.99],
        .eur: [.month: 2.99, .quarter: 8.49, .halfYear: 15.49, .year: 27.99, .lifetime: 79.99],
        .rub: [.month: 299,  .quarter: 799,  .halfYear: 1490,  .year: 2690,  .lifetime: 7490],
        .uah: [.month: 149,  .quarter: 399,  .halfYear: 749,   .year: 1290,  .lifetime: 3690],
    ]

    static func price(_ plan: PlanPeriod, _ currency: Currency) -> Double {
        table[currency]?[plan] ?? 0
    }

    /// Экономия в % относительно помесячной оплаты
    static func savings(_ plan: PlanPeriod, _ currency: Currency) -> Int? {
        guard let months = plan.months, months > 1 else { return nil }
        let monthly = price(.month, currency) * Double(months)
        let p = price(plan, currency)
        guard monthly > 0 else { return nil }
        let s = Int(((monthly - p) / monthly * 100).rounded())
        return s > 0 ? s : nil
    }

    static func perMonth(_ plan: PlanPeriod, _ currency: Currency) -> Double? {
        guard let months = plan.months else { return nil }
        return price(plan, currency) / Double(months)
    }
}

/// Лимиты бесплатной версии — базовые функции не блокируются
enum FreeLimits {
    static let tags = 8
    static let collections = 3
    static let sources = 5
}
