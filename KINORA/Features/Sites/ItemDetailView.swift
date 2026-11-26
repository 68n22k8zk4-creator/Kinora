import SwiftUI

/// Красивая «обёртка» над страницей тайтла на сайте:
/// постер, описание, статус, теги и кнопка «Смотреть» — без рекламы и лишнего.
struct ItemDetailView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) var dismiss

    let item: SiteItem

    @State private var page: ScrapeResult? = nil
    @State private var loading = true
    @State private var expanded = false
    @State private var showTagPicker = false

    private var lib: MediaTitle? { store.title(forURL: item.url) }
    private var source: VideoSource? { store.source(item.sourceID) }
    private var heroImage: String { (page?.image.isEmpty == false ? page!.image : item.imageURL) }
    private var displayTitle: String {
        if let t = page?.pageTitle, !t.isEmpty, t.count < 120, t.lowercased().contains(item.title.lowercased().prefix(4)) { return t }
        return item.title
    }
    private var related: [SiteItem] {
        (page?.items ?? []).filter { $0.url != item.url }.prefix(18).map { $0 }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                banner
                actions
                if let lib, let p = store.lastProgress(for: lib.id) { progressRow(p) }
                statusRow
                descriptionBlock
                tagsRow
                otherSites
                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Похожее на \(source?.name ?? "сайте")")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(related) { r in
                                    Button { router.push(.item(r)) } label: { SiteItemPoster(item: r) }
                                        .buttonStyle(PressableStyle())
                                }
                            }
                            .padding(.horizontal, Theme.hPad)
                        }
                    }
                }
                TabBarSpacer()
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(AppBackground())
        .task { await loadPage() }
        .sheet(isPresented: $showTagPicker) {
            if let lib { TagPickerSheet(titleID: lib.id).environmentObject(store) }
        }
    }

    // MARK: Parts

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: URL(string: heroImage), referer: source?.baseURL,
                        videoURL: URL(string: (page?.video.isEmpty == false ? page!.video : item.videoURL)))
                .frame(height: 400)
                .frame(maxWidth: .infinity)
                .blur(radius: 18)
                .opacity(0.7)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.35), .clear, Theme.bg.opacity(0.9), Theme.bg], startPoint: .top, endPoint: .bottom)

            VStack {
                HStack(spacing: 10) {
                    CircleIconButton(icon: "chevron.left") { dismiss() }
                    Spacer()
                    CircleIconButton(icon: lib?.isBookmarked == true ? "bookmark.fill" : "bookmark",
                                     tint: lib?.isBookmarked == true ? Theme.accent2 : .white) {
                        let t = store.ensureTitle(for: item)
                        store.toggleBookmark(t.id)
                    }
                    Menu {
                        if let url = URL(string: item.url) {
                            Link(destination: url) { Label("Открыть в Safari", systemImage: "safari") }
                            ShareLink(item: url) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                        }
                        Button { router.push(.search(item.title)) } label: { Label("Искать на всех сайтах", systemImage: "magnifyingglass") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.08)))
                            .overlay(Circle().stroke(Theme.stroke))
                    }
                }
                .padding(.horizontal, Theme.hPad)
                .padding(.top, 56)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 16) {
                ZStack {
                    LinearGradient(colors: (item.type ?? .movie).gradient, startPoint: .top, endPoint: .bottom)
                    SiteThumb(item: item)
                }
                .frame(width: 128, height: 184)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.strokeHi))
                .shadow(color: .black.opacity(0.6), radius: 14, y: 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayTitle).font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                        .lineLimit(4).minimumScaleFactor(0.6)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2).lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        if let s = source {
                            HStack(spacing: 5) {
                                SourceIcon(source: s, size: 20)
                                Text(s.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 8).frame(height: 28)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        if let type = item.type { Chip(title: type.singular, compact: true) }
                    }
                }
            }
            .padding(.horizontal, Theme.hPad)
        }
        .frame(height: 400)
    }

    private var actions: some View {
        let p = lib.flatMap { store.lastProgress(for: $0.id) }
        return HStack(spacing: 10) {
            PrimaryButton(title: p == nil ? "Смотреть" : "Продолжить",
                          subtitle: p.map { "с \(TimeFmt.clock($0.position))" } ?? source.map { "на \($0.name)" },
                          height: 58) {
                Watch.open(item, store: store, router: router, player: player)
            }
            Button {
                let t = store.ensureTitle(for: item)
                store.toggleFavorite(t.id)
            } label: {
                Image(systemName: lib?.isFavorite == true ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(lib?.isFavorite == true ? Theme.pink : .white)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, Theme.hPad)
    }

    private func progressRow(_ p: WatchProgress) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.accent2)
            VStack(alignment: .leading, spacing: 5) {
                Text("Остановились на \(TimeFmt.clock(p.position)) из \(TimeFmt.clock(p.duration))")
                    .font(.system(size: 13)).foregroundStyle(.white)
                ProgressLine(value: p.fraction)
            }
            Text("\(Int(p.fraction * 100))%").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
        }
        .padding(14)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }

    private var statusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([WatchStatus.planned, .watching, .watched, .dropped]) { s in
                    Button {
                        hapticTap()
                        let t = store.ensureTitle(for: item)
                        store.setStatus(t.id, t.status == s ? .none : s)
                    } label: {
                        Chip(title: s.title, icon: s.icon, selected: lib?.status == s,
                             tint: s == .watched ? Color(hex: 0x16A34A) : (s == .dropped ? Color(hex: 0xB91C1C) : Theme.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.hPad)
        }
    }

    @ViewBuilder
    private var descriptionBlock: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.accent2)
                Text("Загружаю страницу с \(source?.name ?? "сайта")…").font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, Theme.hPad)
        } else if let d = page?.description, !d.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text(d).font(.system(size: 15)).foregroundStyle(Theme.text2)
                    .lineLimit(expanded ? nil : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { withAnimation { expanded.toggle() } } label: {
                    Text(expanded ? "Свернуть" : "Подробнее").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent2)
                }
            }
            .padding(.horizontal, Theme.hPad)
        }
    }

    private var tagsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Теги").font(.system(size: 20, weight: .bold)).foregroundStyle(.white).padding(.top, 6)
            FlowLayout(spacing: 8) {
                ForEach((lib?.tagIDs ?? []).compactMap { store.tag($0) }) { tag in
                    Chip(title: tag.name, emoji: tag.emoji, selected: true, tint: tag.color.opacity(0.55))
                }
                Button {
                    store.ensureTitle(for: item)
                    showTagPicker = true
                } label: { Chip(title: "", icon: "plus") }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.hPad)
    }

    /// Тот же тайтл на других подключённых сайтах
    @ViewBuilder
    private var otherSites: some View {
        let others = store.enabledSources.filter { $0.id != item.sourceID }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "На других сайтах")
                ForEach(others) { s in
                    Button { router.push(.search(item.title)) } label: {
                        HStack(spacing: 12) {
                            SourceIcon(source: s, size: 36)
                            Text(s.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            Text("Найти").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent2)
                            Image(systemName: "chevron.right").foregroundStyle(Theme.text3)
                        }
                        .padding(10)
                        .glass(radius: 16)
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.horizontal, Theme.hPad)
                }
            }
        }
    }

    private func loadPage() async {
        guard page == nil, let url = URL(string: item.url) else { return }
        loading = true
        let r = await SiteScraper.scrape(url, sourceID: item.sourceID, category: item.type ?? source?.category)
        page = r
        loading = false
        if let lib { store.enrich(lib.id, with: r) }
    }
}

