import SwiftUI

struct PlanCard: View {
    var plan: PlanPeriod
    var currency: Currency
    var selected: Bool
    var popular: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: plan.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(selected ? Theme.gold : Theme.accentSoft)
            Text(plan.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text(currency.format(Pricing.price(plan, currency)))
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(plan.perText).font(.system(size: 12)).foregroundStyle(Theme.text2)
            if let pm = Pricing.perMonth(plan, currency), plan != .month {
                Text("≈ \(currency.format((pm * 100).rounded() / 100)) / мес.")
                    .font(.system(size: 10)).foregroundStyle(Theme.text3).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(plan == .lifetime ? "один платёж" : " ").font(.system(size: 10)).foregroundStyle(Theme.text3)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .frame(width: 128)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(selected ? AnyShapeStyle(LinearGradient(colors: [Theme.accentDeep.opacity(0.7), Color(hex: 0x3B0764)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.card))
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Theme.accent2 : Theme.stroke, lineWidth: selected ? 2 : 1))
        .shadow(color: selected ? Theme.accent.opacity(0.5) : .clear, radius: 14)
        .overlay(alignment: .top) {
            if popular {
                Text("Популярный").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 20)
                    .background(Capsule().fill(Theme.accentGradient))
                    .offset(y: -10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let s = Pricing.savings(plan, currency) {
                Text("-\(s)%").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Capsule().fill(Theme.gold))
                    .offset(x: -6, y: 8)
            }
        }
    }
}

struct PlusView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    var isTab: Bool

    @State private var selected: PlanPeriod = .year
    @State private var confirm = false

    private var currency: Currency { store.data.settings.currency }

    private let benefits: [(String, String, Bool, Bool)] = [
        ("Библиотека, поиск, каталог", "books.vertical.fill", true, true),
        ("Встроенный плеер и точная позиция", "play.rectangle.fill", true, true),
        ("Подключение сайтов-источников", "link", true, true),
        ("Неограниченные теги и коллекции", "tag.fill", false, true),
        ("Неограниченные источники", "infinity", false, true),
        ("Расширенная статистика и аналитика", "chart.bar.xaxis", false, true),
        ("Синхронизация и резервные копии", "arrow.triangle.2.circlepath.icloud.fill", false, true),
        ("Темы и персонализация", "paintpalette.fill", false, true),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if isTab { AppHeader(showsCrown: false).padding(.top, 6) } else { NavBar(title: "KINORA Plus") }

                hero

                if store.isPlus { activeCard }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Тарифные планы").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                        Spacer()
                        Menu {
                            Picker("Валюта", selection: $store.data.settings.currency) {
                                ForEach(Currency.allCases) { c in Text("\(c.code) · \(c.symbol)").tag(c) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(currency.code).font(.system(size: 14, weight: .semibold))
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 32)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                    .padding(.horizontal, Theme.hPad)

                    Picker("Валюта", selection: $store.data.settings.currency) {
                        ForEach(Currency.allCases) { c in Text(c.symbol).tag(c) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.hPad)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(PlanPeriod.allCases) { p in
                                Button { hapticTap(); selected = p } label: {
                                    PlanCard(plan: p, currency: currency, selected: selected == p, popular: p == .year)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        .padding(.horizontal, Theme.hPad)
                        .padding(.vertical, 14)
                    }

                    PrimaryButton(title: "Оформить \(selected.title.lowercased()) — \(currency.format(Pricing.price(selected, currency)))", icon: "crown.fill") {
                        confirm = true
                    }
                    .padding(.horizontal, Theme.hPad)

                    Text("Оплата в тестовой сборке не подключена: кнопка включает Plus локально для проверки функций. Для App Store понадобится StoreKit.")
                        .font(.system(size: 11)).foregroundStyle(Theme.text3)
                        .padding(.horizontal, Theme.hPad)
                }

                comparison
                priceTable
                TabBarSpacer()
            }
        }
        .background(isTab ? nil : AppBackground())
        .alert("Активировать KINORA Plus?", isPresented: $confirm) {
            Button("Активировать (тест)") { store.activatePlus(selected) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("\(selected.title) • \(currency.format(Pricing.price(selected, currency))). Тестовая активация без оплаты.")
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill").foregroundStyle(Theme.gold)
                    Text("KINORA Plus").font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(LinearGradient(colors: [Theme.gold, Color(hex: 0xF59E0B)], startPoint: .leading, endPoint: .trailing))
                }
                Text("Больше возможностей для максимального удовольствия от просмотра. Базовые функции остаются бесплатными.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 4) {
                    Text("от \(currency.format(Pricing.price(.month, currency))) / мес.").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text("или \(currency.format(Pricing.price(.year, currency))) / год").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            Spacer(minLength: 0)
            Text("👑").font(.system(size: 64)).shadow(color: Theme.gold.opacity(0.6), radius: 16)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.plusGradient))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.accent.opacity(0.7), lineWidth: 1.2))
        .shadow(color: Theme.accent.opacity(0.35), radius: 18)
        .padding(.horizontal, Theme.hPad)
    }

    private var activeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Plus активен").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text(activeText).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Button("Отключить") { store.deactivatePlus() }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.red)
        }
        .padding(14)
        .glass(highlighted: true)
        .padding(.horizontal, Theme.hPad)
    }

    private var activeText: String {
        guard let plan = store.data.profile.plusPlan else { return "" }
        if plan == .lifetime { return "Навсегда" }
        let df = DateFormatter(); df.locale = Locale(identifier: "ru_RU"); df.dateStyle = .long
        return "\(plan.title) • до \(df.string(from: store.data.profile.plusExpiresAt ?? Date()))"
    }

    private var comparison: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Возможности").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("Free").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2).frame(width: 48)
                Text("Plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.gold).frame(width: 48)
            }
            .padding(.bottom, 10)
            ForEach(Array(benefits.enumerated()), id: \.offset) { _, b in
                HStack(spacing: 10) {
                    Image(systemName: b.1).foregroundStyle(Theme.accent2).frame(width: 22)
                    Text(b.0).font(.system(size: 13)).foregroundStyle(.white)
                    Spacer()
                    mark(b.2).frame(width: 48)
                    mark(b.3).frame(width: 48)
                }
                .padding(.vertical, 9)
                Rectangle().fill(Theme.stroke).frame(height: 1)
            }
            HStack {
                Text("Лимиты Free: \(FreeLimits.tags) тегов, \(FreeLimits.collections) коллекции, \(FreeLimits.sources) источников")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(16)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }

    private func mark(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "minus")
            .foregroundStyle(on ? Theme.accent2 : Theme.text3)
    }

    /// Сводная таблица цен во всех валютах
    private var priceTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Цены во всех валютах").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("").frame(width: 92, alignment: .leading)
                        ForEach(Currency.allCases) { c in
                            Text(c.code).font(.system(size: 12, weight: .bold)).foregroundStyle(c == currency ? Theme.accent2 : Theme.text2)
                                .frame(width: 78)
                        }
                    }
                    .padding(.bottom, 8)
                    ForEach(PlanPeriod.allCases) { p in
                        HStack(spacing: 0) {
                            Text(p.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).frame(width: 92, alignment: .leading)
                            ForEach(Currency.allCases) { c in
                                Text(c.format(Pricing.price(p, c))).font(.system(size: 12)).foregroundStyle(c == currency ? .white : Theme.text2)
                                    .frame(width: 78)
                            }
                        }
                        .padding(.vertical, 7)
                        Rectangle().fill(Theme.stroke).frame(height: 1)
                    }
                }
            }
            Text("Экономия считается относительно помесячной оплаты.").font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
        .padding(16)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }
}
