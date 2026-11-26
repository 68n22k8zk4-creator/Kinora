import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    @State private var heroIndex = 0

    /// Для слайдера берём по 1–2 свежих тайтла с каждого сайта
    private var featured: [SiteItem] {
        var out: [SiteItem] = []
        let lists = store.enabledSources.map { store.items(of: $0.id).filter { $0.type?.isAdult != true || store.data.settings.adultEnabled } }
        var i = 0
        while out.count < 6 && lists.contains(where: { $0.count > i }) {
            for l in lists where l.count > i && out.count < 6 { out.append(l[i]) }
            i += 1
        }
        return out
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                AppHeader().padding(.top, 6)

                HStack(spacing: 10) {
                    Button { router.push(.search("")) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium))
                            Text("Поиск по всем сайтам…").font(.system(size: 16))
                            Spacer()
                        }
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .overlay(Capsule().stroke(Theme.stroke))
                    }
                    .buttonStyle(.plain)
                    CircleIconButton(icon: "link.badge.plus", size: 50) { router.push(.sources) }
                }
                .padding(.horizontal, Theme.hPad)

                if store.data.sources.isEmpty {
                    OnboardingCard()
                } else {
                    if !featured.isEmpty {
                        TabView(selection: $heroIndex) {
                            ForEach(Array(featured.enumerated()), id: \.element.id) { index, it in
                                SiteHeroCard(item: it, index: index, total: featured.count)
                                    .padding(.horizontal, Theme.hPad)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 340)
                    } else if store.isRefreshingAny {
                        loadingCard
                    }

                    sitesStrip

                    if !store.continueWatching.isEmpty {
                        VStack(spacing: 12) {
                            SectionHeader(title: "Продолжить просмотр", action: "Все") { router.push(.history) }
                            TabView {
                                ForEach(Array(store.continueWatching.prefix(5).enumerated()), id: \.offset) { _, entry in
                                    ContinueCard(title: entry.title, progress: entry.progress)
                                        .padding(.horizontal, Theme.hPad)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: store.continueWatching.count > 1 ? .automatic : .never))
                            .frame(height: 140)
                        }
                    }

                    ForEach(store.enabledSources) { s in
                        SourceShelf(source: s)
                    }
                }

                TabBarSpacer()
            }
        }
        .refreshable { await store.refreshAll(force: true) }
        .task {
            await store.refreshAll()
            await store.buildMissingIndexes()
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.accent2)
            Text("Загружаю тайтлы с ваших сайтов…").font(.system(size: 14)).foregroundStyle(Theme.text2)
            Spacer()
        }
        .padding(18)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }

    /// Быстрый переход к каждому сайту
    private var sitesStrip: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Мои сайты", action: "Управление") { router.push(.sources) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.enabledSources) { s in
                        Button { router.push(.sourceFeed(s.id)) } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    SourceIcon(source: s, size: 46)
                                    if store.refreshing.contains(s.id) {
                                        ProgressView().scaleEffect(0.6).offset(x: 8, y: -8)
                                    }
                                }
                                Text(s.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                Text("\(max(store.items(of: s.id).count, store.indexCount(s.id))) тайтлов").font(.system(size: 11)).foregroundStyle(Theme.text2)
                            }
                            .frame(width: 100, height: 112)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    Button { router.push(.sources) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.accent2)
                            Text("Добавить").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        }
                        .frame(width: 100, height: 112)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5])))
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, Theme.hPad)
            }
        }
    }
}

// MARK: - Полка одного сайта