// MARK: - Лента одного сайта

struct SourceFeedView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    let sourceID: UUID
    @State private var query = ""
    @State private var results: [SiteItem]? = nil
    @State private var searching = false
    @State private var mode = 0   // 0 — лента, 1 — весь сайт

    private var source: VideoSource? { store.source(sourceID) }

    var body: some View {
        let items = results ?? store.items(of: sourceID)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                NavBar(title: source?.name ?? "Сайт") {
                    if store.refreshing.contains(sourceID) {
                        ProgressView().tint(Theme.accent2).frame(width: 44, height: 44)
                    } else {
                        CircleIconButton(icon: "arrow.clockwise") { Task { await store.refreshFeed(sourceID) } }
                    }
                    CircleIconButton(icon: "globe") { browse() }
                }

                Picker("", selection: $mode) {
                    Text("Лента").tag(0)
                    Text("Весь сайт" + (store.indexCount(sourceID) > 0 ? " (\(store.indexCount(sourceID)))" : "")).tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.hPad)

                if mode == 1 {
                    SiteIndexSection(sourceID: sourceID)
                } else {
                feedContent(items)
                }
                TabBarSpacer()
            }
        }
        .background(AppBackground())
        .refreshable { if mode == 0 { await store.refreshFeed(sourceID) } else { await store.buildSitemapIndex(sourceID) } }
    }

    @ViewBuilder
    private func feedContent(_ items: [SiteItem]) -> some View {
                HStack(spacing: 10) {
                    SearchField(text: $query, placeholder: "Поиск на \(source?.name ?? "сайте")…", onSubmit: search)
                    if searching { ProgressView().tint(Theme.accent2) }
                }
                .padding(.horizontal, Theme.hPad)
                .onChange(of: query) { q in if q.isEmpty { results = nil } }

                if results == nil { CategoryChips(sourceID: sourceID) }

                if let err = store.feed(sourceID)?.error, results == nil, items.isEmpty {
                    feedError(err)
                }

                if items.isEmpty && !store.refreshing.contains(sourceID) && store.feed(sourceID)?.error == nil {
                    EmptyStateView(icon: "sparkles.tv", title: results == nil ? "Лента пуста" : "Ничего не найдено",
                                   subtitle: "Обновите ленту или откройте сайт кнопкой 🌐")
                }

                Text("В ленте \(items.count)" + (store.indexCount(sourceID) > 0 ? " • на сайте \(store.indexCount(sourceID))" : "")).font(.system(size: 13)).foregroundStyle(Theme.text2)
                    .padding(.horizontal, Theme.hPad)

                ItemGrid(items: items, showsSource: false) {
                    if results == nil { Task { await store.loadMore(sourceID) } }
                }

                if results == nil {
                    PagingFooter(loading: store.loadingMore.contains(sourceID), hasMore: store.canLoadMore(sourceID)) {
                        Task { await store.loadMore(sourceID) }
                    }
                    if !store.canLoadMore(sourceID) && store.indexCount(sourceID) > items.count {
                        Button { mode = 1 } label: {
                            Label("Показать все \(store.indexCount(sourceID)) тайтлов сайта", systemImage: "square.stack.3d.up.fill")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Capsule().fill(Theme.accentGradient))
                        }
                        .padding(.horizontal, Theme.hPad)
                    }
                }
    }

    private func feedError(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13)).foregroundStyle(Theme.gold)
            HStack {
                SecondaryButton(title: "Открыть сайт", icon: "globe", height: 42) { browse() }
                SecondaryButton(title: "Повторить", icon: "arrow.clockwise", height: 42) {
                    Task { await store.refreshFeed(sourceID) }
                }
            }
        }
        .padding(14)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let s = source else { return }
        searching = true
        store.addSearch(q)
        Task {
            results = await store.searchSite(s, query: q)
            searching = false
        }
    }

    private func browse() {
        guard let s = source, let url = URL(string: s.baseURL) else { return }
        router.webSession = WebSession(titleID: nil, season: 0, episode: 0, sourceID: s.id, url: url)
    }
}

