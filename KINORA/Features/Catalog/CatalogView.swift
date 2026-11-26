import SwiftUI

enum SortOption: String, CaseIterable, Identifiable {
    case popular, rating, release, alphabet, added
    var id: String { rawValue }
    var title: String {
        switch self {
        case .popular: return "Популярные"
        case .rating: return "По рейтингу"
        case .release: return "По дате выхода"
        case .alphabet: return "По алфавиту"
        case .added: return "Недавно добавленные"
        }
    }
}

enum CatalogStatusFilter: String, CaseIterable, Identifiable {
    case all, watched, watching, notStarted, dropped, noRating, bookmarked
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Все"
        case .watched: return "Уже смотрел"
        case .watching: return "Сейчас смотрю"
        case .notStarted: return "Не начинал"
        case .dropped: return "Забросил"
        case .noRating: return "Нет оценки"
        case .bookmarked: return "В закладках"
        }
    }

    func matches(_ t: MediaTitle) -> Bool {
        switch self {
        case .all: return true
        case .watched: return t.status == .watched
        case .watching: return t.status == .watching
        case .notStarted: return t.status == .none || t.status == .planned
        case .dropped: return t.status == .dropped
        case .noRating: return t.userRating == nil
        case .bookmarked: return t.isBookmarked
        }
    }
}

func sortTitles(_ list: [MediaTitle], by sort: SortOption) -> [MediaTitle] {
    switch sort {
    case .popular: return list.sorted { $0.popularity > $1.popularity }
    case .rating: return list.sorted { $0.rating > $1.rating }
    case .release: return list.sorted { $0.year > $1.year }
    case .alphabet: return list.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    case .added: return list.sorted { $0.addedAt > $1.addedAt }
    }
}

struct CatalogView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter

    @State private var query = ""
    @State private var sourceFilter: UUID? = nil
    @State private var statusFilter: CatalogStatusFilter = .all
    @State private var sortAZ = false
    @AppStorage("catalog.grid") private var isGrid = true

    private var type: ContentType? { router.catalogType }

    private var base: [SiteItem] {
        store.allItems.filter { (type == nil || $0.type == type) && (sourceFilter == nil || $0.sourceID == sourceFilter) }
    }

    private var results: [SiteItem] {
        var list = base
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { list = list.filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) } }
        if statusFilter != .all {
            list = list.filter { it in
                if let t = store.title(forURL: it.url) { return statusFilter.matches(t) }
                return statusFilter == .notStarted || statusFilter == .noRating
            }
        }
        if sortAZ { list.sort { $0.title.localizedCompare($1.title) == .orderedAscending } }
        return list
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .top) {
                    catalogHeader
                    AppHeader().padding(.top, 6)
                }

                HStack(spacing: 10) {
                    SearchField(text: $query, placeholder: "Фильтр по загруженным тайтлам…")
                    CircleIconButton(icon: "magnifyingglass", filled: true, size: 50) { router.push(.search(query)) }
                }
                .padding(.horizontal, Theme.hPad)

                typeSelector
                controls
                sourceChips

                if store.data.sources.isEmpty {
                    OnboardingCard()
                } else if results.isEmpty {
                    if store.isRefreshingAny {
                        HStack { ProgressView().tint(Theme.accent2); Text("Загружаю сайты…").foregroundStyle(Theme.text2) }
                            .padding(.horizontal, Theme.hPad)
                    } else {
                        EmptyStateView(icon: "film.stack", title: "Ничего не найдено",
                                       subtitle: "Попробуйте другой тип или фильтр. Кнопка 🔍 ищет прямо на сайтах.")
                    }
                } else if isGrid {
                    ItemGrid(items: results) { loadMore() }
                    PagingFooter(loading: !store.loadingMore.isEmpty, hasMore: pagingIDs.contains { store.canLoadMore($0) }) { loadMore() }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, it in
                            Button { router.push(.item(it)) } label: { SiteItemRow(item: it) }
                                .buttonStyle(PressableStyle())
                                .onAppear { if i >= results.count - 4 { loadMore() } }
                        }
                    }
                    .padding(.horizontal, Theme.hPad)
                    PagingFooter(loading: !store.loadingMore.isEmpty, hasMore: pagingIDs.contains { store.canLoadMore($0) }) { loadMore() }
                }

                TabBarSpacer()
            }
        }
        .refreshable { await store.refreshAll(force: true) }
        .task { await store.refreshAll() }
    }

    /// Сайты, с которых догружаем страницы для текущего фильтра
    private var pagingIDs: [UUID] {
        if let sourceFilter { return [sourceFilter] }
        return store.enabledSources.filter { s in
            type == nil || s.category == type || store.items(of: s.id).contains { $0.type == type }
        }.map(\.id)
    }

    private func loadMore() {
        guard store.loadingMore.isEmpty else { return }
        let ids = pagingIDs
        Task { await store.loadMoreAll(ids) }
    }

    private var catalogHeader: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: URL(string: base.first?.imageURL ?? ""))
                .frame(height: 230).frame(maxWidth: .infinity)
                .opacity(0.45)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
            LinearGradient(colors: [Theme.accentDeep.opacity(0.35), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
            VStack(alignment: .leading, spacing: 4) {
                Text("Каталог").font(.system(size: 34, weight: .heavy)).foregroundStyle(.white)
                Text("\(store.allItems.count) тайтлов с \(store.enabledSources.count) сайтов 👀").font(.system(size: 15)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, Theme.hPad)
            .padding(.bottom, 6)
        }
        .frame(height: 230)
    }

    private var typeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                typeCard(nil, icon: "square.grid.2x2.fill", name: "Все", tint: Theme.accentSoft)
                ForEach(store.visibleTypes) { t in
                    typeCard(t, icon: t.icon, name: t.title, tint: t.tint)
                }
            }
            .padding(.horizontal, Theme.hPad)
            .padding(.vertical, 4)
        }
    }

    private func typeCard(_ t: ContentType?, icon: String, name: String, tint: Color) -> some View {
        let selected = type == t
        let count = store.allItems.filter { t == nil || $0.type == t }.count
        return Button {
            hapticTap()
            withAnimation(.easeOut(duration: 0.2)) { router.catalogType = t }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("(\(count.compactString))").font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            .frame(width: 86, height: 84)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? Theme.accentDeep.opacity(0.45) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.accent2 : Theme.stroke, lineWidth: selected ? 1.5 : 1))
            .shadow(color: selected ? Theme.accent.opacity(0.4) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Статус", selection: $statusFilter) {
                    ForEach(CatalogStatusFilter.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                pill(icon: "line.3.horizontal.decrease", text: statusFilter == .all ? "Фильтры" : statusFilter.title, active: statusFilter != .all)
            }
            Button { sortAZ.toggle() } label: {
                pill(icon: "arrow.up.arrow.down", text: sortAZ ? "По алфавиту" : "Как на сайтах", active: sortAZ)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                layoutButton(grid: true)
                layoutButton(grid: false)
            }
            .padding(3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Theme.stroke))
        }
        .padding(.horizontal, Theme.hPad)
    }

    private func pill(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Capsule().fill(active ? Theme.accentDeep.opacity(0.5) : Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(active ? Theme.accent : Theme.stroke))
    }

    private func layoutButton(grid: Bool) -> some View {
        Button { withAnimation { isGrid = grid } } label: {
            Image(systemName: grid ? "square.grid.2x2.fill" : "list.bullet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isGrid == grid ? Theme.accent2 : Theme.text2)
                .frame(width: 40, height: 32)
                .background(Capsule().fill(isGrid == grid ? Theme.accentDeep.opacity(0.45) : .clear))
        }
        .buttonStyle(.plain)
    }

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { sourceFilter = nil } label: {
                    Chip(title: "Все сайты", selected: sourceFilter == nil, showsCheck: true)
                }
                ForEach(store.enabledSources) { s in
                    Button { sourceFilter = sourceFilter == s.id ? nil : s.id } label: {
                        Chip(title: s.name, selected: sourceFilter == s.id)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.hPad)
        }
    }
}