struct SourceShelf: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    var source: VideoSource

    var body: some View {
        let items = store.items(of: source.id).filter { $0.type?.isAdult != true || store.data.settings.adultEnabled }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SourceIcon(source: source, size: 28)
                Text(source.name).font(.system(size: 21, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                if store.refreshing.contains(source.id) { ProgressView().tint(Theme.accent2).scaleEffect(0.8) }
                Spacer()
                Button { router.push(.sourceFeed(source.id)) } label: {
                    HStack(spacing: 4) { Text("Все"); Image(systemName: "arrow.right") }
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent2)
                }
            }
            .padding(.horizontal, Theme.hPad)

            CategoryChips(sourceID: source.id, limit: 15)

            if items.isEmpty {
                HStack(spacing: 10) {
                    if store.refreshing.contains(source.id) {
                        Text("Загружаю…").font(.system(size: 13)).foregroundStyle(Theme.text2)
                    } else {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.gold)
                        Text(store.feed(source.id)?.error ?? "Пока ничего не загружено")
                            .font(.system(size: 13)).foregroundStyle(Theme.text2).lineLimit(2)
                        Spacer()
                        Button("Открыть") { router.push(.sourceFeed(source.id)) }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent2)
                    }
                }
                .padding(14)
                .glass(radius: 16)
                .padding(.horizontal, Theme.hPad)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items.prefix(30)) { it in
                            Button { router.push(.item(it)) } label: { SiteItemPoster(item: it) }
                                .buttonStyle(PressableStyle())
                        }
                        Button { router.push(.sourceFeed(source.id)) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "square.grid.3x3.fill").font(.system(size: 26)).foregroundStyle(Theme.accent2)
                                Text(store.indexCount(source.id) > items.count ? "Все \(store.indexCount(source.id))" : "Все \(items.count)+")
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                Text(store.indexing[source.id] != nil ? "собираю…" : "весь сайт").font(.system(size: 11)).foregroundStyle(Theme.text2)
                            }
                            .frame(width: 118, height: 168)
                            .glass(radius: 14)
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(.horizontal, Theme.hPad)
                }
            }
        }
    }
}

// MARK: - Слайдер

struct SiteHeroCard: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    var item: SiteItem
    var index: Int
    var total: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                LinearGradient(colors: (item.type ?? .movie).gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                SiteThumb(item: item)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                Text(store.source(item.sourceID)?.name ?? "Новое")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentSoft)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentDeep.opacity(0.6)))
                Text(item.title)
                    .font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
                    .lineLimit(3).minimumScaleFactor(0.6)
                    .frame(maxWidth: 260, alignment: .leading)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                        .frame(maxWidth: 260, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Button {
                        hapticTap(.medium)
                        Watch.open(item, store: store, router: router, player: player)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Смотреть").font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22).frame(height: 48)
                        .background(Capsule().fill(.white))
                    }
                    .buttonStyle(PressableStyle())
                    Button { router.push(.item(item)) } label: {
                        Image(systemName: "info").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(Circle().fill(Color.white.opacity(0.14)))
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)

            HStack { Spacer()
                VStack { Spacer()
                    Text("\(index + 1) / \(total)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(.black.opacity(0.55)))
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.strokeHi))
        .contentShape(Rectangle())
        .onTapGesture { router.push(.item(item)) }
    }
}

// MARK: - Первый запуск

struct OnboardingCard: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @State private var url = ""
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("👋 Добро пожаловать в KINORA").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
            Text("Добавьте сайты, на которых вы смотрите фильмы, сериалы и аниме. KINORA соберёт с них каталог, поиск и «продолжить просмотр» в одном месте.")
                .font(.system(size: 14)).foregroundStyle(Theme.text2)
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "link").foregroundStyle(Theme.text2)
                    TextField("", text: $url, prompt: Text("Адрес сайта, например site.com").foregroundColor(Theme.text3))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .foregroundStyle(.white)
                        .onSubmit(add)
                }
                .padding(.horizontal, 14).frame(height: 50)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(Theme.accent.opacity(0.4)))
                Button(action: add) {
                    Group {
                        if adding { ProgressView().tint(.white) } else { Image(systemName: "plus").font(.system(size: 18, weight: .bold)) }
                    }
                    .foregroundStyle(.white).frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.accentGradient))
                }
                .buttonStyle(.plain)
            }
            Button { router.push(.sources) } label: {
                HStack { Text("Все настройки источников"); Image(systemName: "arrow.right") }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent2)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.plusGradient))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.accent.opacity(0.6)))
        .padding(.horizontal, Theme.hPad)
    }

    private func add() {
        adding = true
        Task {
            await store.addSite(url)
            url = ""
            adding = false
        }
    }
}

extension Int {
    var compactString: String {
        if self >= 1000 { return String(format: "%.1fK", Double(self) / 1000) }
        return "\(self)"
    }
}
