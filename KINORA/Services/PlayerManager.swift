import Foundation
import AVFoundation
import AVKit
import Combine
import UIKit
import MediaPlayer

struct MediaOption: Identifiable, Hashable {
    let id: String
    let name: String
    let option: AVMediaSelectionOption?
}

enum QualityLevel: String, CaseIterable, Identifiable {
    case auto, p1080, p720, p480, p360
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Авто"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        }
    }
    /// Ограничение битрейта для HLS
    var bitrate: Double {
        switch self {
        case .auto: return 0
        case .p1080: return 6_000_000
        case .p720: return 3_000_000
        case .p480: return 1_200_000
        case .p360: return 700_000
        }
    }
}

@MainActor
final class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    let player = AVPlayer()
    weak var store: LibraryStore?

    @Published var isPresented = false
    @Published var isMini = false
    @Published var titleID: UUID?
    @Published var season = 0
    @Published var episode = 0
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var rate: Float = 1.0
    @Published var quality: QualityLevel = .auto
    @Published var audioOptions: [MediaOption] = []
    @Published var subtitleOptions: [MediaOption] = []
    @Published var selectedAudio: String = "default"
    @Published var selectedSubtitle: String = "off"
    @Published var nextCountdown: Int? = nil
    @Published var errorText: String? = nil
    @Published var isLocalFile = false
    @Published var aspectFill = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObs: NSKeyValueObservation?
    private var bufferObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var lastSave: Date = .distantPast
    private var countdownTimer: Timer?
    private var pendingSeek: Double = 0

    static let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        rateObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            Task { @MainActor in
                self?.isPlaying = status == .playing
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        }
        setupRemoteCommands()
    }

    var currentTitle: MediaTitle? { titleID.flatMap { store?.title($0) } }

    var episodeName: String {
        guard let t = currentTitle, let s = t.seasons.first(where: { $0.number == season }),
              let e = s.episodes.first(where: { $0.number == episode }) else { return "" }
        return e.name
    }

    var headerSubtitle: String {
        guard let t = currentTitle else { return "" }
        return t.isEpisodic ? "Сезон \(season) • Серия \(episode)" : (t.yearText)
    }

    var hasNext: Bool {
        guard let t = currentTitle, let store else { return false }
        return store.nextEpisode(in: t, season: season, episode: episode) != nil
    }

    // MARK: Loading

    /// Ссылка на видео для эпизода (локальный файл имеет приоритет)
    func videoURL(for t: MediaTitle, season: Int, episode: Int) -> URL? {
        if let local = DownloadManager.shared.localFile(titleID: t.id, season: season, episode: episode) { return local }
        if t.isEpisodic {
            guard let s = t.seasons.first(where: { $0.number == season }),
                  let e = s.episodes.first(where: { $0.number == episode }), !e.videoURL.isEmpty else { return nil }
            return URL(string: e.videoURL)
        }
        return t.videoURL.isEmpty ? nil : URL(string: t.videoURL)
    }

    func canPlayNatively(_ t: MediaTitle, season: Int, episode: Int) -> Bool {
        videoURL(for: t, season: season, episode: episode) != nil
    }

    /// Прямое воспроизведение по ссылке (например, найденной на странице источника)
    func play(directURL: URL, title t: MediaTitle, season: Int, episode: Int, startAt: Double, headers: [String: String] = [:]) {
        load(url: directURL, title: t, season: season, episode: episode, startAt: startAt, headers: headers)
    }

    func play(title t: MediaTitle, season: Int, episode: Int, startAt: Double? = nil) {
        guard let url = videoURL(for: t, season: season, episode: episode) else {
            store?.showToast("Нет прямой ссылки на видео — откройте источник")
            return
        }
        let start = startAt ?? store?.progress(t.id, season: season, episode: episode).map { $0.isFinished ? 0 : $0.position } ?? 0
        load(url: url, title: t, season: season, episode: episode, startAt: start)
    }

    private func load(url: URL, title t: MediaTitle, season: Int, episode: Int, startAt: Double, headers: [String: String] = [:]) {
        saveProgress(force: true)
        cancelCountdown()
        errorText = nil
        titleID = t.id
        self.season = season
        self.episode = episode
        currentTime = startAt
        duration = 0
        pendingSeek = startAt
        isLocalFile = url.isFileURL
        audioOptions = []
        subtitleOptions = []

        var options: [String: Any] = [:]
        if !headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = headers }
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = quality.bitrate

        statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let status = it.status
            let errText = it.error?.localizedDescription
            Task { @MainActor in self?.itemStatusChanged(status, errText) }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didFinish() }
        }

        try? AVAudioSession.sharedInstance().setActive(true)
        player.replaceCurrentItem(with: item)
        let defaultSpeed = Float(store?.data.settings.defaultSpeed ?? 1.0)
        rate = defaultSpeed
        player.playImmediately(atRate: rate)
        isPresented = true
        isMini = false
        loadMediaOptions(asset)
        updateNowPlaying()
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, _ err: String?) {
        switch status {
        case .readyToPlay:
            let d = player.currentItem?.duration.seconds ?? 0
            if d.isFinite { duration = d }
            if pendingSeek > 1 {
                seek(to: pendingSeek)
                pendingSeek = 0
            }
            updateNowPlaying()
        case .failed:
            errorText = err ?? "Не удалось воспроизвести видео"
        default: break
        }
    }

    private func loadMediaOptions(_ asset: AVURLAsset) {
        Task { @MainActor in
            if let group = try? await asset.loadMediaSelectionGroup(for: .audible) {
                audioOptions = group.options.enumerated().map { i, o in
                    MediaOption(id: "a\(i)", name: o.displayName, option: o)
                }
                if let sel = player.currentItem?.currentMediaSelection.selectedMediaOption(in: group),
                   let match = audioOptions.first(where: { $0.option == sel }) {
                    selectedAudio = match.id
                } else {
                    selectedAudio = audioOptions.first?.id ?? "default"
                }
            }
            if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
                subtitleOptions = [MediaOption(id: "off", name: "Выключены", option: nil)] +
                    group.options.enumerated().map { i, o in MediaOption(id: "s\(i)", name: o.displayName, option: o) }
                player.currentItem?.select(nil, in: group)
                selectedSubtitle = "off"
            }
        }
    }

    func selectAudio(_ opt: MediaOption) {
        guard let item = player.currentItem, let o = opt.option else { return }
        Task { @MainActor in
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
                item.select(o, in: group)
                selectedAudio = opt.id
            }
        }
    }

    func selectSubtitle(_ opt: MediaOption) {
        guard let item = player.currentItem else { return }
        Task { @MainActor in
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                item.select(opt.option, in: group)
                selectedSubtitle = opt.id
            }
        }
    }

    func setQuality(_ q: QualityLevel) {
        quality = q
        player.currentItem?.preferredPeakBitRate = q.bitrate
    }

    // MARK: Controls

    func togglePlay() {
        if player.timeControlStatus == .paused {
            if duration > 0 && currentTime >= duration - 0.5 { seek(to: 0) }
            player.playImmediately(atRate: rate)
        } else {
            player.pause()
            saveProgress(force: true)
        }
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        saveProgress(force: true)
    }

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration - 0.5) : seconds)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func skip(_ delta: Double) {
        seek(to: currentTime + delta)
        hapticTap()
    }

    func setRate(_ r: Float) {
        rate = r
        if player.timeControlStatus != .paused { player.rate = r }
    }

    func skipIntro() {
        let target = Double(store?.data.settings.skipIntroSeconds ?? 85)
        seek(to: max(currentTime, target))
    }

    var showSkipIntro: Bool {
        guard let t = currentTitle, t.isEpisodic else { return false }
        let limit = Double(store?.data.settings.skipIntroSeconds ?? 85)
        return currentTime > 3 && currentTime < limit - 2 && duration > limit * 3
    }

    func close() {
        saveProgress(force: true)
        player.pause()
        player.replaceCurrentItem(with: nil)
        cancelCountdown()
        isPresented = false
        isMini = false
        titleID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func minimize() {
        isPresented = false
        isMini = true
    }

    func expand() {
        isMini = false
        isPresented = true
    }

    // MARK: Progress

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if pendingSeek == 0 { currentTime = seconds }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        if Date().timeIntervalSince(lastSave) > 5, isPlaying { saveProgress(force: false) }
    }

    func saveProgress(force: Bool) {
        guard let titleID, duration > 0, currentTime > 0 else { return }
        lastSave = Date()
        store?.saveProgress(titleID: titleID, season: season, episode: episode, position: currentTime, duration: duration)
    }

    private func didFinish() {
        if duration > 0 { currentTime = duration }
        saveProgress(force: true)
        guard let store, store.data.settings.autoplayNext, hasNext else { return }
        startCountdown()
    }

    // MARK: Autoplay next

    func startCountdown() {
        cancelCountdown()
        nextCountdown = store?.data.settings.autoplayDelay ?? 10
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let c = self.nextCountdown else { return }
                if c <= 1 { self.playNext() } else { self.nextCountdown = c - 1 }
            }
        }
    }

    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        nextCountdown = nil
    }

    func playNext() {
        cancelCountdown()
        guard let t = currentTitle, let store, let next = store.nextEpisode(in: t, season: season, episode: episode) else { return }
        if canPlayNatively(t, season: next.season, episode: next.episode) {
            play(title: t, season: next.season, episode: next.episode, startAt: 0)
        } else {
            store.showToast("У следующей серии нет прямой ссылки")
        }
    }

    // MARK: Now playing / remote

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.play() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(10) }
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(-10) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let t = currentTitle else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: t.isEpisodic ? "\(t.name) • S\(season)E\(episode)" : t.name,
            MPMediaItemPropertyArtist: "KINORA",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0
        ]
    }
}
