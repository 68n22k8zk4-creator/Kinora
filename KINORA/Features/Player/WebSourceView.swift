import SwiftUI
import WebKit

/// Просмотр через сайт-источник во встроенном браузере.
/// Скрипт находит HTML5 <video> на странице (включая iframe-плееры), каждые 3 сек
/// сохраняет точную позицию и при открытии перематывает на сохранённую секунду.
/// DRM не обходится: защищённые видео играют только так, как разрешает сайт.
struct WebSourceView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) var dismiss

    @State var session: WebSession
    @StateObject private var model = WebModel()
    @State private var showEpisodePicker = false
    @State private var showAlternatives = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .top) {
                KinoraWebView(model: model)
                    .ignoresSafeArea(edges: .bottom)
                if model.progress < 1 {
                    ProgressView(value: model.progress).tint(Theme.accent2).frame(height: 2)
                }
                if model.failed { failedBanner }
            }
            bottomBar
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear(perform: setup)
        .onDisappear {
            Orientation.set(.portrait)
        }
        .confirmationDialog("Открыть в другом источнике", isPresented: $showAlternatives, titleVisibility: .visible) {
            ForEach(store.alternativeSources(excluding: session.sourceID)) { s in
                Button(s.name) { switchSource(s) }
            }
        }
        .sheet(isPresented: $showEpisodePicker) { episodePicker }
    }

    private var title: MediaTitle? { session.titleID.flatMap { store.title($0) } }
    private var source: VideoSource? { store.source(session.sourceID) }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: 10) {
            CircleIconButton(icon: "xmark", size: 38) { close() }
            VStack(alignment: .leading, spacing: 1) {
                Text(title?.name ?? model.webView?.title ?? source?.name ?? "").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    if let source { HealthDot(health: source.health) }
                    Text(source?.name ?? model.host).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                    if title?.isEpisodic == true {
                        Button { showEpisodePicker = true } label: {
                            Text("S\(session.season) • E\(session.episode)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent2)
                        }
                    }
                }
            }
            Spacer()
            if model.videoTime > 0 {
                Text(TimeFmt.clock(model.videoTime)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white).padding(.horizontal, 8).frame(height: 26)
                    .background(Capsule().fill(Theme.accentDeep.opacity(0.6)))
            }
            Menu {
                Button { saveLink() } label: { Label("Запомнить эту страницу для тайтла", systemImage: "pin") }
                if let direct = model.directVideoURL {
                    Button { openNative(direct) } label: { Label("Открыть видео в плеере KINORA", systemImage: "play.rectangle") }
                }
                Button { showAlternatives = true } label: { Label("Другой источник", systemImage: "arrow.triangle.swap") }
                Button { Orientation.set(.landscape) } label: { Label("Повернуть экран", systemImage: "rectangle.landscape.rotate") }
                Button { Orientation.set(.portrait) } label: { Label("Вертикально", systemImage: "rectangle.portrait") }
                if let url = model.currentURL { Link(destination: url) { Label("Открыть в Safari", systemImage: "safari") } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(Circle().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bg2)
    }

    private var bottomBar: some View {
        HStack {
            Button { model.webView?.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!model.canGoBack)
            Spacer()
            Button { model.webView?.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!model.canGoForward)
            Spacer()
            Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
            Spacer()
            Button { showAlternatives = true } label: { Image(systemName: "arrow.triangle.swap") }
            Spacer()
            if let direct = model.directVideoURL {
                Button { openNative(direct) } label: { Image(systemName: "play.rectangle.fill").foregroundStyle(Theme.accent2) }
            } else {
                Button { saveLink() } label: { Image(systemName: "pin") }
            }
        }
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .frame(height: 50)
        .background(Theme.bg2.ignoresSafeArea(edges: .bottom))
    }

    private var failedBanner: some View {
        VStack(spacing: 10) {
            Text("Сайт не отвечает").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            Text("Открыть тот же тайтл в другом подключённом источнике?").font(.system(size: 13)).foregroundStyle(Theme.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(store.alternativeSources(excluding: session.sourceID)) { s in
                        Button { switchSource(s) } label: {
                            HStack { SourceIcon(source: s, size: 26); Text(s.name).foregroundStyle(.white) }
                                .padding(.horizontal, 12).frame(height: 40)
                                .background(Capsule().fill(Theme.accentDeep.opacity(0.6)))
                        }
                    }
                    Button { model.webView?.reload(); model.failed = false } label: {
                        Text("Повторить").foregroundStyle(.white).padding(.horizontal, 14).frame(height: 40)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                }
            }
        }
        .padding(16)
        .glass(highlighted: true)
        .padding(16)
    }

    private var episodePicker: some View {
        NavigationStack {
            List {
                ForEach(title?.seasons ?? []) { s in
                    Section("\(s.number) сезон") {
                        ForEach(s.episodes) { e in
                            Button {
                                session.season = s.number
                                session.episode = e.number
                                model.resumePosition = session.titleID.flatMap { store.progress($0, season: s.number, episode: e.number)?.position } ?? 0
                                model.resetResume()
                                showEpisodePicker = false
                            } label: {
                                HStack {
                                    Text("\(e.number). \(e.name)").foregroundStyle(.white)
                                    Spacer()
                                    if s.number == session.season && e.number == session.episode {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent2)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Какую серию смотрите?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    // MARK: Logic

    private func setup() {
        Orientation.set(.allButUpsideDown)
        model.resumePosition = session.titleID.flatMap { store.progress($0, season: session.season, episode: session.episode) }
            .map { $0.isFinished ? 0 : $0.position } ?? 0
        model.onProgress = { time, duration in
            // Свободный просмотр сайта: тайтл появляется в истории, как только началось видео
            if session.titleID == nil, let page = model.currentURL {
                let item = SiteItem(title: model.webView?.title?.isEmpty == false ? model.webView!.title! : (page.host ?? "Видео"),
                                    url: page.absoluteString, imageURL: model.pageImage,
                                    sourceID: session.sourceID, type: source?.category)
                session.titleID = store.ensureTitle(for: item).id
            }
            guard let id = session.titleID else { return }
            store.saveProgress(titleID: id, season: session.season, episode: session.episode,
                               position: time, duration: duration)
        }
        model.load(session.url)
    }

    private func switchSource(_ s: VideoSource) {
        guard let t = title, let url = store.watchURL(for: t, on: s) else { return }
        session.sourceID = s.id
        session.url = url
        model.failed = false
        model.load(url)
    }

    private func saveLink() {
        guard let url = model.currentURL?.absoluteString, let id = session.titleID else {
            store.showToast("Начните просмотр, чтобы привязать страницу")
            return
        }
        store.update(id) { $0.sourceLinks[session.sourceID.uuidString] = url }
        store.showToast("Страница сохранена для этого источника")
    }

    private func openNative(_ url: URL) {
        guard let t = title else { return }
        let start = model.videoTime
        let referer = model.currentURL?.absoluteString ?? ""
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            player.play(directURL: url, title: t, season: session.season, episode: session.episode,
                        startAt: start, headers: referer.isEmpty ? [:] : ["Referer": referer])
        }
    }

    private func close() {
        model.flush()
        router.webSession = nil
        dismiss()
    }
}

// MARK: - Model

@MainActor
final class WebModel: NSObject, ObservableObject {
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var failed = false
    @Published var videoTime: Double = 0
    @Published var directVideoURL: URL?
    var pageImage: String = ""

    var resumePosition: Double = 0
    var onProgress: ((Double, Double) -> Void)?
    weak var webView: WKWebView?
    private var lastDuration: Double = 0
    private var observers: [NSKeyValueObservation] = []

    var host: String { currentURL?.host ?? "" }

    func attach(_ wv: WKWebView) {
        webView = wv
        observers = [
            wv.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
                let p = w.estimatedProgress
                Task { @MainActor in self?.progress = p }
            },
            wv.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in
                let v = w.canGoBack
                Task { @MainActor in self?.canGoBack = v }
            },
            wv.observe(\.canGoForward, options: [.new]) { [weak self] w, _ in
                let v = w.canGoForward
                Task { @MainActor in self?.canGoForward = v }
            },
            wv.observe(\.url, options: [.new]) { [weak self] w, _ in
                let u = w.url
                Task { @MainActor in self?.currentURL = u }
            }
        ]
        if let u = pendingURL {
            pendingURL = nil
            load(u)
        }
    }

    private var pendingURL: URL?

    func load(_ url: URL) {
        directVideoURL = nil
        videoTime = 0
        guard let wv = webView else { pendingURL = url; return }
        installScript(wv)
        wv.load(URLRequest(url: url))
    }

    /// Смена серии: обновляем позицию для скрипта
    func resetResume() {
        guard let wv = webView else { return }
        installScript(wv)
        wv.evaluateJavaScript("window.__kinoraResume = \(resumePosition); window.__kinoraApplied = false;", completionHandler: nil)
    }

    private func installScript(_ wv: WKWebView) {
        let ucc = wv.configuration.userContentController
        ucc.removeAllUserScripts()
        let js = Self.script.replacingOccurrences(of: "__RESUME__", with: "\(resumePosition)")
        ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    }

    func flush() {
        if videoTime > 0 && lastDuration > 0 { onProgress?(videoTime, lastDuration) }
    }

    func handle(_ body: Any) {
        guard let dict = body as? [String: Any] else { return }
        let t = (dict["t"] as? Double) ?? Double((dict["t"] as? Int) ?? 0)
        let d = (dict["d"] as? Double) ?? Double((dict["d"] as? Int) ?? 0)
        if let img = dict["img"] as? String, !img.isEmpty { pageImage = img }
        if let src = dict["src"] as? String, src.hasPrefix("http"), let u = URL(string: src) {
            directVideoURL = u
        }
        guard d > 30, t.isFinite, d.isFinite else { return }
        videoTime = t
        lastDuration = d
        if t > 1 { onProgress?(t, d) }
    }

    static let script = """
    (function(){
      if (window.__kinoraInstalled) return;
      window.__kinoraInstalled = true;
      window.__kinoraResume = __RESUME__;
      window.__kinoraApplied = false;
      function pick(){
        var vs = document.getElementsByTagName('video'), best = null;
        for (var i = 0; i < vs.length; i++) {
          var v = vs[i];
          if (!best || (v.duration || 0) > (best.duration || 0)) best = v;
        }
        return best;
      }
      setInterval(function(){
        var v = pick();
        if (!v) return;
        var d = v.duration;
        if (!d || !isFinite(d)) return;
        var r = window.__kinoraResume || 0;
        if (!window.__kinoraApplied && r > 5 && r < d - 10) {
          try { v.currentTime = r; } catch(e) {}
          window.__kinoraApplied = true;
        } else if (!window.__kinoraApplied) {
          window.__kinoraApplied = true;
        }
        try {
          var og = document.querySelector('meta[property="og:image"]');
          window.webkit.messageHandlers.kinora.postMessage({t: v.currentTime, d: d, p: v.paused ? 1 : 0, src: v.currentSrc || '', img: og ? og.content : ''});
        } catch(e) {}
      }, 3000);
    })();
    """
}

struct KinoraWebView: UIViewRepresentable {
    @ObservedObject var model: WebModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "kinora")
        config.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.isOpaque = false
        wv.backgroundColor = UIColor(Theme.bg)
        wv.scrollView.backgroundColor = UIColor(Theme.bg)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        model.attach(wv)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "kinora")
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let model: WebModel
        init(model: WebModel) { self.model = model }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let body = message.body
            Task { @MainActor in self.model.handle(body) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            markFailed(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            markFailed(error)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in self.model.failed = false }
        }

        private func markFailed(_ error: Error) {
            let code = (error as NSError).code
            if code == NSURLErrorCancelled { return }
            Task { @MainActor in self.model.failed = true }
        }

        /// Блокируем всплывающие окна (реклама): ссылки с target=_blank открываем в этом же окне только по тапу
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
