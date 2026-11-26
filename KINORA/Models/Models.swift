import Foundation
import SwiftUI

// MARK: - Content type

enum ContentType: String, Codable, CaseIterable, Identifiable {
    case movie, series, anime, cartoon, hentai, adult

    var isAdult: Bool { self == .adult || self == .hentai }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movie: return "Фильмы"
        case .series: return "Сериалы"
        case .anime: return "Аниме"
        case .cartoon: return "Мультфильмы"
        case .hentai: return "Хентай"
        case .adult: return "Порно"
        }
    }

    var singular: String {
        switch self {
        case .movie: return "Фильм"
        case .series: return "Сериал"
        case .anime: return "Аниме"
        case .cartoon: return "Мультфильм"
        case .hentai: return "Хентай"
        case .adult: return "18+"
        }
    }

    var icon: String {
        switch self {
        case .movie: return "film.fill"
        case .series: return "tv.fill"
        case .anime: return "sparkles"
        case .cartoon: return "teddybear.fill"
        case .hentai: return "18.circle.fill"
        case .adult: return "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .movie: return Color(hex: 0xA78BFA)
        case .series: return Color(hex: 0xC4B5FD)
        case .anime: return Color(hex: 0xC084FC)
        case .cartoon: return Color(hex: 0x93C5FD)
        case .hentai: return Color(hex: 0xF0ABFC)
        case .adult: return Color(hex: 0xF472B6)
        }
    }

    var gradient: [Color] {
        switch self {
        case .movie: return [Color(hex: 0x1E1B4B), Color(hex: 0x6D28D9)]
        case .series: return [Color(hex: 0x111827), Color(hex: 0x7C3AED)]
        case .anime: return [Color(hex: 0x3B0764), Color(hex: 0xDB2777)]
        case .cartoon: return [Color(hex: 0x0C4A6E), Color(hex: 0x8B5CF6)]
        case .hentai: return [Color(hex: 0x3B0764), Color(hex: 0xC026D3)]
        case .adult: return [Color(hex: 0x4C0519), Color(hex: 0xBE185D)]
        }
    }
}

// MARK: - Watch status

enum WatchStatus: String, Codable, CaseIterable, Identifiable {
    case none, planned, watching, watched, dropped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Без статуса"
        case .planned: return "Не начинал"
        case .watching: return "Смотрю"
        case .watched: return "Просмотрено"
        case .dropped: return "Заброшено"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.dashed"
        case .planned: return "clock"
        case .watching: return "play.fill"
        case .watched: return "checkmark"
        case .dropped: return "nosign"
        }
    }

    var color: Color {
        switch self {
        case .none: return .white.opacity(0.6)
        case .planned: return Color(hex: 0x93C5FD)
        case .watching: return Color(hex: 0xA78BFA)
        case .watched: return Color(hex: 0x4ADE80)
        case .dropped: return Color(hex: 0xF87171)
        }
    }
}

// MARK: - Title

struct Episode: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var number: Int
    var name: String
    /// Прямая ссылка на видео (mp4 / m3u8). Если пусто — смотрим через источник (сайт).
    var videoURL: String = ""
    /// Длительность в секундах (если известна)
    var duration: Double = 0
}

struct Season: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var number: Int
    var episodes: [Episode]
}

struct MediaTitle: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var originalName: String = ""
    var altNames: [String] = []
    var type: ContentType
    var year: Int = 0
    var endYear: Int? = nil
    var durationMinutes: Int = 0
    var ageRating: String = ""
    var genres: [String] = []
    var overview: String = ""
    var posterURL: String = ""
    var backdropURL: String = ""
    var rating: Double = 0
    var imdbRating: Double = 0
    var popularity: Double = 0
    var addedAt: Date = Date()
    var releaseDate: Date? = nil
    /// Для фильма — прямая ссылка на видео (опционально)
    var videoURL: String = ""
    var seasons: [Season] = []
    /// Прямые ссылки на страницу тайтла на конкретных источниках: sourceID -> URL
    var sourceLinks: [String: String] = [:]
    var tmdbID: Int? = nil

    // Пользовательские данные
    var status: WatchStatus = .none
    var isFavorite: Bool = false
    var isBookmarked: Bool = false
    var userRating: Double? = nil
    var tagIDs: [UUID] = []

    // Откуда тайтл: страница на сайте-источнике
    var originURL: String = ""
    var originSourceID: UUID? = nil

    var isEpisodic: Bool { !seasons.isEmpty }
    var totalEpisodes: Int { seasons.reduce(0) { $0 + $1.episodes.count } }

    var yearText: String {
        guard year > 0 else { return "" }
        if type == .movie { return "\(year)" }
        if let endYear { return endYear == year ? "\(year)" : "\(year) – \(endYear)" }
        return isEpisodic ? "\(year) – …" : "\(year)"
    }

    var durationText: String {
        guard durationMinutes > 0 else { return "" }
        let h = durationMinutes / 60, m = durationMinutes % 60
        return h > 0 ? "\(h) ч. \(m) мин." : "\(m) мин."
    }
}

