import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, watched, watching, planned, dropped, favorites, bookmarks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Все"
        case .watched: return "Просмотрено"
        case .watching: return "Смотрю"
        case .planned: return "Не начинал"
        case .dropped: return "Заброшено"
        case .favorites: return "Избранное"
        case .bookmarks: return "Закладки"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .watched: return "checkmark"
        case .watching: return "play"
        case .planned: return "clock"
        case .dropped: return "nosign"
        case .favorites: return "heart"
        case .bookmarks: return "bookmark"
        }
    }
    func matches(_ t: MediaTitle) -> Bool {
        switch self {
        case .all: return t.status != .none || t.isFavorite || t.isBookmarked
        case .watched: return t.status == .watched
        case .watching: return t.status == .watching
        case .planned: return t.status == .planned
        case .dropped: return t.status == .dropped
        case .favorites: return t.isFavorite
        case .bookmarks: return t.isBookmarked
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @State private var filter: LibraryFilter = .all
    @State private var showNewCollection = false
    @State private var newCollectionName = ""

    private var items: [MediaTitle] { store.visibleTitles.filter { filter.matches($0) } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .top) {
                    HeroHeader(title: "Моя библиотека", subtitle: "Всё, что ты смотришь — в одном месте ✨",
                               art: store.continueWatching.first?.title ?? store.visibleTitles.first) { EmptyView() }
                    AppHeader(showsCrown: false, showsSearch: true).padding(.top, 6)
                }

                HStack(spacing: 8) {
                    StatTile(icon: "play.fill", iconColor: Theme.accent2, value: "\(store.statWatchedCount)", label: "Просмотрено")
                    StatTile(icon: "clock", iconColor: Theme.accentSoft, value: "\(TimeFmt.hours(store.statTotalSeconds)) ч", label: "Время просмотра")
                    StatTile(icon: "star.fill", iconColor: Theme.gold, value: store.statAverageRating > 0 ? String(format: "%.1f", store.statAverageRating) : "—", label: "Средний рейтинг")
                    StatTile(icon: "flame.fill", iconColor: .orange, value: TimeFmt.hours(store.statMonthSeconds), label: "Часов в этом месяце")
                }
                .padding(.horizontal, Theme.hPad)
                .onTapGesture { router.push(.stats) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LibraryFilter.allCases) { f in
                            Button { hapticTap(); withAnimation { filter = f } } label: {
                                Chip(title: f.title, icon: f.icon, selected: filter == f)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.hPad)
                    .padding(.vertical, 4)
                }

                if let first = store.continueWatching.first {
                    VStack(spacing: 12) {
                        SectionHeader(title: "Продолжить просмотр", action: "Все") { router.push(.history) }
                        ContinueCard(title: first.title, progress: first.progress, showsButton: true)
                            .padding(.horizontal, Theme.hPad)
                    }
                }

                tagsSection
                collectionsSection
                historySection

                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: filter == .all ? "В библиотеке" : filter.title)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                            ForEach(items) { t in
                                Button { router.push(.title(t.id)) } label: { PosterCard(title: t) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                        .padding(.horizontal, Theme.hPad)
                    }
                }

                quickLinks
                TabBarSpacer()
            }
        }
        .alert("Новая коллекция", isPresented: $showNewCollection) {
            TextField("Название", text: $newCollectionName)
            Button("Создать") {
                let n = newCollectionName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { store.addCollection(name: n, emoji: "📁") }
                newCollectionName = ""
            }
            Button("Отмена", role: .cancel) { newCollectionName = "" }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Мои теги", action: "Редактировать") { router.push(.tagsManager) }
            FlowLayout(spacing: 8) {
                ForEach(store.data.tags) { tag in
                    Button { router.push(.tag(tag.id)) } label: {
                        Chip(title: tag.name, emoji: tag.emoji, selected: false)
                            .overlay(Capsule().stroke(tag.color.opacity(0.6)))
                            .background(Capsule().fill(tag.color.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
                Button { router.push(.tagsManager) } label: { Chip(title: "", icon: "plus") }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.hPad)
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Мои коллекции", action: "Новая") { showNewCollection = true }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.data.collections) { c in
                        Button { router.push(.collection(c.id)) } label: { CollectionCard(collection: c) }
                            .buttonStyle(PressableStyle())
                    }
                    Button { showNewCollection = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.accent2)
                            Text("Создать").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            if !store.isPlus {
                                Text("\(store.data.collections.count)/\(FreeLimits.collections)").font(.system(size: 11)).foregroundStyle(Theme.text3)
                            }
                        }
                        .frame(width: 140, height: 170)
                        .glass(radius: 18)
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, Theme.hPad)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "История просмотров", action: "Вся история") { router.push(.history) }
            if store.data.history.isEmpty {
                Text("Пока пусто").font(.system(size: 14)).foregroundStyle(Theme.text3).padding(.horizontal, Theme.hPad)
            }
            VStack(spacing: 8) {
                ForEach(store.data.history.prefix(3)) { h in
                    HistoryRow(entry: h)
                }
            }
            .padding(.horizontal, Theme.hPad)
        }
    }

    private var quickLinks: some View {
        VStack(spacing: 8) {
            linkRow("link", "Мои источники", "\(store.data.sources.count) сайтов подключено") { router.push(.sources) }
            linkRow("chart.bar.fill", "Статистика", store.isPlus ? "Расширенная аналитика" : "Базовая • расширенная в Plus") { router.push(.stats) }
            linkRow("arrow.down.circle", "Загрузки", "\(store.data.downloads.count) файлов") { router.push(.downloads) }
        }
        .padding(.horizontal, Theme.hPad)
    }

    private func linkRow(_ icon: String, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.accent2).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Text(sub).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.text3)
            }
            .padding(14)
            .glass(radius: 16)
        }
        .buttonStyle(PressableStyle())
    }
}

