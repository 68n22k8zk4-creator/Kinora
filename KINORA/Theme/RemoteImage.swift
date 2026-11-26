import SwiftUI
import UIKit
import AVFoundation

/// Загрузчик постеров с кэшем и заголовком Referer (многие сайты не отдают картинки без него).
/// Если картинки нет или она не загрузилась — берём случайный кадр из превью-ролика.
@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var task: Task<Void, Never>?
    private var currentKey = ""

    static let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 600
        return c
    }()
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 40 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: cfg)
    }()

    func load(_ url: URL?, referer: String?, video: URL?) {
        let key = (url?.absoluteString ?? "") + "|" + (video?.absoluteString ?? "")
        guard key != currentKey || image == nil else { return }
        currentKey = key
        task?.cancel()
        if let cached = Self.memory.object(forKey: key as NSString) { image = cached; return }
        image = nil
        guard url != nil || video != nil else { return }
        task = Task {
            var result: UIImage? = nil
            if let url { result = await Self.fetchImage(url, referer: referer) }
            if result == nil, let video, !Task.isCancelled { result = await Self.frame(from: video, referer: referer) }
            guard let img = result, !Task.isCancelled else { return }
            Self.memory.setObject(img, forKey: key as NSString)
            if currentKey == key { image = img }
        }
    }

    private static func headers(for url: URL, referer: String?) -> [String: String] {
        var h = ["User-Agent": SiteScraper.userAgent,
                 "Accept": "image/avif,image/webp,image/*,video/*,*/*;q=0.8"]
        if let referer, !referer.isEmpty {
            h["Referer"] = referer.hasSuffix("/") ? referer : referer + "/"
        } else if let scheme = url.scheme, let host = url.host {
            h["Referer"] = "\(scheme)://\(host)/"
        }
        return h
    }

    private static func fetchImage(_ url: URL, referer: String?) async -> UIImage? {
        var req = URLRequest(url: url, timeoutInterval: 20)
        headers(for: url, referer: referer).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        guard let (data, resp) = try? await session.data(for: req),
              ((resp as? HTTPURLResponse)?.statusCode ?? 200) < 400,
              let img = UIImage(data: data), img.size.width > 20 else { return nil }
        return await Task.detached(priority: .utility) { img.preparingForDisplay() ?? img }.value
    }

    /// Случайный кадр из ролика (между 15% и 60% длительности)
    private static func frame(from url: URL, referer: String?) async -> UIImage? {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers(for: url, referer: referer)])
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        var seconds = Double.random(in: 2...8)
        if let d = try? await asset.load(.duration), d.seconds.isFinite, d.seconds > 3 {
            seconds = d.seconds * Double.random(in: 0.15...0.6)
        }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        return await withCheckedContinuation { (c: CheckedContinuation<UIImage?, Never>) in
            gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cg, _, _, _ in
                c.resume(returning: cg.map { UIImage(cgImage: $0) })
            }
        }
    }
}

struct RemoteImage: View {
    var url: URL?
    var referer: String? = nil
    var videoURL: URL? = nil
    @StateObject private var loader = ImageLoader()

    var body: some View {
        Color.clear
            .overlay {
                if let img = loader.image {
                    Image(uiImage: img).resizable().scaledToFill().transition(.opacity)
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.25), value: loader.image != nil)
            .onAppear { loader.load(url, referer: referer, video: videoURL) }
            .onChange(of: url) { loader.load($0, referer: referer, video: videoURL) }
    }
}

/// Постер карточки с сайта: картинка как на сайте, иначе — кадр из превью-видео
struct SiteThumb: View {
    @EnvironmentObject var store: LibraryStore
    var item: SiteItem

    var body: some View {
        RemoteImage(url: URL(string: item.imageURL),
                     referer: store.source(item.sourceID)?.baseURL,
                     videoURL: item.videoURL.isEmpty ? nil : URL(string: item.videoURL))
    }
}
