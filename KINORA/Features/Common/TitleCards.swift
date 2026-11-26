import SwiftUI

// MARK: - Watch helper

enum Watch {
    /// Единая точка запуска просмотра:
    /// 1) локальный файл / прямая ссылка → встроенный плеер с точной позицией;
    /// 2) иначе — первый доступный подключённый источник (сайт) во встроенном браузере.
    @MainActor
    static func start(_ t: MediaTitle, season: Int? = nil, episode: Int? = nil, fromStart: Bool = false,
                      preferredSource: UUID? = nil,
                      store: LibraryStore, router: AppRouter, player: PlayerManager) {
        let resume = store.resumePoint(for: t)
        let s = season ?? resume.season
        let e = episode ?? resume.episode
        var position: Double = fromStart ? 0 : (season == nil ? resume.position : (store.progress(t.id, season: s, episode: e).map { $0.isFinished ? 0 : $0.position } ?? 0))
        if position < 0 { position = 0 }

        if preferredSource == nil, player.canPlayNatively(t, season: s, episode: e) {
            player.play(title: t, season: s, episode: e, startAt: position)
            return
        }
        // Тайтл со страницы сайта — открываем именно эту страницу
        if !t.originURL.isEmpty, let url = URL(string: t.originURL),
           preferredSource == nil || preferredSource == t.originSourceID {
            router.webSession = WebSession(titleID: t.id, season: s, episode: e,
                                           sourceID: t.originSourceID ?? store.enabledSources.first?.id ?? UUID(), url: url)
            return
        }
        let sources = store.enabledSources
        let src = preferredSource.flatMap { id in sources.first { $0.id == id } }
            ?? sources.first { $0.health != .offline } ?? sources.first
        guard let src, let url = store.watchURL(for: t, on: src) else {
            store.showToast("Добавьте ссылку на видео или подключите источник")
            return
        }
        router.webSession = WebSession(titleID: t.id, season: s, episode: e, sourceID: src.id, url: url)
    }

    /// Открыть карточку с сайта прямо в плеере источника
    @MainActor
    static func open(_ item: SiteItem, store: LibraryStore, router: AppRouter, player: PlayerManager) {
        let t = store.ensureTitle(for: item)
        start(t, store: store, router: router, player: player)
    }
}

// MARK: - Карточки с сайтов

struct SiteItemCard: View {
    @EnvironmentObject var store: LibraryStore
    var item: SiteItem
    var showsSource = true

    var body: some View {
        let lib = store.title(forURL: item.url)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    LinearGradient(colors: (item.type ?? .movie).gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: (item.type ?? .movie).icon).font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                    SiteThumb(item: item)
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    if let type = item.type { TypeBadge(type: type) }
                    Spacer()
                    if lib?.isBookmarked == true {
                        Image(systemName: "bookmark.fill").font(.system(size: 13)).foregroundStyle(Theme.accent2)
                            .padding(5).background(Circle().fill(.black.opacity(0.55)))
                    }
                }
                .padding(6)
                if let lib, let p = store.lastProgress(for: lib.id), !p.isFinished {
                    VStack { Spacer(); ProgressLine(value: p.fraction, height: 3).padding(6) }
                }
            }
            Text(item.title)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 7).padding(.horizontal, 4)
            Text(showsSource ? ([store.source(item.sourceID)?.name ?? "", item.subtitle].filter { !$0.isEmpty }.joined(separator: " • ")) : item.subtitle)
                .font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
                .padding(.horizontal, 4).padding(.top, 2).padding(.bottom, 8)
        }
        .padding(4)
        .glass(radius: 18)
    }
}

struct SiteItemPoster: View {
    var item: SiteItem
    var width: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                LinearGradient(colors: (item.type ?? .movie).gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                SiteThumb(item: item)
            }
            .frame(width: width, height: width * 1.42)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
            Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(2).frame(width: width, alignment: .leading)
            if !item.subtitle.isEmpty {
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1).frame(width: width, alignment: .leading)
            }
        }
    }
}

// MARK: - Grid card