struct CollectionCard: View {
    @EnvironmentObject var store: LibraryStore
    var collection: UserCollection

    var body: some View {
        let cover = collection.titleIDs.compactMap { store.title($0) }.first
        ZStack(alignment: .bottomLeading) {
            if let cover {
                PosterView(title: cover, showTitleOnPlaceholder: false)
            } else {
                LinearGradient(colors: [Theme.accentDeep, Theme.bg2], startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(collection.emoji) \(collection.name)").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text("\(collection.titleIDs.count) элементов").font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            .padding(10)
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 10))
                        Text("\(collection.titleIDs.count)").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 7).frame(height: 22)
                    .background(Capsule().fill(.black.opacity(0.55)))
                }
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 140, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke))
    }
}

struct HistoryRow: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    var entry: HistoryEntry

    var body: some View {
        if let t = store.title(entry.titleID) {
            HStack(spacing: 12) {
                PosterView(title: t, useBackdrop: true, showTitleOnPlaceholder: false)
                    .frame(width: 84, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text((t.isEpisodic ? "Сезон \(entry.season) • Серия \(entry.episode) • " : "") + "\(Int(entry.fraction * 100))%")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Spacer()
                Text(TimeFmt.relative(entry.date)).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                Button {
                    Watch.start(t, season: t.isEpisodic ? entry.season : nil, episode: t.isEpisodic ? entry.episode : nil,
                                store: store, router: router, player: player)
                } label: {
                    Image(systemName: entry.fraction >= 0.92 ? "checkmark" : "play.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(entry.fraction >= 0.92 ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.accentGradient)))
                        .overlay(Circle().stroke(entry.fraction >= 0.92 ? Theme.accent2 : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                Menu {
                    Button("Открыть страницу") { router.push(.title(t.id)) }
                    Button("Удалить из истории", role: .destructive) { store.data.history.removeAll { $0.id == entry.id } }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.text2).frame(width: 24, height: 34)
                }
            }
            .padding(8)
            .glass(radius: 16)
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var confirmClear = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                NavBar(title: "История") {
                    Button("Очистить") { confirmClear = true }.foregroundStyle(Theme.accent2)
                }
                if !store.continueWatching.isEmpty {
                    Text("Продолжить").font(.system(size: 18, weight: .bold)).foregroundStyle(.white).padding(.horizontal, Theme.hPad)
                    ForEach(Array(store.continueWatching.enumerated()), id: \.offset) { _, item in
                        ContinueCard(title: item.title, progress: item.progress).padding(.horizontal, Theme.hPad)
                    }
                }
                Text("Все просмотры").font(.system(size: 18, weight: .bold)).foregroundStyle(.white).padding(.horizontal, Theme.hPad)
                LazyVStack(spacing: 8) {
                    ForEach(store.data.history) { HistoryRow(entry: $0) }
                }
                .padding(.horizontal, Theme.hPad)
                TabBarSpacer()
            }
        }
        .background(AppBackground())
        .confirmationDialog("Очистить историю просмотров?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) { store.data.history.removeAll() }
        }
    }
}

// MARK: - Tags manager

struct TagsManagerView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @State private var showNew = false
    @State private var editing: UserTag? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                NavBar(title: "Мои теги") {
                    CircleIconButton(icon: "plus", filled: true) { showNew = true }
                }
                if !store.isPlus {
                    Text("Бесплатно: \(store.data.tags.count) из \(FreeLimits.tags) тегов. В Plus — без ограничений.")
                        .font(.system(size: 13)).foregroundStyle(Theme.text2).padding(.horizontal, Theme.hPad)
                }
                ForEach(store.data.tags) { tag in
                    let count = store.data.titles.filter { $0.tagIDs.contains(tag.id) }.count
                    HStack(spacing: 12) {
                        Text(tag.emoji.isEmpty ? "🏷️" : tag.emoji).font(.system(size: 22))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(tag.color.opacity(0.25)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            Text("\(count) тайтлов").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Button { editing = tag } label: { Image(systemName: "pencil").foregroundStyle(.white) }
                            .buttonStyle(.plain).padding(.horizontal, 6)
                        Button { store.deleteTag(tag.id) } label: { Image(systemName: "trash").foregroundStyle(Theme.red) }
                            .buttonStyle(.plain)
                    }
                    .padding(12)
                    .glass(radius: 16)
                    .padding(.horizontal, Theme.hPad)
                    .onTapGesture { router.push(.tag(tag.id)) }
                }
                TabBarSpacer()
            }
        }
        .background(AppBackground())
        .sheet(isPresented: $showNew) { NewTagSheet().environmentObject(store) }
        .sheet(item: $editing) { tag in NewTagSheet(editing: tag).environmentObject(store) }
    }
}

