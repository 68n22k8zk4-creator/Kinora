import SwiftUI

/// Умный поиск: один запрос — сразу по всем подключённым сайтам.
/// Один и тот же тайтл на разных сайтах показывается в разделах каждого сайта.
struct SearchView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) var dismiss

    var initialQuery: String = ""

    @State private var query = ""
    @State private var searched = ""
    @State private var type: ContentType? = nil
    @State private var sourceID: UUID? = nil
    @State private var results: [UUID: [SiteItem]] = [:]
    @State private var loading: Set<UUID> = []
    @State private var expanded: Set<UUID> = []
    @State private var debounce: Task<Void, Never>? = nil
    @FocusState private var focused: Bool

    private var q: String { query.trimmingCharacters(in: .whitespaces) }

    private var sources: [VideoSource] {
        store.enabledSources.filter { sourceID == nil || $0.id == sourceID }
    }

    private func filtered(_ list: [SiteItem]) -> [SiteItem] {
        list.filter { (type == nil || $0.type == type) && ($0.type?.isAdult != true || store.data.settings.adultEnabled) }
    }

    private var allFound: [SiteItem] { sources.flatMap { results[$0.id] ?? [] } }

    private var libraryMatches: [MediaTitle] {
        guard !searched.isEmpty else { return [] }
        return store.visibleTitles.filter { $0.matches(searched) && (type == nil || $0.type == type) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SearchField(text: $query, placeholder: "Название фильма, сериала, аниме…",
                                onSubmit: { runSearch() }, focused: $focused)
                    Button("Отмена") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.accent2)
                }
                .padding(.horizontal, Theme.hPad)
                .padding(.top, 8)

                typeTabs
                filterBar

                if store.enabledSources.isEmpty {
                    EmptyStateView(icon: "link.badge.plus", title: "Нет подключённых сайтов",
                                   subtitle: "Добавьте сайты — и поиск будет искать сразу на всех.")
                    Button { router.push(.sources) } label: {
                        Text("Добавить сайт").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent2)
                    }
                    .padding(.horizontal, Theme.hPad)
                } else if searched.isEmpty {
                    historySection
                } else {
                    if !libraryMatches.isEmpty {
                        Text("В моей библиотеке").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, Theme.hPad)
                        LazyVStack(spacing: 10) {
                            ForEach(libraryMatches) { t in
                                TitleRow(title: t).onTapGesture { router.push(.title(t.id)) }
                            }
                        }
                        .padding(.horizontal, Theme.hPad)
                    }
                    ForEach(sources) { s in sourceSection(s) }
                    if !store.data.searchHistory.isEmpty { historySection }
                }
                TabBarSpacer()
            }
        }
        .background(AppBackground())
        .onAppear {
            if query.isEmpty && !initialQuery.isEmpty {
                query = initialQuery
                runSearch()
            } else if initialQuery.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            }
        }
        .onChange(of: query) { _ in
            debounce?.cancel()
            guard q.count >= 3, q != searched else { return }
            debounce = Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                runSearch()
            }
        }
    }

    // MARK: Search

    private func runSearch() {
        debounce?.cancel()
        let text = q
        guard text.count >= 2 else { return }
        focused = false
        searched = text
        store.addSearch(text)
        results = [:]
        expanded = []
        for s in store.enabledSources {
            loading.insert(s.id)
            Task {
                let found = await store.searchSite(s, query: text)
                guard searched == text else { return }
                results[s.id] = found
                loading.remove(s.id)
            }
        }
    }

    // MARK: Parts

    private var typeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tab(nil, "Все", "square.grid.2x2.fill", filteredCount(nil), Theme.accentSoft)
                ForEach(store.visibleTypes) { t in
                    tab(t, t.title, t.icon, filteredCount(t), t.tint)
                }
            }
            .padding(.horizontal, Theme.hPad)
            .padding(.vertical, 4)
        }
    }

    private func filteredCount(_ t: ContentType?) -> Int {
        allFound.filter { t == nil || $0.type == t }.count
    }

    private func tab(_ t: ContentType?, _ name: String, _ icon: String, _ count: Int, _ tint: Color) -> some View {
        let selected = type == t
        return Button { hapticTap(); type = t } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("(\(count))").font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            .frame(width: 76, height: 74)
            .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Theme.accentDeep.opacity(0.45) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.accent2 : Theme.stroke, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Все источники") { sourceID = nil }
                    ForEach(store.enabledSources) { s in Button(s.name) { sourceID = s.id } }
                } label: {
                    filterPill(sourceID.flatMap { store.source($0)?.name } ?? "Все источники", prominent: true)
                }
                if !searched.isEmpty {
                    Button { runSearch() } label: { filterPill("Обновить", prominent: false, icon: "arrow.clockwise") }
                        .buttonStyle(.plain)
                }
                if !loading.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().tint(Theme.accent2).scaleEffect(0.8)
                        Text("Ищу на \(loading.count) сайтах…").font(.system(size: 13)).foregroundStyle(Theme.text2)
                    }
                }
            }
            .padding(.horizontal, Theme.hPad)
        }
    }

    private func filterPill(_ text: String, prominent: Bool, icon: String = "chevron.down") -> some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(prominent ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.06))))
        .overlay(Capsule().stroke(prominent ? Color.clear : Theme.stroke))
    }

    private func sourceSection(_ s: VideoSource) -> some View {
        let list = filtered(results[s.id] ?? [])
        let isOpen = expanded.contains(s.id)
        let shown = isOpen ? list : Array(list.prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SourceIcon(source: s, size: 30)
                Text(s.name).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                if loading.contains(s.id) {
                    ProgressView().tint(Theme.accent2).scaleEffect(0.8)
                } else {
                    Text("\(list.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                }
                Spacer()
                if let url = s.searchURL(for: searched) {
                    Button {
                        router.webSession = WebSession(titleID: nil, season: 0, episode: 0, sourceID: s.id, url: url)
                    } label: {
                        Label("На сайте", systemImage: "globe").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent2)
                    }
                }
            }
            .padding(.horizontal, Theme.hPad)

            if !loading.contains(s.id) && list.isEmpty {
                Text(s.searchTemplate.isEmpty ? "У сайта не найден поиск — проверьте шаблон поиска в настройках источника"
                                              : "Ничего не найдено")
                    .font(.system(size: 13)).foregroundStyle(Theme.text3)
                    .padding(.horizontal, Theme.hPad)
            }

            LazyVStack(spacing: 10) {
                ForEach(shown) { it in
                    SearchResultRow(item: it)
                }
            }
            .padding(.horizontal, Theme.hPad)

            if list.count > 5 {
                Button {
                    withAnimation { if isOpen { expanded.remove(s.id) } else { expanded.insert(s.id) } }
                } label: {
                    Text(isOpen ? "Свернуть" : "Показать все \(list.count)")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.accent2)
                Text("История поиска").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                Spacer()
                if !store.data.searchHistory.isEmpty {
                    Button("Очистить всё") { store.data.searchHistory.removeAll() }
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent2)
                }
            }
            .padding(.horizontal, Theme.hPad)
            if store.data.searchHistory.isEmpty {
                Text("Здесь будут ваши запросы").font(.system(size: 13)).foregroundStyle(Theme.text3).padding(.horizontal, Theme.hPad)
            }
            FlowLayout(spacing: 8) {
                ForEach(store.data.searchHistory) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "clock").font(.system(size: 12))
                        Text(item.query).font(.system(size: 14))
                        Button { store.data.searchHistory.removeAll { $0.id == item.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().stroke(Theme.stroke))
                    .onTapGesture { query = item.query; runSearch() }
                }
            }
            .padding(.horizontal, Theme.hPad)
        }
    }
}

