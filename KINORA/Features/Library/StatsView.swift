import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                NavBar(title: "Статистика")

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatTile(icon: "checkmark.seal.fill", iconColor: Theme.green, value: "\(store.statWatchedCount)", label: "Просмотрено тайтлов")
                    StatTile(icon: "clock.fill", iconColor: Theme.accentSoft, value: "\(TimeFmt.hours(store.statTotalSeconds)) ч", label: "Всего часов")
                    StatTile(icon: "star.fill", iconColor: Theme.gold, value: store.statAverageRating > 0 ? String(format: "%.1f", store.statAverageRating) : "—", label: "Средний рейтинг")
                    StatTile(icon: "flame.fill", iconColor: .orange, value: "\(store.statActiveDays)", label: "Дней активности")
                }
                .padding(.horizontal, Theme.hPad)

                ZStack {
                    VStack(alignment: .leading, spacing: 18) {
                        weekly
                        byType
                        topGenres
                    }
                    .blur(radius: store.isPlus ? 0 : 6)
                    .allowsHitTesting(store.isPlus)

                    if !store.isPlus {
                        VStack(spacing: 10) {
                            Image(systemName: "crown.fill").font(.system(size: 30)).foregroundStyle(Theme.gold)
                            Text("Расширенная статистика").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            Text("Активность по дням, жанры и типы контента — в KINORA Plus").font(.system(size: 13))
                                .foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                            PrimaryButton(title: "Открыть Plus", icon: "crown.fill", height: 46) { router.tab = .plus }
                                .frame(width: 220)
                        }
                        .padding(20)
                        .glass(highlighted: true)
                        .padding(.horizontal, 30)
                    }
                }
                TabBarSpacer()
            }
        }
        .background(AppBackground())
    }

    private var weekly: some View {
        let data = store.weeklyActivity()
        let maxV = max(data.map { $0.1 }.max() ?? 1, 1)
        let df: DateFormatter = {
            let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "EE"; return f
        }()
        return VStack(alignment: .leading, spacing: 12) {
            Text("Активность за неделю").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 6) {
                        Text(item.1 > 0 ? "\(Int(item.1 / 60))м" : "").font(.system(size: 10)).foregroundStyle(Theme.text2)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.accentGradient)
                            .frame(height: max(4, CGFloat(item.1 / maxV) * 110))
                        Text(df.string(from: item.0)).font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150, alignment: .bottom)
        }
        .padding(16)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }

    private var byType: some View {
        let data = store.statByType()
        let total = max(data.map { $0.1 }.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("По типам").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Image(systemName: item.0.icon).foregroundStyle(item.0.tint).frame(width: 22)
                    Text(item.0.title).font(.system(size: 14)).foregroundStyle(.white).frame(width: 100, alignment: .leading)
                    ProgressLine(value: Double(item.1) / Double(total), height: 6)
                    Text("\(item.1)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2).frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }

    private var topGenres: some View {
        var counts: [String: Int] = [:]
        for t in store.visibleTitles where t.status == .watched || t.status == .watching {
            for g in t.genres { counts[g, default: 0] += 1 }
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(6)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Любимые жанры").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            if top.isEmpty { Text("Пока мало данных").font(.system(size: 13)).foregroundStyle(Theme.text3) }
            FlowLayout(spacing: 8) {
                ForEach(Array(top.enumerated()), id: \.offset) { _, g in
                    Chip(title: "\(g.key) · \(g.value)", selected: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }
}