struct SiteItemRow: View {
    @EnvironmentObject var store: LibraryStore
    var item: SiteItem

    var body: some View {
        let lib = store.title(forURL: item.url)
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    LinearGradient(colors: (item.type ?? .movie).gradient, startPoint: .top, endPoint: .bottom)
                    SiteThumb(item: item)
                }
                .frame(width: 92, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let t = item.type { TypeBadge(type: t).padding(5) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2)
                }
                if let s = store.source(item.sourceID) {
                    HStack(spacing: 6) {
                        SourceIcon(source: s, size: 18)
                        Text(s.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accentSoft)
                    }
                }
                if let lib, lib.status != .none {
                    Label(lib.status.title, systemImage: lib.status.icon)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(lib.status.color)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Theme.text3)
        }
        .padding(10)
        .glass(radius: 18)
    }
}

extension MediaTitle {
    /// Поиск по названию, оригинальному и альтернативным названиям
    func matches(_ q: String) -> Bool {
        let q = q.lowercased()
        if name.lowercased().contains(q) || originalName.lowercased().contains(q) { return true }
        return altNames.contains { $0.lowercased().contains(q) }
    }
}

// MARK: - Filtered list (Тренды, статусы и т.п.)

struct FilteredListView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @Environment(\.dismiss) var dismiss
    var title: String
    var filter: ListFilter

    private var items: [MediaTitle] {
        let all = store.visibleTitles
        switch filter {
        case .status(let s): return all.filter { $0.status == s }
        case .favorites: return all.filter(\.isFavorite)
        case .bookmarks: return all.filter(\.isBookmarked)
        case .type(let t): return all.filter { $0.type == t }
        case .trending: return all.sorted { ($0.rating + $0.popularity / 50) > ($1.rating + $1.popularity / 50) }
        case .recent: return all.sorted { $0.addedAt > $1.addedAt }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                NavBar(title: title)
                if items.isEmpty {
                    EmptyStateView(icon: "tray", title: "Пусто", subtitle: "Здесь пока ничего нет")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ForEach(items) { t in
                        Button { router.push(.title(t.id)) } label: { PosterCard(title: t) }
                            .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.hPad)
                TabBarSpacer()
            }
        }
        .background(AppBackground())
    }
}

/// Простая навигационная шапка для вложенных экранов
struct NavBar<Trailing: View>: View {
    @Environment(\.dismiss) var dismiss
    var title: String
    var trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            CircleIconButton(icon: "chevron.left") { dismiss() }
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white).lineLimit(1)
            Spacer()
            trailing
        }
        .padding(.horizontal, Theme.hPad)
        .padding(.top, 6)
    }
}

extension NavBar where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}
