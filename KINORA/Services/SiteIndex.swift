import Foundation

// MARK: - Полный список тайтлов сайта

/// Одна страница тайтла из полного списка сайта
struct IndexEntry: Codable, Hashable, Identifiable {
    var id: String { url }
    var url: String
    var title: String
    var image: String = ""
    /// true — название взято из адреса страницы (ещё не уточнено с сайта)
    var titleFromSlug: Bool = false
}

struct SiteIndex: Codable {
    var entries: [IndexEntry] = []
    var updatedAt: Date = .distantPast
    /// Откуда собрано: "sitemap", "crawl" или оба
    var method: String = ""
    var crawledPages: Int = 0
}

// MARK: - Сетевые помощники

enum Net {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.httpCookieStorage = .shared
        return URLSession(configuration: cfg)
    }()

    /// Текст страницы/файла с учётом кириллических кодировок
    static func text(_ url: URL, referer: String? = nil) async -> String? {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(SiteScraper.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xml,text/xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("ru-RU,ru;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode < 400 else { return nil }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .windowsCP1251) ?? String(data: data, encoding: .isoLatin1)
    }

    static func matches(_ pattern: String, in text: String, group: Int = 1) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges > group, m.range(at: group).location != NSNotFound else { return nil }
            return ns.substring(with: m.range(at: group))
        }
    }

    static func first(_ pattern: String, in text: String) -> String? { matches(pattern, in: text).first }

    static func unescape(_ s: String) -> String {
        var r = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.hasPrefix("<![CDATA["), r.hasSuffix("]]>") { r = String(r.dropFirst(9).dropLast(3)) }
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&#039;", "'"), ("&nbsp;", " ")] {
            r = r.replacingOccurrences(of: a, with: b)
        }
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Карта сайта (sitemap.xml)

/// Почти у каждого сайта есть sitemap.xml — служебный список ВСЕХ страниц для поисковиков.
/// Из него KINORA получает полный каталог сайта, а не только то, что видно на главной.
enum SitemapService {
    static let junk = try! NSRegularExpression(
        pattern: "/(tag|tags|category|categories|genre|genres|author|authors|page|search|login|register|signup|static|user|users|profile|feed|rss|wp-content|wp-json|comments?|contacts?|about|faq|rules|privacy|dmca|terms|cdn-cgi)(/|$|\\?)",
        options: [.caseInsensitive])

    static func isJunk(_ url: String) -> Bool {
        guard let u = URL(string: url) else { return true }
        let path = u.path
        if path.isEmpty || path == "/" { return true }
        return junk.firstMatch(in: path, range: NSRange(location: 0, length: (path as NSString).length)) != nil
    }

    /// Собрать все страницы тайтлов. sample — адреса карточек с главной, по ним понимаем, как выглядят страницы тайтлов.
    static func build(base: URL, sample: [String], progress: @escaping (Int) -> Void) async -> [IndexEntry] {
        guard let scheme = base.scheme, let host = base.host else { return [] }
        let origin = "\(scheme)://\(host)"
        let referer = origin + "/"

        var queue: [String] = []
        if let robots = await Net.text(URL(string: origin + "/robots.txt")!) {
            queue += Net.matches("(?m)^\\s*sitemap:\\s*(\\S+)", in: robots)
        }
        queue += ["/sitemap.xml", "/sitemap_index.xml", "/sitemap-index.xml", "/wp-sitemap.xml", "/sitemap/sitemap.xml", "/sitemaps.xml"]
            .map { origin + $0 }

        var visited = Set<String>()
        var entries: [String: IndexEntry] = [:]
        var fetches = 0

        while !queue.isEmpty && fetches < 120 && entries.count < 40_000 {
            let next = queue.removeFirst()
            guard !visited.contains(next), let url = URL(string: next) else { continue }
            visited.insert(next)
            if next.hasSuffix(".gz") { continue }
            fetches += 1
            guard let xml = await Net.text(url, referer: referer), xml.contains("<loc") else { continue }

            if xml.range(of: "<sitemapindex", options: .caseInsensitive) != nil {
                let children = Net.matches("<sitemap>.*?<loc>(.*?)</loc>", in: xml).map(Net.unescape)
                // Сначала карты с тайтлами, служебные — в конец
                let ranked = children.sorted { rank($0) > rank($1) }.filter { rank($0) > -5 }
                queue.insert(contentsOf: ranked.filter { !visited.contains($0) }, at: 0)
                continue
            }

            for block in Net.matches("<url>(.*?)</url>", in: xml) {
                guard let locRaw = Net.first("<loc>(.*?)</loc>", in: block) else { continue }
                let loc = Net.unescape(locRaw)
                guard sameSite(loc, host: host), entries[loc] == nil else { continue }
                let image = Net.first("<image:loc>(.*?)</image:loc>", in: block).map(Net.unescape)
                    ?? Net.first("<video:thumbnail_loc>(.*?)</video:thumbnail_loc>", in: block).map(Net.unescape) ?? ""
                let explicitTitle = (Net.first("<video:title>(.*?)</video:title>", in: block)
                    ?? Net.first("<image:title>(.*?)</image:title>", in: block)
                    ?? Net.first("<news:title>(.*?)</news:title>", in: block)).map(Net.unescape)
                let title = explicitTitle ?? slugTitle(loc)
                entries[loc] = IndexEntry(url: loc, title: title, image: image, titleFromSlug: explicitTitle == nil)
            }
            progress(entries.count)
        }

        return filter(Array(entries.values), sample: sample)
    }