// MARK: - Разделы сайта (категории)

struct CategoryChips: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    let sourceID: UUID
    var limit: Int = 60

    var body: some View {
        let cats = Array((store.feed(sourceID)?.categories ?? []).prefix(limit))
        if !cats.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cats) { c in
                        Button { router.push(.sitePage(sourceID, c.title, c.url)) } label: {
                            Chip(title: c.title)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.hPad)
            }
        }
    }
}

// MARK: - Страница раздела с бесконечной прокруткой

struct SitePageView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    let sourceID: UUID
    let title: String
    let startURL: String

    @State private var items: [SiteItem] = []
    @State private var nextURL: String = ""
    @State private var loading = false
    @State private var started = false
    @State private var subCats: [SiteLink] = []
    @State private var pages = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                NavBar(title: title) {
                    CircleIconButton(icon: "globe") {
                        if let url = URL(string: startURL) {
                            router.webSession = WebSession(titleID: nil, season: 0, episode: 0, sourceID: sourceID, url: url)
                        }
                    }
                }
                if let s = store.source(sourceID) {
                    HStack(spacing: 6) {
                        SourceIcon(source: s, size: 20)
                        Text("\(s.name) • \(items.count) тайтлов • стр. \(max(pages, 1))")
                            .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, Theme.hPad)
                }
                if !subCats.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(subCats.prefix(40)) { c in
                                Button { router.push(.sitePage(sourceID, c.title, c.url)) } label: { Chip(title: c.title, compact: true) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.hPad)
                    }
                }
                if items.isEmpty && !loading && started {
                    EmptyStateView(icon: "tray", title: "Пусто", subtitle: "В этом разделе не найдено карточек. Откройте его на сайте кнопкой 🌐")
                }
                ItemGrid(items: items, showsSource: false) { Task { await loadNext() } }
                PagingFooter(loading: loading, hasMore: !nextURL.isEmpty) { Task { await loadNext() } }
                TabBarSpacer()
            }
        }
        .background(AppBackground())
        .task {
            guard !started else { return }
            started = true
            nextURL = startURL
            await loadNext()
        }
        .refreshable {
            items = []; pages = 0; nextURL = startURL
            await loadNext()
        }
    }

    private func loadNext() async {
        guard !loading, !nextURL.isEmpty, let url = URL(string: nextURL), let s = store.source(sourceID) else { return }
        loading = true
        let current = nextURL
        let r = await SiteScraper.scrape(url, sourceID: sourceID, category: s.category)
        let known = Set(items.map(\.url))
        let fresh = r.items.filter { !known.contains($0.url) }
        items.append(contentsOf: fresh)
        pages += 1
        if subCats.isEmpty {
            let main = Set((store.feed(sourceID)?.categories ?? []).map(\.url))
            subCats = r.categories.filter { !main.contains($0.url) && $0.url != startURL }
        }
        nextURL = (fresh.isEmpty || r.nextURL == current) ? "" : r.nextURL
        loading = false
    }
}

// MARK: - Общие части

/// Сетка карточек; onReachEnd вызывается, когда видна одна из последних карточек
struct ItemGrid: View {
    @EnvironmentObject var router: AppRouter
    var items: [SiteItem]
    var showsSource: Bool = true
    var onReachEnd: () -> Void = {}

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                Button { router.push(.item(it)) } label: { SiteItemCard(item: it, showsSource: showsSource) }
                    .buttonStyle(PressableStyle())
                    .onAppear { if i >= items.count - 6 { onReachEnd() } }
            }
        }
        .padding(.horizontal, Theme.hPad)
    }
}

struct PagingFooter: View {
    var loading: Bool
    var hasMore: Bool
    var action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            if loading {
                ProgressView().tint(Theme.accent2)
                Text("Загружаю следующую страницу…").font(.system(size: 13)).foregroundStyle(Theme.text2)
            } else if hasMore {
                Button(action: action) {
                    Label("Ещё", systemImage: "arrow.down.circle")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent2)
                }
            } else {
                Text("Это всё 👀").font(.system(size: 13)).foregroundStyle(Theme.text3)
            }
            Spacer()
        }
        .frame(height: 44)
    }
}