// MARK: - Progress / history

struct ProgressKey: Hashable, Codable {
    var titleID: UUID
    var season: Int
    var episode: Int

    var string: String { "\(titleID.uuidString)|\(season)|\(episode)" }
}

struct WatchProgress: Codable, Hashable {
    var titleID: UUID
    var season: Int
    var episode: Int
    /// Точная позиция в секундах
    var position: Double
    var duration: Double
    var updatedAt: Date = Date()

    var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var isFinished: Bool { duration > 0 && fraction >= 0.92 }
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var titleID: UUID
    var season: Int
    var episode: Int
    var fraction: Double
    var watchedSeconds: Double
    var date: Date = Date()
}

// MARK: - Tags / collections

struct UserTag: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var emoji: String = ""
    var colorHex: UInt32 = 0xA78BFA

    var color: Color { Color(hex: colorHex) }
}

struct UserCollection: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var emoji: String = "📁"
    var titleIDs: [UUID] = []
    var createdAt: Date = Date()
}

// MARK: - Sources

enum SourceHealth: String, Codable {
    case unknown, online, offline, checking
}

struct VideoSource: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    /// Шаблон поиска: {query} будет заменён на название. Например https://site.com/search?q={query}
    var searchTemplate: String = ""
    var category: ContentType? = nil
    var isEnabled: Bool = true
    var note: String = ""
    var health: SourceHealth = .unknown
    var lastChecked: Date? = nil
    var order: Int = 0

    var host: String { URL(string: baseURL)?.host ?? baseURL }

    func searchURL(for query: String) -> URL? {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if !searchTemplate.isEmpty {
            return URL(string: searchTemplate.replacingOccurrences(of: "{query}", with: q))
        }
        return URL(string: baseURL)
    }
}

// MARK: - Search history

struct SearchHistoryItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var query: String
    var date: Date = Date()
}

// MARK: - Persisted state

struct AppData: Codable {
    var titles: [MediaTitle] = []
    var progress: [String: WatchProgress] = [:]
    var history: [HistoryEntry] = []
    var tags: [UserTag] = []
    var collections: [UserCollection] = []
    var sources: [VideoSource] = []
    var searchHistory: [SearchHistoryItem] = []
    var settings: AppSettings = AppSettings()
    var profile: UserProfile = UserProfile()
    var downloads: [DownloadItem] = []
    /// Кэш тайтлов, найденных на сайтах: sourceID -> лента
    var feeds: [String: SourceFeed] = [:]
}

struct AppSettings: Codable {
    var adultEnabled: Bool = false
    var adultConfirmed: Bool = false
    var autoplayNext: Bool = true
    var autoplayDelay: Int = 10
    var skipIntroSeconds: Int = 85
    var defaultSpeed: Double = 1.0
    var tmdbAPIKey: String = ""
    var tmdbLanguage: String = "ru-RU"
    var currency: Currency = .czk
    var hapticsEnabled: Bool = true
}

struct UserProfile: Codable {
    var nickname: String = "KinoraUser"
    var avatarEmoji: String = "🦊"
    var userID: Int = Int.random(in: 10000...99999)
    var plusPlan: PlanPeriod? = nil
    var plusActivatedAt: Date? = nil
    var plusExpiresAt: Date? = nil

    var isPlus: Bool {
        guard let plusPlan else { return false }
        if plusPlan == .lifetime { return true }
        return (plusExpiresAt ?? .distantPast) > Date()
    }
}

struct DownloadItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var titleID: UUID
    var season: Int
    var episode: Int
    var fileName: String
    var sizeBytes: Int64 = 0
    var date: Date = Date()
}


// MARK: - Контент с сайтов

/// Карточка тайтла, найденная на сайте-источнике
struct SiteItem: Codable, Identifiable, Hashable {
    var id: String { url }
    var title: String
    var url: String
    var imageURL: String
    var subtitle: String = ""
    var sourceID: UUID
    var type: ContentType? = nil
    /// Превью-ролик карточки (если сайт его даёт) — из него берём кадр, когда нет картинки
    var videoURL: String = ""
}

