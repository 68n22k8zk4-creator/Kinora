import Foundation
import SwiftUI
import Combine

struct StatusSuggestion: Identifiable {
    let id = UUID()
    let titleID: UUID
    let titleName: String
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var data: AppData {
        didSet { scheduleSave() }
    }
    @Published var toast: String? = nil
    /// Источники, которые сейчас обновляются
    @Published var refreshing: Set<UUID> = []
    /// Полные списки тайтлов сайтов (хранятся отдельными файлами)
    @Published var indexes: [UUID: SiteIndex] = [:]
    /// Что сейчас происходит с полным списком сайта (текст статуса)
    @Published var indexing: [UUID: String] = [:]
    private var crawlTasks: [UUID: Task<Void, Never>] = [:]
    @Published var statusSuggestion: StatusSuggestion? = nil

    private var saveWorkItem: DispatchWorkItem?

    nonisolated static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("kinora_data_v2.json")
    }()

    init() {
        if let raw = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder.kinora.decode(AppData.self, from: raw) {
            data = decoded
        } else {
            // Если файл есть, но не читается — сохраняем копию, чтобы не потерять данные
            if FileManager.default.fileExists(atPath: Self.fileURL.path) {
                let backup = Self.fileURL.deletingLastPathComponent().appendingPathComponent("kinora_data_broken_\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: Self.fileURL, to: backup)
            }
            data = Self.migrateFromV1() ?? SeedData.make()
        }
        for src in data.sources {
            if let raw = try? Data(contentsOf: Self.indexURL(src.id)),
               let idx = try? JSONDecoder.kinora.decode(SiteIndex.self, from: raw) {
                indexes[src.id] = idx
            }
        }
    }

    /// Перенос из версии 1: сохраняем добавленные сайты, теги и настройки,
    /// а демо-тайтлы, демо-прогресс и историю выбрасываем.
    private static func migrateFromV1() -> AppData? {
        let old = fileURL.deletingLastPathComponent().appendingPathComponent("kinora_data.json")
        guard let raw = try? Data(contentsOf: old),
              let v1 = try? JSONDecoder.kinora.decode(AppData.self, from: raw) else { return nil }
        var d = SeedData.make()
        d.sources = v1.sources.map { s in
            var s = s
            s.health = .unknown
            if let host = URL(string: s.baseURL)?.host, s.category == nil {
                s.category = SiteScraper.guessCategory(host: host, name: s.name)
            }
            return s
        }
        d.settings = v1.settings
        d.profile = v1.profile
        d.searchHistory = v1.searchHistory
        try? FileManager.default.removeItem(at: old)
        return d
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = data
        let url = Self.fileURL
        let item = DispatchWorkItem {
            DispatchQueue.global(qos: .utility).async {
                if let raw = try? JSONEncoder.kinora.encode(snapshot) {
                    try? raw.write(to: url, options: .atomic)
                }
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        if let raw = try? JSONEncoder.kinora.encode(data) {
            try? raw.write(to: Self.fileURL, options: .atomic)
        }
    }

    func exportBackup() -> URL? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KINORA_backup_\(df.string(from: Date())).json")
        guard let raw = try? JSONEncoder.kinora.encode(data) else { return nil }
        try? raw.write(to: url, options: .atomic)
        return url
    }

    func importBackup(from url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.kinora.decode(AppData.self, from: raw) else { return false }
        data = decoded
        return true
    }

    func resetAll() {
        data = SeedData.make()
    }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    // MARK: Titles

    var isPlus: Bool { data.profile.isPlus }

    var visibleTitles: [MediaTitle] {
        data.titles.filter { !$0.type.isAdult || data.settings.adultEnabled }
    }

    var visibleTypes: [ContentType] {
        ContentType.allCases.filter { !$0.isAdult || data.settings.adultEnabled }
    }

    func title(_ id: UUID) -> MediaTitle? { data.titles.first { $0.id == id } }

    func binding(for id: UUID) -> Binding<MediaTitle>? {
        guard data.titles.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.data.titles.first { $0.id == id } ?? MediaTitle(name: "", type: .movie) },
            set: { newValue in
                if let i = self.data.titles.firstIndex(where: { $0.id == id }) { self.data.titles[i] = newValue }
            })
    }

    func update(_ id: UUID, _ change: (inout MediaTitle) -> Void) {
        guard let i = data.titles.firstIndex(where: { $0.id == id }) else { return }
        change(&data.titles[i])
    }

    func upsert(_ title: MediaTitle) {
        if let i = data.titles.firstIndex(where: { $0.id == title.id }) {
            data.titles[i] = title
        } else if let tmdb = title.tmdbID, let i = data.titles.firstIndex(where: { $0.tmdbID == tmdb && $0.type == title.type }) {
            var merged = title
            merged.id = data.titles[i].id
            merged.status = data.titles[i].status
            merged.tagIDs = data.titles[i].tagIDs
            merged.isBookmarked = data.titles[i].isBookmarked
            merged.isFavorite = data.titles[i].isFavorite
            merged.sourceLinks = data.titles[i].sourceLinks
            if merged.seasons.isEmpty { merged.seasons = data.titles[i].seasons }
            data.titles[i] = merged
        } else {
            data.titles.append(title)
        }
    }

    func delete(_ id: UUID) {
        data.titles.removeAll { $0.id == id }
        data.progress = data.progress.filter { $0.value.titleID != id }
        data.history.removeAll { $0.titleID == id }
        for i in data.collections.indices { data.collections[i].titleIDs.removeAll { $0 == id } }
    }

    func toggleBookmark(_ id: UUID) {
        update(id) { $0.isBookmarked.toggle() }
        if let t = title(id) { showToast(t.isBookmarked ? "Добавлено в закладки" : "Убрано из закладок") }
    }

    func toggleFavorite(_ id: UUID) {
        update(id) { $0.isFavorite.toggle() }
    }

    func setStatus(_ id: UUID, _ status: WatchStatus) {
        update(id) { $0.status = status }
    }

    // MARK: Progress

    func progress(_ titleID: UUID, season: Int, episode: Int) -> WatchProgress? {
        data.progress[ProgressKey(titleID: titleID, season: season, episode: episode).string]
    }

    /// Последняя (по времени) позиция для тайтла
    func lastProgress(for titleID: UUID) -> WatchProgress? {
        data.progress.values.filter { $0.titleID == titleID }.max { $0.updatedAt < $1.updatedAt }
    }

    /// Куда продолжать: если последняя серия досмотрена — следующая серия с нуля
    func resumePoint(for t: MediaTitle) -> (season: Int, episode: Int, position: Double) {
        guard let last = lastProgress(for: t.id) else {
            if let s = t.seasons.first, let e = s.episodes.first { return (s.number, e.number, 0) }
            return (0, 0, 0)
        }
        if last.isFinished, let next = nextEpisode(in: t, season: last.season, episode: last.episode) {
            return (next.season, next.episode, progress(t.id, season: next.season, episode: next.episode)?.position ?? 0)
        }
        return (last.season, last.episode, last.isFinished ? 0 : last.position)
    }

    func nextEpisode(in t: MediaTitle, season: Int, episode: Int) -> (season: Int, episode: Int)? {
        guard let sIndex = t.seasons.firstIndex(where: { $0.number == season }) else { return nil }
        let s = t.seasons[sIndex]
        if let eIndex = s.episodes.firstIndex(where: { $0.number == episode }), eIndex + 1 < s.episodes.count {
            return (season, s.episodes[eIndex + 1].number)
        }
        if sIndex + 1 < t.seasons.count, let first = t.seasons[sIndex + 1].episodes.first {
            return (t.seasons[sIndex + 1].number, first.number)
        }
        return nil
    }

    func isLastEpisode(_ t: MediaTitle, season: Int, episode: Int) -> Bool {
        if !t.isEpisodic { return true }
        return nextEpisode(in: t, season: season, episode: episode) == nil
    }

    func saveProgress(titleID: UUID, season: Int, episode: Int, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, duration > 0 else { return }
        let key = ProgressKey(titleID: titleID, season: season, episode: episode).string
        let previous = data.progress[key]
        let newP = WatchProgress(titleID: titleID, season: season, episode: episode,
                                 position: position, duration: duration, updatedAt: Date())
        data.progress[key] = newP

        // Учёт реально просмотренного времени (без скачков перемотки)
        var delta: Double = 0
        if let previous {
            let d = position - previous.position
            if d > 0 && d < 30 { delta = d }
        }

        // История: обновляем последнюю запись того же эпизода, если она «свежая»
        if let i = data.history.firstIndex(where: { $0.titleID == titleID && $0.season == season && $0.episode == episode }),
           Date().timeIntervalSince(data.history[i].date) < 6 * 3600 {
            data.history[i].fraction = newP.fraction
            data.history[i].watchedSeconds += delta
            data.history[i].date = Date()
            let entry = data.history.remove(at: i)
            data.history.insert(entry, at: 0)
        } else {
            data.history.insert(HistoryEntry(titleID: titleID, season: season, episode: episode,
                                             fraction: newP.fraction, watchedSeconds: delta), at: 0)
            if data.history.count > 500 { data.history.removeLast(data.history.count - 500) }
        }

        guard let t = title(titleID) else { return }
        if t.status == .none || t.status == .planned {
            update(titleID) { $0.status = .watching }
        }
        // Авто-определение статуса: досмотрел последнюю серию → предложить «Просмотрено»
        if newP.isFinished, !(previous?.isFinished ?? false), t.status != .watched,
           isLastEpisode(t, season: season, episode: episode) {
            statusSuggestion = StatusSuggestion(titleID: titleID, titleName: t.name)
        }
    }

    func resetProgress(for titleID: UUID) {
        data.progress = data.progress.filter { $0.value.titleID != titleID }
    }

    func watchedEpisodesCount(_ t: MediaTitle) -> Int {
        data.progress.values.filter { $0.titleID == t.id && $0.isFinished }.count
    }

    var continueWatching: [(title: MediaTitle, progress: WatchProgress)] {
        var seen = Set<UUID>()
        var result: [(title: MediaTitle, progress: WatchProgress)] = []
        for p in data.progress.values.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard !seen.contains(p.titleID), let t = title(p.titleID) else { continue }
            seen.insert(p.titleID)
            if t.type.isAdult && !data.settings.adultEnabled { continue }
            if t.status == .watched || t.status == .dropped { continue }
            if p.isFinished && isLastEpisode(t, season: p.season, episode: p.episode) { continue }
            result.append((title: t, progress: p))
        }
        return result
    }

    // MARK: Stats

    var statWatchedCount: Int { data.titles.filter { $0.status == .watched }.count }
    var statTotalSeconds: Double { data.history.reduce(0) { $0 + $1.watchedSeconds } }
    var statMonthSeconds: Double {
        let cal = Calendar.current
        return data.history.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.watchedSeconds }
    }
    var statAverageRating: Double {
        let rated = data.titles.compactMap { $0.userRating ?? ($0.status == .watched && $0.rating > 0 ? $0.rating : nil) }
        guard !rated.isEmpty else { return 0 }
        return rated.reduce(0, +) / Double(rated.count)
    }
    var statActiveDays: Int {
        let cal = Calendar.current
        return Set(data.history.map { cal.startOfDay(for: $0.date) }).count
    }
    var statTitlesInLibrary: Int {
        data.titles.filter { $0.status != .none || $0.isBookmarked || $0.isFavorite }.count
    }

    func statByType() -> [(ContentType, Int)] {
        visibleTypes.map { type in (type, data.titles.filter { $0.type == type && $0.status == .watched }.count) }
    }

    /// Секунды по дням за последние 7 дней
    func weeklyActivity() -> [(Date, Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let sum = data.history.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.watchedSeconds }
            return (day, sum)
        }
    }

    // MARK: Tags

    func tag(_ id: UUID) -> UserTag? { data.tags.first { $0.id == id } }

    @discardableResult
    func addTag(name: String, emoji: String, colorHex: UInt32) -> Bool {
        if !isPlus && data.tags.count >= FreeLimits.tags {
            showToast("Лимит \(FreeLimits.tags) тегов — безлимит в KINORA Plus")
            return false
        }
        data.tags.append(UserTag(name: name, emoji: emoji, colorHex: colorHex))
        return true
    }

    func deleteTag(_ id: UUID) {
        data.tags.removeAll { $0.id == id }
        for i in data.titles.indices { data.titles[i].tagIDs.removeAll { $0 == id } }
    }

    func toggleTag(_ tagID: UUID, on titleID: UUID) {
        update(titleID) { t in
            if t.tagIDs.contains(tagID) { t.tagIDs.removeAll { $0 == tagID } } else { t.tagIDs.append(tagID) }
        }
    }

    /// Перенос тайтла из одного тега в другой
    func moveTitle(_ titleID: UUID, fromTag: UUID, toTag: UUID) {
        update(titleID) { t in
            t.tagIDs.removeAll { $0 == fromTag }
            if !t.tagIDs.contains(toTag) { t.tagIDs.append(toTag) }
        }
    }

    // MARK: Collections

    @discardableResult
    func addCollection(name: String, emoji: String) -> Bool {
        if !isPlus && data.collections.count >= FreeLimits.collections {
            showToast("Лимит \(FreeLimits.collections) коллекций — безлимит в KINORA Plus")
            return false
        }
        data.collections.append(UserCollection(name: name, emoji: emoji))
        return true
    }

    func toggle(_ titleID: UUID, inCollection cID: UUID) {
        guard let i = data.collections.firstIndex(where: { $0.id == cID }) else { return }
        if data.collections[i].titleIDs.contains(titleID) {
            data.collections[i].titleIDs.removeAll { $0 == titleID }
        } else {
            data.collections[i].titleIDs.append(titleID)
        }
    }

    // MARK: Sources

    var sortedSources: [VideoSource] { data.sources.sorted { $0.order < $1.order } }
    var enabledSources: [VideoSource] { sortedSources.filter { $0.isEnabled && ($0.category?.isAdult != true || data.settings.adultEnabled) } }

    @discardableResult
    func addSource(_ s: VideoSource) -> Bool {
        if !isPlus && data.sources.count >= FreeLimits.sources {
            showToast("Лимит \(FreeLimits.sources) источников — безлимит в KINORA Plus")
            return false
        }
        var s = s
        s.order = (data.sources.map(\.order).max() ?? -1) + 1
        data.sources.append(s)
        return true
    }

    func updateSource(_ s: VideoSource) {
        if let i = data.sources.firstIndex(where: { $0.id == s.id }) { data.sources[i] = s }
    }

    func deleteSource(_ id: UUID) {
        data.sources.removeAll { $0.id == id }
        data.feeds.removeValue(forKey: id.uuidString)
        crawlTasks[id]?.cancel()
        indexes[id] = nil
        try? FileManager.default.removeItem(at: Self.indexURL(id))
        for i in data.titles.indices { data.titles[i].sourceLinks.removeValue(forKey: id.uuidString) }
    }

    func moveSources(from: IndexSet, to: Int) {
        var list = sortedSources
        list.move(fromOffsets: from, toOffset: to)
        for (i, s) in list.enumerated() {
            if let idx = data.sources.firstIndex(where: { $0.id == s.id }) { data.sources[idx].order = i }
        }
    }

    func source(_ id: UUID) -> VideoSource? { data.sources.first { $0.id == id } }

    /// Проверка доступности сайта
    func checkHealth(_ id: UUID) async {
        guard let s = source(id), let url = URL(string: s.baseURL) else { return }
        setHealth(id, .checking)
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "GET"
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            setHealth(id, (200..<400).contains(code) ? .online : .offline)
        } catch {
            setHealth(id, .offline)
        }
    }

    func checkAllSources() async {
        for s in data.sources where s.isEnabled { await checkHealth(s.id) }
    }

    func setHealth(_ id: UUID, _ h: SourceHealth) {
        if let i = data.sources.firstIndex(where: { $0.id == id }) {
            data.sources[i].health = h
            data.sources[i].lastChecked = Date()
        }
    }

    /// Лучший URL для просмотра тайтла на источнике: прямая ссылка или поиск
    func watchURL(for t: MediaTitle, on s: VideoSource) -> URL? {
        if let link = t.sourceLinks[s.id.uuidString], let url = URL(string: link) { return url }
        return s.searchURL(for: t.name)
    }

    /// Альтернативные источники, если текущий не работает
    func alternativeSources(excluding id: UUID) -> [VideoSource] {
        enabledSources.filter { $0.id != id && $0.health != .offline }
    }

    // MARK: Контент с сайтов

    func feed(_ sourceID: UUID) -> SourceFeed? { data.feeds[sourceID.uuidString] }

    func items(of sourceID: UUID) -> [SiteItem] { feed(sourceID)?.items ?? [] }

    /// Все карточки со всех включённых сайтов (без дублей)
    var allItems: [SiteItem] {
        var seen = Set<String>()
        var out: [SiteItem] = []
        for s in enabledSources {
            for it in items(of: s.id) where !seen.contains(it.url) {
                if it.type?.isAdult == true && !data.settings.adultEnabled { continue }
                seen.insert(it.url)
                out.append(it)
            }
        }
        return out
    }

    var isRefreshingAny: Bool { !refreshing.isEmpty }

    /// Перечитать главную страницу сайта и обновить ленту
    func refreshFeed(_ sourceID: UUID) async {
        guard let s = source(sourceID), let url = URL(string: s.baseURL), !refreshing.contains(sourceID) else { return }
        refreshing.insert(sourceID)
        setHealth(sourceID, .checking)
        let r = await SiteScraper.scrape(url, sourceID: sourceID, category: s.category)
        refreshing.remove(sourceID)
        var f = feed(sourceID) ?? SourceFeed()
        if !r.items.isEmpty {
            f.items = r.items
            f.updatedAt = Date()
            f.error = nil
            f.nextURL = r.nextURL == url.absoluteString ? "" : r.nextURL
            if !r.categories.isEmpty { f.categories = r.categories }
        } else {
            f.error = r.blocked ? "Сайт просит проверку «я не робот». Откройте его один раз во встроенном браузере."
                                : "Не удалось найти тайтлы на главной странице"
        }
        data.feeds[sourceID.uuidString] = f
        setHealth(sourceID, r.items.isEmpty && !r.blocked && r.siteName.isEmpty ? .offline : .online)
        if let i = data.sources.firstIndex(where: { $0.id == sourceID }) {
            if data.sources[i].searchTemplate.isEmpty && !r.searchTemplate.isEmpty {
                data.sources[i].searchTemplate = r.searchTemplate
            }
            if data.sources[i].category == nil {
                data.sources[i].category = SiteScraper.guessCategory(host: data.sources[i].host, name: r.siteName)
            }
        }
    }

    /// Добавить сайт по адресу и сразу просканировать его
    @discardableResult
    func addSite(_ text: String) async -> Bool {
        var str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return false }
        if !str.lowercased().hasPrefix("http") { str = "https://" + str }
        guard let url = URL(string: str), let host = url.host else {
            showToast("Некорректный адрес сайта")
            return false
        }
        if data.sources.contains(where: { $0.host.replacingOccurrences(of: "www.", with: "") == host.replacingOccurrences(of: "www.", with: "") }) {
            showToast("Этот сайт уже добавлен")
            return false
        }
        let name = host.replacingOccurrences(of: "www.", with: "").components(separatedBy: ".").first?.capitalized ?? host
        let src = VideoSource(name: name, baseURL: "\(url.scheme ?? "https")://\(host)",
                              category: SiteScraper.guessCategory(host: host, name: ""))
        guard addSource(src) else { return false }
        showToast("Сканирую \(name)…")
        await refreshFeed(src.id)
        // Параллельно собираем полный список тайтлов сайта
        Task { await self.buildSitemapIndex(src.id) }
        let count = items(of: src.id).count
        showToast(count > 0 ? "\(name): найдено \(count) тайтлов" : "\(name) добавлен. Тайтлы не найдены — откройте сайт")
        return true
    }

    /// Сайты, у которых сейчас грузится следующая страница
    @Published var loadingMore: Set<UUID> = []

    func canLoadMore(_ sourceID: UUID) -> Bool { !(feed(sourceID)?.nextURL.isEmpty ?? true) }

    /// Догрузить следующую страницу ленты сайта (бесконечная прокрутка)
    func loadMore(_ sourceID: UUID) async {
        guard let s = source(sourceID), let next = feed(sourceID)?.nextURL, !next.isEmpty,
              let url = URL(string: next), !loadingMore.contains(sourceID) else { return }
        loadingMore.insert(sourceID)
        let r = await SiteScraper.scrape(url, sourceID: sourceID, category: s.category)
        loadingMore.remove(sourceID)
        var f = feed(sourceID) ?? SourceFeed()
        let known = Set(f.items.map(\.url))
        let fresh = r.items.filter { !known.contains($0.url) }
        f.items.append(contentsOf: fresh)
        f.nextURL = (fresh.isEmpty || r.nextURL == next) ? "" : r.nextURL
        data.feeds[sourceID.uuidString] = f
    }

    /// Догрузить по странице со всех подходящих сайтов (для общего каталога)
    func loadMoreAll(_ ids: [UUID]) async {
        let ready = ids.filter { canLoadMore($0) }
        await withTaskGroup(of: Void.self) { group in
            for id in ready { group.addTask { await self.loadMore(id) } }
        }
    }

    /// Собрать полные списки для сайтов, у которых их ещё нет (по одному, в фоне)
    func buildMissingIndexes() async {
        for s in enabledSources where indexes[s.id] == nil && indexing[s.id] == nil {
            await buildSitemapIndex(s.id)
        }
    }

    func refreshAll(force: Bool = false) async {
        let ids = enabledSources.filter { force || (feed($0.id)?.updatedAt ?? .distantPast) < Date().addingTimeInterval(-3600) }.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in ids { group.addTask { await self.refreshFeed(id) } }
        }
    }

    /// Поиск по одному сайту
    func searchSite(_ s: VideoSource, query: String) async -> [SiteItem] {
        guard !s.searchTemplate.isEmpty, let url = s.searchURL(for: query) else {
            // Нет поиска на сайте — ищем в уже загруженной ленте
            let q = query.lowercased()
            let feedHits = items(of: s.id).filter { $0.title.lowercased().contains(q) }
            let known = Set(feedHits.map(\.url))
            let idxHits = (indexes[s.id]?.entries ?? []).map { siteItem($0, sourceID: s.id) }
                .filter { !known.contains($0.url) && $0.title.lowercased().contains(q) }
            return feedHits + idxHits.prefix(60)
        }
        let r = await SiteScraper.scrape(url, sourceID: s.id, category: s.category)
        let q = query.lowercased()
        // Сначала самые похожие по названию
        var list = r.items.sorted { a, b in
            let ah = a.title.lowercased().contains(q), bh = b.title.lowercased().contains(q)
            return ah && !bh
        }
        // Плюс совпадения из полного списка сайта
        let known = Set(list.map(\.url))
        let extra = (indexes[s.id]?.entries ?? []).lazy
            .map { self.siteItem($0, sourceID: s.id) }
            .filter { !known.contains($0.url) && $0.title.lowercased().contains(q) }
            .prefix(40)
        list.append(contentsOf: extra)
        return list
    }

    func title(forURL url: String) -> MediaTitle? { data.titles.first { $0.originURL == url } }

    /// Превращает карточку сайта в тайтл библиотеки (нужно для прогресса, тегов, закладок)
    @discardableResult
    func ensureTitle(for item: SiteItem) -> MediaTitle {
        if let t = title(forURL: item.url) { return t }
        let src = source(item.sourceID)
        var t = MediaTitle(name: item.title, type: item.type ?? src?.category ?? .movie)
        t.posterURL = item.imageURL
        t.originURL = item.url
        t.originSourceID = item.sourceID
        t.sourceLinks[item.sourceID.uuidString] = item.url
        let yearText = item.subtitle.range(of: "(19|20)\\d{2}", options: .regularExpression).map({ String(item.subtitle[$0]) }) ?? ""
        if let y = Int(yearText) { t.year = y }
        data.titles.append(t)
        return t
    }

    /// Дополнить тайтл данными со страницы (описание, постер)
    func enrich(_ titleID: UUID, with r: ScrapeResult) {
        update(titleID) { t in
            if t.overview.isEmpty, !r.description.isEmpty { t.overview = r.description }
            if t.backdropURL.isEmpty, !r.image.isEmpty { t.backdropURL = r.image }
            if t.posterURL.isEmpty, !r.image.isEmpty { t.posterURL = r.image }
        }
    }

    // MARK: Весь сайт (карта сайта + глубокое сканирование)

    nonisolated static func indexURL(_ id: UUID) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("index_\(id.uuidString).json")
    }

    func indexCount(_ id: UUID) -> Int { indexes[id]?.entries.count ?? 0 }
    func isCrawling(_ id: UUID) -> Bool { crawlTasks[id] != nil }

    private func saveIndex(_ id: UUID) {
        guard let idx = indexes[id] else { return }
        let url = Self.indexURL(id)
        DispatchQueue.global(qos: .utility).async {
            if let raw = try? JSONEncoder().encodeKinoraCompact(idx) { try? raw.write(to: url, options: .atomic) }
        }
    }

    private func mergeIndex(_ id: UUID, _ found: [IndexEntry], method: String) {
        var idx = indexes[id] ?? SiteIndex()
        var map = Dictionary(idx.entries.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
        for e in found {
            if var old = map[e.url] {
                if old.image.isEmpty { old.image = e.image }
                if old.titleFromSlug && !e.titleFromSlug { old.title = e.title; old.titleFromSlug = false }
                map[e.url] = old
            } else {
                map[e.url] = e
            }
        }
        idx.entries = map.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        idx.updatedAt = Date()
        if !idx.method.contains(method) { idx.method = idx.method.isEmpty ? method : idx.method + "+" + method }
        indexes[id] = idx
    }

    /// Шаг 1: карта сайта (быстро, обычно даёт ВСЕ тайтлы)
    func buildSitemapIndex(_ id: UUID) async {
        guard let s = source(id), let base = URL(string: s.baseURL), indexing[id] == nil else { return }
        indexing[id] = "Читаю карту сайта…"
        let sample = items(of: id).map(\.url)
        let found = await SitemapService.build(base: base, sample: sample) { n in
            Task { @MainActor in self.indexing[id] = "Карта сайта: найдено \(n)…" }
        }
        mergeIndex(id, found, method: "sitemap")
        saveIndex(id)
        indexing[id] = nil
        // Карты нет или она почти пустая — сканируем сам сайт по страницам и разделам
        if indexCount(id) < 60 && crawlTasks.isEmpty { startDeepCrawl(id) }
    }

    /// Шаг 2: глубокое сканирование — проходит разделы и все страницы как человек
    func startDeepCrawl(_ id: UUID, maxPages: Int = 250) {
        guard crawlTasks[id] == nil, let s = source(id), let base = URL(string: s.baseURL) else { return }
        let category = s.category
        crawlTasks[id] = Task { [weak self] in
            await self?.deepCrawl(id, base: base, category: category, maxPages: maxPages)
            self?.crawlTasks[id] = nil
            self?.indexing[id] = nil
            self?.saveIndex(id)
            if let n = self?.indexCount(id) { self?.showToast("\(s.name): всего \(n) тайтлов") }
        }
    }

    func stopDeepCrawl(_ id: UUID) {
        crawlTasks[id]?.cancel()
        crawlTasks[id] = nil
        indexing[id] = nil
        saveIndex(id)
    }

    private func deepCrawl(_ id: UUID, base: URL, category: ContentType?, maxPages: Int) async {
        var queue: [String] = [base.absoluteString] + (feed(id)?.categories.map(\.url) ?? [])
        var visited = Set<String>()
        var pages = 0
        while !queue.isEmpty && pages < maxPages && !Task.isCancelled {
            let next = queue.removeFirst()
            guard !visited.contains(next), let url = URL(string: next) else { continue }
            visited.insert(next)
            indexing[id] = "Сканирую сайт: стр. \(pages + 1) • найдено \(indexCount(id))"
            let r = await SiteScraper.scrape(url, sourceID: id, category: category, passes: 5)
            if Task.isCancelled { break }
            pages += 1
            mergeIndex(id, r.items.map { IndexEntry(url: $0.url, title: $0.title, image: $0.imageURL) }, method: "crawl")
            // Сначала листаем текущий раздел до конца, потом переходим к следующему
            if !r.nextURL.isEmpty && !visited.contains(r.nextURL) { queue.insert(r.nextURL, at: 0) }
            if pages <= 4 {
                for c in r.categories where !visited.contains(c.url) && !queue.contains(c.url) { queue.append(c.url) }
            }
            if pages % 5 == 0 { saveIndex(id) }
        }
        if var idx = indexes[id] { idx.crawledPages += pages; indexes[id] = idx }
    }

    /// Запись полного списка → карточка (с уточнёнными названием и постером, если уже загружены)
    func siteItem(_ e: IndexEntry, sourceID: UUID) -> SiteItem {
        let m = MetaFetcher.shared.meta(e.url)
        let title = (e.titleFromSlug ? m?.title : nil).flatMap { $0.isEmpty ? nil : $0 } ?? e.title
        let image = e.image.isEmpty ? (m?.image ?? "") : e.image
        let cat = source(sourceID)?.category
        return SiteItem(title: title, url: e.url, imageURL: image, sourceID: sourceID,
                        type: SiteScraper.guessType(url: e.url, text: title, fallback: cat))
    }

    // MARK: Search history

    func addSearch(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count > 1 else { return }
        data.searchHistory.removeAll { $0.query.lowercased() == q.lowercased() }
        data.searchHistory.insert(SearchHistoryItem(query: q), at: 0)
        if data.searchHistory.count > 20 { data.searchHistory.removeLast() }
    }

    // MARK: Plus

    func activatePlus(_ plan: PlanPeriod) {
        data.profile.plusPlan = plan
        data.profile.plusActivatedAt = Date()
        if let months = plan.months {
            data.profile.plusExpiresAt = Calendar.current.date(byAdding: .month, value: months, to: Date())
        } else {
            data.profile.plusExpiresAt = nil
        }
        showToast("KINORA Plus активирован 💜")
    }

    func deactivatePlus() {
        data.profile.plusPlan = nil
        data.profile.plusExpiresAt = nil
    }
}

extension JSONEncoder {
    static var kinora: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONEncoder {
    func encodeKinoraCompact<T: Encodable>(_ v: T) throws -> Data {
        dateEncodingStrategy = .iso8601
        return try encode(v)
    }
}

extension JSONDecoder {
    static var kinora: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
