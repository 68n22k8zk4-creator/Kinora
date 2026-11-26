import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            Group {
                switch router.tab {
                case .home: stack($router.homePath) { HomeView() }
                case .catalog: stack($router.catalogPath) { CatalogView() }
                case .library: stack($router.libraryPath) { LibraryView() }
                case .plus: stack($router.plusPath) { PlusView(isTab: true) }
                case .profile: stack($router.profilePath) { ProfileView() }
                }
            }

            VStack(spacing: 8) {
                if player.isMini { MiniPlayerBar().transition(.move(edge: .bottom).combined(with: .opacity)) }
                CustomTabBar()
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.isMini)

            if let toast = store.toast {
                VStack {
                    ToastView(text: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .animation(.spring(), value: store.toast)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $player.isPresented) {
            PlayerView()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(player)
        }
        .fullScreenCover(item: $router.webSession) { session in
            WebSourceView(session: session)
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(player)
        }
        .sheet(isPresented: $router.showNotifications) {
            NotificationsView().environmentObject(store)
        }
        .alert(item: $store.statusSuggestion) { s in
            Alert(title: Text("Досмотрено! 🎉"),
                  message: Text("Отметить «\(s.titleName)» как «Просмотрено»?"),
                  primaryButton: .default(Text("Просмотрено")) { store.setStatus(s.titleID, .watched) },
                  secondaryButton: .cancel(Text("Позже")))
        }
    }

    @ViewBuilder
    private func stack<Content: View>(_ path: Binding<NavigationPath>, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct RouteDestination: View {
    let route: Route

    var body: some View {
        Group {
            switch route {
            case .title(let id): TitleDetailView(titleID: id)
            case .item(let item): ItemDetailView(item: item)
            case .sourceFeed(let id): SourceFeedView(sourceID: id)
            case .sitePage(let id, let title, let url): SitePageView(sourceID: id, title: title, startURL: url)
            case .search(let q): SearchView(initialQuery: q)
            case .sources: SourcesView()
            case .settings: SettingsView()
            case .plus: PlusView(isTab: false)
            case .collection(let id): CollectionDetailView(collectionID: id)
            case .tag(let id): TagDetailView(tagID: id)
            case .tagsManager: TagsManagerView()
            case .history: HistoryView()
            case .downloads: DownloadsView()
            case .stats: StatsView()
            case .backup: BackupView()
            case .about: AboutView()
            case .list(let title, let filter): FilteredListView(title: title, filter: filter)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - AppTab bar

struct CustomTabBar: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = router.tab == tab
                Button {
                    hapticTap()
                    if router.tab == tab { popToRoot(tab) }
                    router.tab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selected ? tab.iconSelected : tab.icon)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(tab == .plus ? Theme.accentSoft.opacity(0.85) : Theme.text2))
                            .shadow(color: selected ? Theme.accent.opacity(0.7) : .clear, radius: 8)
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selected ? Theme.accent2 : Theme.text2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.bg2.opacity(0.75)))
        )
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.stroke))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private func popToRoot(_ tab: AppTab) {
        switch tab {
        case .home: router.homePath = NavigationPath()
        case .catalog: router.catalogPath = NavigationPath()
        case .library: router.libraryPath = NavigationPath()
        case .plus: router.plusPath = NavigationPath()
        case .profile: router.profilePath = NavigationPath()
        }
    }
}

/// Отступ снизу, чтобы контент не прятался под таб-баром
struct TabBarSpacer: View {
    @EnvironmentObject var player: PlayerManager
    var body: some View { Color.clear.frame(height: player.isMini ? 170 : 100) }
}

// MARK: - Header

struct AppHeader: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var store: LibraryStore
    var showsCrown = true
    var showsSearch = false

    var body: some View {
        HStack(spacing: 10) {
            KinoraLogo(size: 24)
            Spacer()
            if showsSearch {
                CircleIconButton(icon: "magnifyingglass") { router.push(.search("")) }
            }
            if showsCrown {
                CircleIconButton(icon: "crown.fill", tint: Theme.gold, filled: true) { router.tab = .plus }
            }
            CircleIconButton(icon: "bell", badge: false) { router.showNotifications = true }
            CircleIconButton(icon: "gearshape") { router.push(.settings) }
        }
        .padding(.horizontal, Theme.hPad)
    }
}

/// Шапка экрана с фоновой картинкой (как на макетах «Каталог», «Моя библиотека»)
struct HeroHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    var art: MediaTitle?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let art {
                PosterView(title: art, useBackdrop: true, showTitleOnPlaceholder: false)
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
                    .opacity(0.55)
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
            } else {
                LinearGradient(colors: [Theme.accentDeep.opacity(0.45), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
                    .frame(height: 230)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 34, weight: .heavy)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, Theme.hPad)
            .padding(.bottom, 6)
            VStack { trailing(); Spacer() }
        }
        .frame(height: 230)
    }
}

// MARK: - Mini player

struct MiniPlayerBar: View {
    @EnvironmentObject var player: PlayerManager

    var body: some View {
        HStack(spacing: 12) {
            VideoSurface(player: player.player, fill: true)
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentTitle?.name ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(player.headerSubtitle).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                ProgressLine(value: player.duration > 0 ? player.currentTime / player.duration : 0, height: 3)
            }
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36)
            }
            Button { player.close() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text2).frame(width: 30, height: 36)
            }
        }
        .padding(8)
        .glass(radius: 20)
        .padding(.horizontal, 12)
        .onTapGesture { player.expand() }
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 12) {
                                Text(item.1).font(.system(size: 26))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.0).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    Text(item.2).font(.system(size: 13)).foregroundStyle(Theme.text2)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .glass()
                        }
                    }
                    .padding(Theme.hPad)
                }
            }
            .navigationTitle("Уведомления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private var items: [(String, String, String)] {
        var list: [(String, String, String)] = []
        for (t, p) in store.continueWatching.prefix(3) {
            let ep = t.isEpisodic ? "Сезон \(p.season) • Серия \(p.episode)" : "Фильм"
            list.append(("Продолжить «\(t.name)»", "▶️", "\(ep) • остановились на \(TimeFmt.clock(p.position))"))
        }
        let offline = store.data.sources.filter { $0.health == .offline }
        if !offline.isEmpty {
            list.append(("Источники недоступны", "⚠️", offline.map(\.name).joined(separator: ", ")))
        }
        if list.isEmpty {
            list.append(("Пока тихо", "💜", "Здесь появятся напоминания о продолжении просмотра и статус источников."))
        }
        return list
    }
}