/// Раздел сайта (категория, жанр, меню)
struct SiteLink: Codable, Identifiable, Hashable {
    var id: String { url }
    var title: String
    var url: String
}

struct SourceFeed: Codable, Hashable {
    var items: [SiteItem] = []
    var updatedAt: Date = .distantPast
    var error: String? = nil
    /// Следующая страница главной
    var nextURL: String = ""
    /// Разделы сайта
    var categories: [SiteLink] = []
}

// MARK: - Устойчивое чтение данных (новые поля не ломают старые сохранения)

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension KeyedDecodingContainer where K == AnyKey {
    func v<T: Decodable>(_ key: String, _ def: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: AnyKey(key))) ?? nil) ?? def
    }
}

extension MediaTitle {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init(name: c.v("name", ""), type: c.v("type", ContentType.movie))
        id = c.v("id", UUID())
        originalName = c.v("originalName", "")
        altNames = c.v("altNames", [])
        year = c.v("year", 0)
        endYear = c.v("endYear", Int?.none)
        durationMinutes = c.v("durationMinutes", 0)
        ageRating = c.v("ageRating", "")
        genres = c.v("genres", [])
        overview = c.v("overview", "")
        posterURL = c.v("posterURL", "")
        backdropURL = c.v("backdropURL", "")
        rating = c.v("rating", 0.0)
        imdbRating = c.v("imdbRating", 0.0)
        popularity = c.v("popularity", 0.0)
        addedAt = c.v("addedAt", Date())
        releaseDate = c.v("releaseDate", Date?.none)
        videoURL = c.v("videoURL", "")
        seasons = c.v("seasons", [])
        sourceLinks = c.v("sourceLinks", [:])
        tmdbID = c.v("tmdbID", Int?.none)
        status = c.v("status", WatchStatus.none)
        isFavorite = c.v("isFavorite", false)
        isBookmarked = c.v("isBookmarked", false)
        userRating = c.v("userRating", Double?.none)
        tagIDs = c.v("tagIDs", [])
        originURL = c.v("originURL", "")
        originSourceID = c.v("originSourceID", UUID?.none)
    }
}

extension SiteItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init(title: c.v("title", ""), url: c.v("url", ""), imageURL: c.v("imageURL", ""),
                  sourceID: c.v("sourceID", UUID()))
        subtitle = c.v("subtitle", "")
        type = c.v("type", ContentType?.none)
        videoURL = c.v("videoURL", "")
    }
}

extension SourceFeed {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init()
        items = c.v("items", [])
        updatedAt = c.v("updatedAt", Date.distantPast)
        error = c.v("error", String?.none)
        nextURL = c.v("nextURL", "")
        categories = c.v("categories", [])
    }
}

extension VideoSource {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init(name: c.v("name", ""), baseURL: c.v("baseURL", ""))
        id = c.v("id", UUID())
        searchTemplate = c.v("searchTemplate", "")
        category = c.v("category", ContentType?.none)
        isEnabled = c.v("isEnabled", true)
        note = c.v("note", "")
        health = c.v("health", SourceHealth.unknown)
        lastChecked = c.v("lastChecked", Date?.none)
        order = c.v("order", 0)
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init()
        adultEnabled = c.v("adultEnabled", false)
        adultConfirmed = c.v("adultConfirmed", false)
        autoplayNext = c.v("autoplayNext", true)
        autoplayDelay = c.v("autoplayDelay", 10)
        skipIntroSeconds = c.v("skipIntroSeconds", 85)
        defaultSpeed = c.v("defaultSpeed", 1.0)
        tmdbAPIKey = c.v("tmdbAPIKey", "")
        tmdbLanguage = c.v("tmdbLanguage", "ru-RU")
        currency = c.v("currency", Currency.czk)
        hapticsEnabled = c.v("hapticsEnabled", true)
    }
}

extension AppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init()
        titles = c.v("titles", [])
        progress = c.v("progress", [:])
        history = c.v("history", [])
        tags = c.v("tags", [])
        collections = c.v("collections", [])
        sources = c.v("sources", [])
        searchHistory = c.v("searchHistory", [])
        settings = c.v("settings", AppSettings())
        profile = c.v("profile", UserProfile())
        downloads = c.v("downloads", [])
        feeds = c.v("feeds", [:])
    }
}