struct SearchResultRow: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    var item: SiteItem

    var body: some View {
        let lib = store.title(forURL: item.url)
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    LinearGradient(colors: (item.type ?? .movie).gradient, startPoint: .top, endPoint: .bottom)
                    SiteThumb(item: item)
                }
                .frame(width: 96, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let t = item.type { TypeBadge(type: t).padding(5) }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(item.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(3)
                    Spacer()
                    Button {
                        let t = store.ensureTitle(for: item)
                        store.toggleBookmark(t.id)
                    } label: {
                        Image(systemName: lib?.isBookmarked == true ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(lib?.isBookmarked == true ? Theme.accent2 : Theme.text2)
                    }
                    .buttonStyle(.plain)
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2)
                }
                if let lib, lib.status != .none {
                    Label(lib.status.title, systemImage: lib.status.icon)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(lib.status.color)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    SmallPlayButton(title: lib.flatMap { store.lastProgress(for: $0.id) } != nil ? "Продолжить" : "Смотреть") {
                        Watch.open(item, store: store, router: router, player: player)
                    }
                }
            }
        }
        .padding(10)
        .glass(radius: 18)
        .contentShape(Rectangle())
        .onTapGesture { router.push(.item(item)) }
    }
}

// MARK: - Flow layout (iOS 16+)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += s.width + spacing
            width = max(width, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