struct TagDetailView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    let tagID: UUID

    var body: some View {
        let tag = store.tag(tagID)
        let items = store.visibleTitles.filter { $0.tagIDs.contains(tagID) }
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                NavBar(title: "\(tag?.emoji ?? "") \(tag?.name ?? "Тег")")
                if items.isEmpty {
                    EmptyStateView(icon: "tag", title: "Нет тайтлов", subtitle: "Добавьте тег на странице тайтла")
                }
                ForEach(items) { t in
                    HStack(spacing: 12) {
                        PosterView(title: t).frame(width: 54, height: 78).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            Text(t.type.singular).font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Menu {
                            ForEach(store.data.tags.filter { $0.id != tagID }) { other in
                                Button("\(other.emoji) \(other.name)") { store.moveTitle(t.id, fromTag: tagID, toTag: other.id) }
                            }
                            Divider()
                            Button("Убрать тег", role: .destructive) { store.toggleTag(tagID, on: t.id) }
                        } label: {
                            Label("Перенести", systemImage: "arrow.right.arrow.left")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(height: 34)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                    .padding(10)
                    .glass(radius: 16)
                    .padding(.horizontal, Theme.hPad)
                    .onTapGesture { router.push(.title(t.id)) }
                }
                TabBarSpacer()
            }
        }
        .background(AppBackground())
    }
}

// MARK: - Collection detail

struct CollectionDetailView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @Environment(\.dismiss) var dismiss
    let collectionID: UUID
    @State private var showPicker = false
    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let c = store.data.collections.first { $0.id == collectionID }
        let items = (c?.titleIDs ?? []).compactMap { store.title($0) }
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                NavBar(title: "\(c?.emoji ?? "") \(c?.name ?? "")") {
                    Menu {
                        Button { showPicker = true } label: { Label("Добавить тайтлы", systemImage: "plus") }
                        Button { newName = c?.name ?? ""; renaming = true } label: { Label("Переименовать", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить коллекцию", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                }
                if items.isEmpty {
                    EmptyStateView(icon: "folder", title: "Коллекция пуста", subtitle: "Нажмите «…» → «Добавить тайтлы»")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ForEach(items) { t in
                        Button { router.push(.title(t.id)) } label: { PosterCard(title: t) }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button("Убрать из коллекции", role: .destructive) { store.toggle(t.id, inCollection: collectionID) }
                            }
                    }
                }
                .padding(.horizontal, Theme.hPad)
                TabBarSpacer()
            }
        }
        .background(AppBackground())
        .sheet(isPresented: $showPicker) { TitleMultiPicker(collectionID: collectionID).environmentObject(store) }
        .confirmationDialog("Удалить коллекцию?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                store.data.collections.removeAll { $0.id == collectionID }
                dismiss()
            }
        }
        .alert("Название", isPresented: $renaming) {
            TextField("Название", text: $newName)
            Button("Сохранить") {
                if let i = store.data.collections.firstIndex(where: { $0.id == collectionID }) { store.data.collections[i].name = newName }
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct TitleMultiPicker: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let collectionID: UUID
    @State private var q = ""

    var body: some View {
        let c = store.data.collections.first { $0.id == collectionID }
        NavigationStack {
            List {
                ForEach(store.visibleTitles.filter { q.isEmpty || $0.matches(q) }) { t in
                    Button { store.toggle(t.id, inCollection: collectionID) } label: {
                        HStack {
                            PosterView(title: t, showTitleOnPlaceholder: false).frame(width: 36, height: 52).clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(t.name).foregroundStyle(.white)
                            Spacer()
                            if c?.titleIDs.contains(t.id) == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent2) }
                        }
                    }
                }
            }
            .searchable(text: $q)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Добавить в коллекцию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
