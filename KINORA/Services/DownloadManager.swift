import Foundation

/// Скачивание прямых видеофайлов (mp4/mov/m4v). HLS-потоки (m3u8) и сайты с DRM не скачиваются.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published var active: [String: Double] = [:]   // key -> progress 0...1

    weak var store: LibraryStore?
    private var session: URLSession!
    private var meta: [Int: (key: String, titleID: UUID, season: Int, episode: Int, ext: String)] = [:]

    static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    static func canDownload(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else { return false }
        let ext = url.pathExtension.lowercased()
        return ["mp4", "m4v", "mov", "webm", "mkv"].contains(ext)
    }

    static func key(_ titleID: UUID, _ s: Int, _ e: Int) -> String { "\(titleID.uuidString)|\(s)|\(e)" }

    func localFile(titleID: UUID, season: Int, episode: Int) -> URL? {
        guard let item = store?.data.downloads.first(where: { $0.titleID == titleID && $0.season == season && $0.episode == episode }) else { return nil }
        let url = Self.folder.appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isDownloaded(titleID: UUID, season: Int, episode: Int) -> Bool {
        localFile(titleID: titleID, season: season, episode: episode) != nil
    }

    func start(urlString: String, titleID: UUID, season: Int, episode: Int) {
        guard let url = URL(string: urlString) else { return }
        guard Self.canDownload(urlString) else {
            store?.showToast("Этот источник не поддерживает скачивание")
            return
        }
        let key = Self.key(titleID, season, episode)
        guard active[key] == nil else { return }
        let task = session.downloadTask(with: url)
        meta[task.taskIdentifier] = (key, titleID, season, episode, url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
        active[key] = 0
        task.resume()
        store?.showToast("Загрузка началась")
    }

    func delete(_ item: DownloadItem) {
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(item.fileName))
        store?.data.downloads.removeAll { $0.id == item.id }
    }

    var totalBytes: Int64 { store?.data.downloads.reduce(0) { $0 + $1.sizeBytes } ?? 0 }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        let p = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in
            if let m = self.meta[id] { self.active[m.key] = p }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        // Файл нужно переместить синхронно, до выхода из метода
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: tmp)
        let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
        Task { @MainActor in
            guard let m = self.meta[id] else { try? FileManager.default.removeItem(at: tmp); return }
            let fileName = "\(m.titleID.uuidString)_s\(m.season)e\(m.episode).\(m.ext)"
            let dest = Self.folder.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.moveItem(at: tmp, to: dest)
            self.store?.data.downloads.removeAll { $0.titleID == m.titleID && $0.season == m.season && $0.episode == m.episode }
            self.store?.data.downloads.append(DownloadItem(titleID: m.titleID, season: m.season, episode: m.episode,
                                                           fileName: fileName, sizeBytes: size))
            self.active[m.key] = nil
            self.meta[id] = nil
            self.store?.showToast("Скачано ✅")
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil else { return }
        let id = task.taskIdentifier
        Task { @MainActor in
            if let m = self.meta[id] {
                self.active[m.key] = nil
                self.meta[id] = nil
                self.store?.showToast("Ошибка загрузки")
            }
        }
    }
}