    private static func rank(_ u: String) -> Int {
        let s = u.lowercased()
        var r = 0
        for w in ["anime", "film", "movie", "serial", "series", "video", "post", "title", "catalog", "release", "hentai", "cartoon", "mult", "tv", "episode", "content", "item"] where s.contains(w) { r += 3 }
        for w in ["tag", "categor", "author", "page", "user", "image", "taxonomy", "static", "news", "blog", "comment"] where s.contains(w) { r -= 6 }
        return r
    }

    static func sameSite(_ url: String, host: String) -> Bool {
        guard let h = URL(string: url)?.host else { return false }
        let a = h.replacingOccurrences(of: "www.", with: ""), b = host.replacingOccurrences(of: "www.", with: "")
        let base = b.split(separator: ".").suffix(2).joined(separator: ".")
        return a == b || a.hasSuffix(base)
    }

    /// Оставляем только страницы, похожие на страницы тайтлов
    static func filter(_ all: [IndexEntry], sample: [String]) -> [IndexEntry] {
        let clean = all.filter { !isJunk($0.url) }
        let firstSegs = sample.compactMap { firstSegment($0) }
        guard !firstSegs.isEmpty else { return sorted(clean) }
        var counts: [String: Int] = [:]
        firstSegs.forEach { counts[$0, default: 0] += 1 }
        let threshold = max(2, firstSegs.count / 10)
        let allowed = Set(counts.filter { $0.value >= threshold }.map(\.key))
        let depths = Set(sample.compactMap { URL(string: $0)?.pathComponents.count })
        let byPattern = clean.filter { e in
            guard let seg = firstSegment(e.url) else { return false }
            if allowed.contains(seg) { return true }
            // Тайтлы прямо в корне сайта (/nazvanie-anime.html) — сравниваем глубину адреса
            if allowed.isEmpty, let d = URL(string: e.url)?.pathComponents.count { return depths.contains(d) }
            return false
        }
        return sorted(byPattern.count >= 20 ? byPattern : clean)
    }

    private static func sorted(_ list: [IndexEntry]) -> [IndexEntry] {
        list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func firstSegment(_ url: String) -> String? {
        guard let comps = URL(string: url)?.pathComponents.filter({ $0 != "/" }), !comps.isEmpty else { return nil }
        // Тайтл прямо в корне — сегмента-раздела нет
        if comps.count == 1 { return "" }
        return comps[0].lowercased()
    }

    /// Название из адреса: /anime/12345-van-pis.html → «Van pis»
    static func slugTitle(_ url: String) -> String {
        guard let u = URL(string: url) else { return url }
        var parts = u.pathComponents.filter { $0 != "/" }
        var last = parts.popLast() ?? ""
        if last.allSatisfy(\.isNumber) || ["index.html", "index.php", "watch", "online"].contains(last.lowercased()) {
            last = parts.popLast() ?? last
        }
        if let dot = last.lastIndex(of: "."), ["html", "htm", "php", "aspx"].contains(last[last.index(after: dot)...].lowercased()) {
            last = String(last[..<dot])
        }
        last = last.removingPercentEncoding ?? last
        last = last.replacingOccurrences(of: "^\\d+[-_]", with: "", options: .regularExpression)
        last = last.replacingOccurrences(of: "[-_+]", with: " ", options: .regularExpression)
        last = last.replacingOccurrences(of: "\\s+\\d{4,}$", with: "", options: .regularExpression)
        last = last.trimmingCharacters(in: .whitespaces)
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

// MARK: - Уточнение названия и постера со страницы

/// Для записей из карты сайта постепенно подтягиваем настоящее название и постер (og:title / og:image)
@MainActor
final class MetaFetcher: ObservableObject {
    static let shared = MetaFetcher()

    struct Meta: Codable { var title: String; var image: String }

    @Published private(set) var cache: [String: Meta] = [:]
    private var inFlight = Set<String>()
    private var running = 0
    private var waiting: [(String, String?)] = []
    private var saveTask: Task<Void, Never>?

    private static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("kinora_meta.json")
    }

    init() {
        if let d = try? Data(contentsOf: Self.fileURL), let c = try? JSONDecoder().decode([String: Meta].self, from: d) {
            cache = c
        }
    }

    func meta(_ url: String) -> Meta? { cache[url] }

    func request(_ url: String, referer: String?) {
        guard cache[url] == nil, !inFlight.contains(url) else { return }
        inFlight.insert(url)
        waiting.append((url, referer))
        pump()
    }

    private func pump() {
        while running < 4, !waiting.isEmpty {
            let (url, referer) = waiting.removeLast()   // сначала то, что видно сейчас
            running += 1
            Task {
                let m = await Self.load(url, referer: referer)
                running -= 1
                inFlight.remove(url)
                if let m { cache[url] = m; scheduleSave() }
                pump()
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = cache
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: Self.fileURL, options: .atomic) }
        }
    }

    nonisolated static func load(_ urlString: String, referer: String?) async -> Meta? {
        guard let url = URL(string: urlString), let html = await Net.text(url, referer: referer) else { return nil }
        func meta(_ name: String) -> String? {
            Net.first("<meta[^>]+(?:property|name)=[\"']\(name)[\"'][^>]+content=[\"']([^\"']+)[\"']", in: html)
                ?? Net.first("<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(name)[\"']", in: html)
        }
        var title = meta("og:title") ?? Net.first("<h1[^>]*>(.*?)</h1>", in: html) ?? Net.first("<title[^>]*>(.*?)</title>", in: html) ?? ""
        title = Net.unescape(title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        var image = meta("og:image") ?? meta("twitter:image") ?? ""
        if !image.isEmpty, let abs = URL(string: Net.unescape(image), relativeTo: url)?.absoluteString { image = abs }
        guard !title.isEmpty || !image.isEmpty else { return nil }
        return Meta(title: title, image: image)
    }
}
