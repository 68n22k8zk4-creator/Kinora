import SwiftUI

/// «Весь сайт»: полный список тайтлов из карты сайта и глубокого сканирования
struct SiteIndexSection: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @ObservedObject private var meta = MetaFetcher.shared
    let sourceID: UUID

    @State private var filter = ""
    @State private var limit = 60
    @State private var letter: String? = nil

    private var source: VideoSource? { store.source(sourceID) }

    private var entries: [IndexEntry] {
        let all = store.indexes[sourceID]?.entries ?? []
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { e in
            let title = displayTitle(e)
            if let letter, !title.uppercased().hasPrefix(letter) { return false }
            return q.isEmpty || title.lowercased().contains(q) || e.url.lowercased().contains(q)
        }
    }

    private var letters: [String] {
        let all = store.indexes[sourceID]?.entries ?? []
        let set = Set(all.compactMap { displayTitle($0).first.map { String($0).uppercased() } }.filter { $0.rangeOfCharacter(from: .letters) != nil })
        return set.sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    private func displayTitle(_ e: IndexEntry) -> String {
        if e.titleFromSlug, let t = meta.meta(e.url)?.title, !t.isEmpty { return t }
        return e.title
    }

    var body: some View {
        let list = entries
        VStack(alignment: .leading, spacing: 14) {
            statusCard

            if !(store.indexes[sourceID]?.entries.isEmpty ?? true) {
                SearchField(text: $filter, placeholder: "Найти среди \(store.indexCount(sourceID)) тайтлов…")
                    .padding(.horizontal, Theme.hPad)
                    .onChange(of: filter) { _ in limit = 60 }

                if letters.count > 3 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button { letter = nil; limit = 60 } label: { Chip(title: "Все", selected: letter == nil, compact: true) }
                            ForEach(letters, id: \.self) { l in
                                Button { letter = letter == l ? nil : l; limit = 60 } label: { Chip(title: l, selected: letter == l, compact: true) }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Theme.hPad)
                    }
                }

                Text("Показано \(min(limit, list.count)) из \(list.count)")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.horizontal, Theme.hPad)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ForEach(Array(list.prefix(limit).enumerated()), id: \.element.id) { i, e in
                        IndexCard(entry: e, sourceID: sourceID)
                            .onAppear { if i >= limit - 9 && limit < list.count { limit += 60 } }
                    }
                }
                .padding(.horizontal, Theme.hPad)
            }
        }
        .task {
            if store.indexes[sourceID] == nil && store.indexing[sourceID] == nil {
                await store.buildSitemapIndex(sourceID)
            }
        }
    }

    private var statusCard: some View {
        let idx = store.indexes[sourceID]
        let busy = store.indexing[sourceID]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 22)).foregroundStyle(Theme.accent2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(idx == nil ? "Полный список сайта" : "На сайте найдено: \(idx!.entries.count)")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    if let busy {
                        Text(busy).font(.system(size: 12)).foregroundStyle(Theme.accentSoft)
                    } else if let idx {
                        Text(methodText(idx)).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    } else {
                        Text("Собираю все тайтлы сайта…").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                }
                Spacer()
                if busy != nil { ProgressView().tint(Theme.accent2) }
            }
            HStack(spacing: 8) {
                SecondaryButton(title: "Карта сайта", icon: "map", height: 38) {
                    Task { await store.buildSitemapIndex(sourceID) }
                }
                .disabled(busy != nil)
                if store.isCrawling(sourceID) {
                    SecondaryButton(title: "Стоп", icon: "stop.fill", height: 38) { store.stopDeepCrawl(sourceID) }
                } else {
                    SecondaryButton(title: "Глубокий скан", icon: "magnifyingglass.circle", height: 38) {
                        store.startDeepCrawl(sourceID)
                    }
                    .disabled(busy != nil)
                }
            }
            Text("Карта сайта — служебный список всех страниц, обычно там ВСЕ тайтлы. Глубокий скан проходит разделы и страницы сайта сам (несколько минут, можно пользоваться приложением).")
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
        .padding(14)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }

    private func methodText(_ idx: SiteIndex) -> String {
        var parts: [String] = []
        if idx.method.contains("sitemap") { parts.append("карта сайта") }
        if idx.method.contains("crawl") { parts.append("скан \(idx.crawledPages) стр.") }
        let df = DateFormatter(); df.locale = Locale(identifier: "ru_RU"); df.dateFormat = "d MMM, HH:mm"
        return (parts.isEmpty ? "" : parts.joined(separator: " + ") + " • ") + "обновлено " + df.string(from: idx.updatedAt)
    }
}

/// Карточка из полного списка: название и постер уточняются со страницы, когда карточка появляется на экране
struct IndexCard: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @ObservedObject private var meta = MetaFetcher.shared
    let entry: IndexEntry
    let sourceID: UUID

    var body: some View {
        let item = store.siteItem(entry, sourceID: sourceID)
        Button { router.push(.item(item)) } label: { SiteItemCard(item: item, showsSource: false) }
            .buttonStyle(PressableStyle())
            .onAppear {
                if entry.image.isEmpty || entry.titleFromSlug {
                    meta.request(entry.url, referer: store.source(sourceID)?.baseURL)
                }
            }
    }
}