struct PosterCard: View {
    @EnvironmentObject var store: LibraryStore
    var title: MediaTitle
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                PosterView(title: title)
                    .aspectRatio(2/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    if let badge {
                        Text(badge).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).frame(height: 20)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accentDeep))
                    }
                    Spacer()
                    if title.rating > 0 { RatingBadge(rating: title.rating) }
                }
                .padding(6)
                if let p = store.lastProgress(for: title.id), !p.isFinished {
                    VStack { Spacer(); ProgressLine(value: p.fraction, height: 3).padding(6) }
                }
            }
            HStack(alignment: .top) {
                Text(title.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { store.toggleBookmark(title.id) } label: {
                    Image(systemName: title.isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(title.isBookmarked ? Theme.accent2 : Theme.text2)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
            HStack(spacing: 4) {
                ForEach(Array(([title.type.singular] + title.genres).prefix(2)), id: \.self) { GenreTag(text: $0) }
            }
            .padding(.horizontal, 4)
            .padding(.top, 5)
            .padding(.bottom, 8)
        }
        .padding(4)
        .glass(radius: 18)
    }
}

// MARK: - Small horizontal poster (trends)

struct TrendPoster: View {
    var title: MediaTitle
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(title: title)
                .frame(width: 118, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
            Text(title.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(2).frame(width: 118, alignment: .leading)
            if title.rating > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.gold)
                    Text(String(format: "%.1f", title.rating)).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
        }
    }
}

// MARK: - List row

struct TitleRow: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    var title: MediaTitle
    var sourceID: UUID? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                PosterView(title: title)
                    .frame(width: 104, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                TypeBadge(type: title.type).padding(6)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(title.name).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                    Spacer()
                    Button { store.toggleBookmark(title.id) } label: {
                        Image(systemName: title.isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(title.isBookmarked ? Theme.accent2 : Theme.text2)
                    }.buttonStyle(.plain)
                }
                Text([title.originalName, title.yearText].filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                HStack(spacing: 10) {
                    if title.rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Theme.gold)
                            Text(String(format: "%.1f", title.rating)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold)
                        }
                    }
                    if title.imdbRating > 0 {
                        Text("IMDb \(String(format: "%.1f", title.imdbRating))").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                    if title.status != .none {
                        Label(title.status.title, systemImage: title.status.icon)
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(title.status.color).lineLimit(1)
                    }
                }
                Text(title.overview).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2)
                HStack(spacing: 4) {
                    ForEach(Array(title.genres.prefix(2)), id: \.self) { GenreTag(text: $0) }
                    Spacer(minLength: 4)
                    SmallPlayButton {
                        Watch.start(title, preferredSource: sourceID, store: store, router: router, player: player)
                    }
                }
            }
        }
        .padding(10)
        .glass(radius: 18)
    }
}

// MARK: - Continue watching card

struct ContinueCard: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    var title: MediaTitle
    var progress: WatchProgress
    var showsButton = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                PosterView(title: title, useBackdrop: true, showTitleOnPlaceholder: false)
                    .frame(width: 150, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Circle().fill(.black.opacity(0.35)).frame(width: 44, height: 44)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                Image(systemName: "play.fill").foregroundStyle(.white).font(.system(size: 17)).offset(x: 1)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(title.name).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                    Spacer()
                    Menu {
                        Button("Открыть страницу") { router.push(.title(title.id)) }
                        Button("Смотреть с начала") { Watch.start(title, season: progress.season, episode: progress.episode, fromStart: true, store: store, router: router, player: player) }
                        Button("Отметить просмотренным") { store.setStatus(title.id, .watched) }
                        Button("Убрать из «Продолжить»", role: .destructive) { store.setStatus(title.id, .dropped) }
                    } label: {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(.white).frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                }
                Text(title.isEpisodic ? "Сезон \(progress.season) • Серия \(progress.episode) • \(TimeFmt.clock(progress.position))" : "Остановились на \(TimeFmt.clock(progress.position))")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2).lineLimit(1)
                HStack(spacing: 8) {
                    ProgressLine(value: progress.fraction)
                    Text("\(Int(progress.fraction * 100))%").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                if showsButton {
                    SmallPlayButton(title: "Продолжить") { start() }
                }
            }
        }
        .padding(10)
        .glass()
        .contentShape(Rectangle())
        .onTapGesture { start() }
    }

    private func start() {
        Watch.start(title, store: store, router: router, player: player)
    }
}
