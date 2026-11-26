import Foundation

/// Необязательный онлайн-каталог через TMDB (бесплатный ключ на themoviedb.org → Settings → API).
/// Без ключа приложение работает полностью локально.
struct TMDBService {
    let apiKey: String
    let language: String

    struct SearchResponse: Decodable { let results: [Item] }

    struct Item: Decodable, Identifiable {
        let id: Int
        let media_type: String?
        let title: String?
        let name: String?
        let original_title: String?
        let original_name: String?
        let overview: String?
        let poster_path: String?
        let backdrop_path: String?
        let vote_average: Double?
        let popularity: Double?
        let release_date: String?
        let first_air_date: String?
        let genre_ids: [Int]?
        let original_language: String?

        var displayName: String { title ?? name ?? "Без названия" }
        var original: String { original_title ?? original_name ?? "" }
        var year: Int {
            let s = release_date ?? first_air_date ?? ""
            return Int(s.prefix(4)) ?? 0
        }
        var isTV: Bool { media_type == "tv" }

        var guessedType: ContentType {
            let g = genre_ids ?? []
            if g.contains(16) {
                return original_language == "ja" ? .anime : .cartoon
            }
            return isTV ? .series : .movie
        }
    }

    struct MovieDetails: Decodable {
        let runtime: Int?
        let genres: [Genre]?
        let imdb_id: String?
    }

    struct TVDetails: Decodable {
        let episode_run_time: [Int]?
        let genres: [Genre]?
        let last_air_date: String?
        let status: String?
        let seasons: [TVSeason]?
    }

    struct TVSeason: Decodable {
        let season_number: Int
        let episode_count: Int
        let name: String?
    }

    struct TVSeasonDetails: Decodable {
        let episodes: [TVEpisode]
    }

    struct TVEpisode: Decodable {
        let episode_number: Int
        let name: String?
        let runtime: Int?
    }

    struct Genre: Decodable { let id: Int; let name: String }

    enum TMDBError: LocalizedError {
        case noKey, bad(Int)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Добавьте TMDB API ключ в настройках"
            case .bad(let c): return "TMDB ответил ошибкой \(c)"
            }
        }
    }

    private func request(_ path: String, _ query: [URLQueryItem] = []) async throws -> Data {
        guard !apiKey.isEmpty else { throw TMDBError.noKey }
        var comps = URLComponents(string: "https://api.themoviedb.org/3\(path)")!
        var items = query + [URLQueryItem(name: "language", value: language)]
        let isBearer = apiKey.count > 40
        if !isBearer { items.append(URLQueryItem(name: "api_key", value: apiKey)) }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!, timeoutInterval: 15)
        if isBearer { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw TMDBError.bad(code) }
        return data
    }

    func search(_ q: String) async throws -> [Item] {
        let data = try await request("/search/multi", [URLQueryItem(name: "query", value: q),
                                                         URLQueryItem(name: "include_adult", value: "false")])
        let r = try JSONDecoder().decode(SearchResponse.self, from: data)
        return r.results.filter { $0.media_type == "movie" || $0.media_type == "tv" }
    }

    /// Превращает результат TMDB в полноценный тайтл библиотеки (с сезонами и сериями)
    func makeTitle(from item: Item) async -> MediaTitle {
        var t = MediaTitle(name: item.displayName, type: item.guessedType)
        t.originalName = item.original
        t.year = item.year
        t.overview = item.overview ?? ""
        t.posterURL = item.poster_path ?? ""
        t.backdropURL = item.backdrop_path ?? ""
        t.rating = ((item.vote_average ?? 0) * 10).rounded() / 10
        t.popularity = item.popularity ?? 0
        t.tmdbID = item.id
        t.genres = (item.genre_ids ?? []).compactMap { Self.genreNames[$0] }

        do {
            if item.isTV {
                let data = try await request("/tv/\(item.id)")
                let d = try JSONDecoder().decode(TVDetails.self, from: data)
                if let g = d.genres, !g.isEmpty { t.genres = g.map(\.name) }
                t.durationMinutes = d.episode_run_time?.first ?? 0
                if let last = d.last_air_date, let y = Int(last.prefix(4)), d.status == "Ended" || d.status == "Canceled" {
                    t.endYear = y
                }
                var seasons: [Season] = []
                for s in (d.seasons ?? []) where s.season_number > 0 && s.episode_count > 0 {
                    var eps: [Episode] = (1...s.episode_count).map { Episode(number: $0, name: "Серия \($0)") }
                    if s.season_number <= 6,
                       let sd = try? await request("/tv/\(item.id)/season/\(s.season_number)"),
                       let det = try? JSONDecoder().decode(TVSeasonDetails.self, from: sd) {
                        eps = det.episodes.map {
                            Episode(number: $0.episode_number,
                                    name: ($0.name?.isEmpty == false ? $0.name! : "Серия \($0.episode_number)"),
                                    duration: Double(($0.runtime ?? 0) * 60))
                        }
                    }
                    seasons.append(Season(number: s.season_number, episodes: eps))
                }
                t.seasons = seasons
            } else {
                let data = try await request("/movie/\(item.id)")
                let d = try JSONDecoder().decode(MovieDetails.self, from: data)
                if let g = d.genres, !g.isEmpty { t.genres = g.map(\.name) }
                t.durationMinutes = d.runtime ?? 0
            }
        } catch {
            // Детали не обязательны — оставляем то, что есть
        }
        return t
    }

    static let genreNames: [Int: String] = [
        28: "Боевик", 12: "Приключения", 16: "Мультфильм", 35: "Комедия", 80: "Криминал",
        99: "Документальный", 18: "Драма", 10751: "Семейный", 14: "Фэнтези", 36: "История",
        27: "Ужасы", 10402: "Музыка", 9648: "Детектив", 10749: "Мелодрама", 878: "Фантастика",
        10770: "ТВ фильм", 53: "Триллер", 10752: "Военный", 37: "Вестерн",
        10759: "Экшен и приключения", 10762: "Детский", 10763: "Новости", 10764: "Реалити",
        10765: "Фантастика и фэнтези", 10766: "Мыльная опера", 10767: "Ток-шоу", 10768: "Война и политика"
    ]
}
