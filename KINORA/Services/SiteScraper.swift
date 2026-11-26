import Foundation
import WebKit
import UIKit

/// Универсальный «читатель» сайтов.
/// Открывает страницу в невидимом браузере (с JavaScript, куками и обычным iPhone-User-Agent),
/// ждёт отрисовки и вытаскивает карточки тайтлов: ссылка + постер + название.
/// Так любой сайт-каталог превращается в ленту KINORA без отдельного парсера под каждый сайт.
struct ScrapeResult {
    var items: [SiteItem] = []
    var searchTemplate: String = ""
    var siteName: String = ""
    var pageTitle: String = ""
    var image: String = ""
    var description: String = ""
    var blocked = false
    /// Следующая страница списка (пагинация)
    var nextURL: String = ""
    /// Разделы сайта: категории, жанры, меню
    var categories: [SiteLink] = []
    /// Видео на странице (для кадра-превью)
    var video: String = ""
}

@MainActor
final class SiteScraper: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    nonisolated static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    /// Скачать и разобрать страницу
    /// passes — сколько раз прокрутить вниз и нажать «Показать ещё» (для сайтов с подгрузкой без страниц)
    static func scrape(_ url: URL, sourceID: UUID, category: ContentType?, passes: Int = 3) async -> ScrapeResult {
        let s = SiteScraper()
        return await s.run(url, sourceID: sourceID, category: category, passes: passes)
    }

    private func run(_ url: URL, sourceID: UUID, category: ContentType?, passes: Int) async -> ScrapeResult {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // общие куки со встроенным браузером
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 2400), configuration: config)
        wv.customUserAgent = Self.userAgent
        wv.navigationDelegate = self
        webView = wv
        // Невидимо кладём в окно: так срабатывает «ленивая» подгрузка картинок и JS сайтов
        wv.alpha = 0.01
        wv.isUserInteractionEnabled = false
        if let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first {
            window.insertSubview(wv, at: 0)
        }

        let loaded = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            continuation = c
            wv.load(URLRequest(url: url, timeoutInterval: 25))
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                self?.finish(false)
            }
        }
        _ = loaded

        // Даём сайту дорисовать JS, затем прокручиваем и жмём «Показать ещё», пока появляются новые карточки
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        var previous = -1
        for _ in 0..<max(1, passes) {
            let count = (await js(wv, Self.loadMoreJS) as? NSNumber)?.intValue ?? 0
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            if count == previous { break }
            previous = count
        }

        var result = ScrapeResult()
        if let json = await js(wv, Self.extractJS) as? String,
           let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result.searchTemplate = obj["search"] as? String ?? ""
            result.siteName = obj["name"] as? String ?? ""
            result.pageTitle = obj["title"] as? String ?? ""
            result.image = obj["image"] as? String ?? ""
            result.description = obj["desc"] as? String ?? ""
            result.blocked = (obj["blocked"] as? Bool) ?? false
            result.nextURL = obj["next"] as? String ?? ""
            result.video = obj["video"] as? String ?? ""
            let cats = obj["cats"] as? [[String: Any]] ?? []
            result.categories = cats.compactMap { d in
                guard let t = d["t"] as? String, let u = d["u"] as? String else { return nil }
                return SiteLink(title: Self.clean(t), url: u)
            }
            let raw = obj["items"] as? [[String: Any]] ?? []
            result.items = raw.compactMap { d in
                guard let t = d["t"] as? String, let u = d["u"] as? String else { return nil }
                let i = d["i"] as? String ?? ""
                let v = d["v"] as? String ?? ""
                if i.isEmpty && v.isEmpty { return nil }
                let sub = d["s"] as? String ?? ""
                return SiteItem(title: Self.clean(t), url: u, imageURL: i, subtitle: Self.clean(sub),
                                sourceID: sourceID, type: Self.guessType(url: u, text: t + " " + sub, fallback: category),
                                videoURL: v)
            }
        }
        wv.stopLoading()
        wv.removeFromSuperview()
        wv.navigationDelegate = nil
        webView = nil
        return result
    }

    /// evaluateJavaScript через completion handler (async-версия падает на undefined)
    private func js(_ wv: WKWebView, _ script: String) async -> Any? {
        await withCheckedContinuation { (c: CheckedContinuation<Any?, Never>) in
            wv.evaluateJavaScript(script) { value, _ in c.resume(returning: value) }
        }
    }

    private func finish(_ ok: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let c = continuation {
            continuation = nil
            c.resume(returning: ok)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finish(true) }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(false) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(false) }
    }

    // MARK: - Helpers

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Тип контента по адресу и тексту карточки
    static func guessType(url: String, text: String, fallback: ContentType?) -> ContentType? {
        let s = (url + " " + text).lowercased()
        func has(_ keys: [String]) -> Bool { keys.contains { s.contains($0) } }
        // Сайт 18+ — всё с него остаётся в 18+
        if fallback == .hentai { return .hentai }
        if fallback == .adult { return has(["hentai", "хентай"]) ? .hentai : .adult }
        if has(["hentai", "хентай"]) { return .hentai }
        if has(["/xxx", "porn", "порно", "18+"]) { return .adult }
        if has(["anime", "аниме", "/ova", "ongoing", "онгоинг"]) { return .anime }
        if has(["cartoon", "multfilm", "mult", "мульт", "animation"]) { return .cartoon }
        if has(["serial", "series", "сериал", "/tv/", "/tv-", "сезон", "season"]) { return .series }
        if has(["film", "movie", "фильм", "kino"]) { return fallback ?? .movie }
        return fallback
    }

    /// Угадать категорию сайта по его адресу и названию
    static func guessCategory(host: String, name: String) -> ContentType? {
        let s = (host + " " + name).lowercased()
        if ["hentai", "хентай", "hentasis"].contains { s.contains($0) } { return .hentai }
        if ["porn", "xxx", "порно", "sex"].contains { s.contains($0) } { return .adult }
        if ["anime", "аниме", "ani", "shiki"].contains { s.contains($0) } { return .anime }
        if ["mult", "cartoon"].contains { s.contains($0) } { return .cartoon }
        if ["serial", "series", "сериал"].contains { s.contains($0) } { return .series }
        return nil
    }

    // MARK: - JS

    /// Прокрутка вниз + нажатие кнопки «Показать ещё / Load more». Возвращает число картинок-ссылок.
    static let loadMoreJS = """
    (function(){
      var n = document.querySelectorAll('a[href] img, a[href] [style*="background"]').length;
      var re = /^(показать|загрузить|смотреть) (ещ[её]|больше|все)|^ещ[её]( \\d+)?$|^больше$|load more|show more|more videos|see more|view more|more results/i;
      var els = document.querySelectorAll('button, [role="button"], a, div[class*="more"], span[class*="more"]');
      for (var i = 0; i < els.length; i++) {
        var e = els[i], t = (e.textContent || '').replace(/\\s+/g, ' ').trim();
        if (t.length > 30 || !re.test(t)) continue;
        if (e.tagName === 'A') {
          var h = e.getAttribute('href') || '';
          if (h && h !== '#' && h.indexOf('javascript') !== 0) continue;   // это ссылка на другую страницу — не трогаем
        }
        try { e.click(); } catch(x) {}
        break;
      }
      window.scrollTo(0, document.body.scrollHeight);
      return n;
    })();
    """

    static let extractJS = """
    (function(){
      function abs(u){ try { return new URL(u, location.href).href; } catch(e) { return ''; } }
      var IMG = /\\.(jpe?g|png|webp|avif|gif)(\\?|#|$)/i;
      var VID = /\\.(mp4|webm|m3u8)(\\?|#|$)/i;
      function isJunk(u){ return !u || u.indexOf('data:') === 0 || /logo|icon|avatar|flag|sprite|blank|spacer|pixel|placeholder|loading|lazy\\.(gif|png|svg)/i.test(u); }
      function bestFromSrcset(ss){
        if (!ss) return '';
        var best = '', bw = 0;
        ss.split(',').forEach(function(p){
          var parts = p.trim().split(/\\s+/); var w = parseInt(parts[1]) || 1;
          if (parts[0] && w >= bw) { bw = w; best = parts[0]; }
        });
        return best;
      }
      // Картинка как на сайте: сначала «ленивые» атрибуты (там настоящий постер), потом srcset, потом src
      function pickSrc(im){
        var pref = ['data-src','data-original','data-lazy-src','data-lazy','data-thumb_url','data-mediumthumb','data-thumb','data-image','data-poster','data-preview-image','data-webp','data-bg','data-img'];
        for (var i = 0; i < pref.length; i++) { var v = im.getAttribute(pref[i]); if (v && !isJunk(v)) return abs(v); }
        for (var j = 0; j < im.attributes.length; j++) {
          var at = im.attributes[j];
          if (at.name.indexOf('data-') === 0 && IMG.test(at.value) && !isJunk(at.value) && at.value.indexOf(' ') < 0) return abs(at.value);
        }
        var ss = bestFromSrcset(im.getAttribute('data-srcset') || im.getAttribute('srcset'));
        if (ss && !isJunk(ss)) return abs(ss);
        var s = im.currentSrc || im.getAttribute('src') || '';
        return isJunk(s) ? '' : abs(s);
      }
      function imgOf(el){
        var best = '', area = 0;
        var ims = el.querySelectorAll('img');
        for (var i = 0; i < ims.length; i++) {
          var s = pickSrc(ims[i]);
          if (!s) continue;
          var r = ims[i].getBoundingClientRect();
          var a = (r.width || 100) * (r.height || 100);
          if (r.width && r.width < 45) continue;
          if (a > area) { area = a; best = s; }
        }
        if (best) return best;
        var srcs = el.querySelectorAll('picture source[srcset], source[data-srcset]');
        for (var k = 0; k < srcs.length; k++) {
          var v = bestFromSrcset(srcs[k].getAttribute('srcset') || srcs[k].getAttribute('data-srcset'));
          if (v && !isJunk(v)) return abs(v);
        }
        var vids = el.querySelectorAll('video[poster]');
        if (vids.length) return abs(vids[0].getAttribute('poster'));
        var nodes = [el].concat(Array.prototype.slice.call(el.querySelectorAll('div,span,a,figure,i'), 0, 25));
        for (var j = 0; j < nodes.length; j++) {
          var bgAttr = nodes[j].getAttribute && (nodes[j].getAttribute('data-bg') || nodes[j].getAttribute('data-background'));
          if (bgAttr && !isJunk(bgAttr)) return abs(bgAttr);
          var bg = nodes[j].style && nodes[j].style.backgroundImage;
          if (!bg || bg === 'none') { try { bg = getComputedStyle(nodes[j]).backgroundImage; } catch(e) { bg = ''; } }
          if (bg && bg.indexOf('url(') === 0) {
            var u = bg.slice(4, -1).replace(/["']/g, '');
            if (!isJunk(u)) return abs(u);
          }
        }
        return '';
      }
      // Превью-ролик карточки (наведение/hover-превью)
      function videoOf(el){
        var all = [el].concat(Array.prototype.slice.call(el.querySelectorAll('*'), 0, 40));
        for (var i = 0; i < all.length; i++) {
          var n = all[i];
          if (!n.attributes) continue;
          for (var j = 0; j < n.attributes.length; j++) {
            var v = n.attributes[j].value;
            if (v && VID.test(v) && v.indexOf(' ') < 0) return abs(v);
          }
          if (n.tagName === 'VIDEO' && (n.currentSrc || n.src)) return abs(n.currentSrc || n.src);
        }
        return '';
      }
      function txt(el){ return el ? (el.textContent || '').replace(/\\s+/g, ' ').trim() : ''; }
      function titleOf(card, a){
        var sel = 'h1,h2,h3,h4,h5,[class*="title"],[class*="name"],[class*="Title"],[class*="Name"]';
        var h = card.querySelector(sel);
        var t = txt(h);
        if (!t || t.length < 2) t = a.getAttribute('title') || '';
        if (!t) { var im = card.querySelector('img'); if (im) t = im.getAttribute('alt') || im.getAttribute('title') || ''; }
        if (!t) t = txt(a);
        return t.replace(/\\s+/g, ' ').trim();
      }
      function subOf(card, title){
        var sel = '[class*="year"],[class*="date"],[class*="genre"],[class*="info"],[class*="meta"],[class*="duration"],[class*="time"],[class*="views"],[class*="cat"],[class*="quality"],[class*="series"],[class*="ep"]';
        var parts = [], seen = {};
        var els = card.querySelectorAll(sel);
        for (var i = 0; i < els.length && parts.length < 3; i++) {
          var t = txt(els[i]);
          if (!t || t.length > 50 || t === title || seen[t] || title.indexOf(t) >= 0) continue;
          seen[t] = 1; parts.push(t);
        }
        return parts.join(' • ');
      }
      var host = location.host.replace(/^www\\./, '');
      function sameSite(href){
        var h; try { h = new URL(href).host.replace(/^www\\./, ''); } catch(e) { return false; }
        var base = host.split('.').slice(-2).join('.');
        return h === host || h.slice(-base.length) === base;
      }
      var bad = /\\/(login|register|signup|auth|user|users|profile|faq|rules|contacts?|about|privacy|dmca|feedback|cdn-cgi|terms|support|upload|premium)(\\/|$|\\?)/i;
      var anchors = document.querySelectorAll('a[href]');
      var items = [], seen = {};
      for (var k = 0; k < anchors.length && items.length < 400; k++) {
        var a = anchors[k];
        var href = abs(a.getAttribute('href'));
        if (!href || href.indexOf('javascript:') === 0 || !sameSite(href)) continue;
        var path = ''; try { path = new URL(href).pathname; } catch(e) {}
        if (path === '/' || path === '' || bad.test(path)) continue;
        if (href.split('#')[0] === location.href.split('#')[0]) continue;
        var card = a, img = imgOf(a), vid = '';
        if (!img) {
          var p = a.parentElement;
          for (var d = 0; d < 4 && p && !img; d++) {
            if (p.querySelectorAll('a[href]').length > 4) break;
            img = imgOf(p); card = p; p = p.parentElement;
          }
        }
        vid = videoOf(card);
        if (!img && !vid) continue;
        var key = href.split('#')[0];
        if (seen[key]) continue;
        var t = titleOf(card, a);
        if (!t || t.length < 2 || t.length > 160) continue;
        seen[key] = 1;
        items.push({ t: t, u: key, i: img, v: vid, s: subOf(card, t) });
      }

      // Следующая страница
      function findNext(){
        var l = document.querySelector('link[rel="next"], a[rel="next"]');
        if (l && l.href) return abs(l.getAttribute('href'));
        var cands = document.querySelectorAll('a[href]');
        var words = /^(next|далее|следующая|вперед|вперёд|›|»|>|→|next page|наступна|další)$/i;
        for (var i = 0; i < cands.length; i++) {
          var c = cands[i], t = txt(c), cls = (c.className || '') + ' ' + (c.parentElement ? c.parentElement.className : '');
          var label = (c.getAttribute('aria-label') || c.getAttribute('title') || '');
          if (words.test(t) || /next|nav-next|pagination-next|page-next/i.test(typeof cls === 'string' ? cls : '') || /next|следующ/i.test(label)) {
            var h = abs(c.getAttribute('href'));
            if (h && h !== location.href && sameSite(h)) return h;
          }
        }
        // Номер текущей страницы + 1
        var cur = 1, m = location.href.match(/[\\/?&](?:page|p|pg|start)[=\\/](\\d+)/i) || location.href.match(/\\/(\\d+)\\/?$/);
        if (m) cur = parseInt(m[1]);
        for (var j = 0; j < cands.length; j++) {
          if (txt(cands[j]) === String(cur + 1)) {
            var hh = abs(cands[j].getAttribute('href'));
            if (hh && sameSite(hh)) return hh;
          }
        }
        // Шаблоны адресов
        var u = location.href;
        if (/[?&]page=\\d+/i.test(u)) return u.replace(/([?&]page=)(\\d+)/i, function(_, a, n){ return a + (parseInt(n) + 1); });
        if (/\\/page\\/\\d+/i.test(u)) return u.replace(/(\\/page\\/)(\\d+)/i, function(_, a, n){ return a + (parseInt(n) + 1); });
        return '';
      }

      // Разделы сайта: меню, категории, жанры
      var cats = [], cseen = {};
      var zones = document.querySelectorAll('nav, header, aside, [class*="menu"], [class*="Menu"], [class*="categor"], [class*="genre"], [class*="nav"], [id*="menu"], [id*="nav"]');
      for (var z = 0; z < zones.length && cats.length < 80; z++) {
        var links = zones[z].querySelectorAll('a[href]');
        for (var q = 0; q < links.length && cats.length < 80; q++) {
          var ln = links[q], ct = txt(ln), ch = abs(ln.getAttribute('href'));
          if (!ct || ct.length < 2 || ct.length > 32 || !ch || !sameSite(ch) || cseen[ch]) continue;
          if (ln.querySelector('img') && ct.length < 2) continue;
          var cp = ''; try { cp = new URL(ch).pathname; } catch(e) {}
          if (cp === '/' || bad.test(cp) || seen[ch.split('#')[0]]) continue;
          if (/^\\d+$/.test(ct)) continue;
          cseen[ch] = 1;
          cats.push({ t: ct, u: ch });
        }
      }

      var tmpl = '';
      var inp = document.querySelector('input[type="search"], input[name="q"], input[name="s"], input[name="query"], input[name="story"], input[name="search"], input[name="keyword"], input[name="k"], input[name="text"], input[name="search_query"], input[name="do_search"]');
      if (inp && inp.form && inp.name) {
        var f = inp.form, act = abs(f.getAttribute('action') || location.pathname), ps = [];
        for (var e = 0; e < f.elements.length; e++) {
          var el = f.elements[e];
          if (!el.name) continue;
          if (el === inp) ps.push(encodeURIComponent(el.name) + '={query}');
          else if (el.type === 'hidden') ps.push(encodeURIComponent(el.name) + '=' + encodeURIComponent(el.value));
        }
        tmpl = act.split('#')[0] + (act.indexOf('?') >= 0 ? '&' : '?') + ps.join('&');
      } else if (inp && inp.name) {
        tmpl = location.origin + '/?' + encodeURIComponent(inp.name) + '={query}';
      }
      function meta(n){ var m = document.querySelector('meta[property="' + n + '"], meta[name="' + n + '"]'); return m ? (m.getAttribute('content') || '') : ''; }
      var pageVideo = meta('og:video') || meta('og:video:url') || meta('og:video:secure_url');
      if (!pageVideo) { var pv = document.querySelector('video'); if (pv) pageVideo = pv.currentSrc || pv.src || (pv.querySelector('source') ? pv.querySelector('source').src : ''); }
      var bodyText = (document.body ? document.body.innerText : '').slice(0, 400).toLowerCase();
      var blocked = /just a moment|checking your browser|verify you are human|ddos-guard|подтвердите, что вы не робот/.test(bodyText) && items.length === 0;
      return JSON.stringify({
        items: items, search: tmpl, next: findNext(), cats: cats,
        name: meta('og:site_name') || document.title.split(/[|\\-—–]/).pop().trim(),
        title: meta('og:title') || txt(document.querySelector('h1')) || document.title,
        image: abs(meta('og:image') || meta('twitter:image') || ''),
        video: pageVideo && pageVideo.indexOf('blob:') !== 0 ? abs(pageVideo) : '',
        desc: meta('og:description') || meta('description'),
        blocked: blocked
      });
    })();
    """
}
