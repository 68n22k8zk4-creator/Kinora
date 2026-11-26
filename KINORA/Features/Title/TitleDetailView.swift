import SwiftUI

struct TitleDetailView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var downloads: DownloadManager
    @Environment(\.dismiss) var dismiss

    let titleID: UUID

    @State private var selectedSeason: Int = 1
    @State private var expanded = false
    @State private var showEdit = false
    @State private var showTagPicker = false
    @State private var showCollectionPicker = false
    @State private var showAllEpisodes = false
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let t = store.title(titleID) {
                content(t)
            } else {
                VStack { NavBar(title: "Удалено"); Spacer() }
            }
        }
        .background(AppBackground())
    }

    private func content(_ t: MediaTitle) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                banner(t)
                overview(t)
                actionButtons(t)
                progressCard(t)
                statusRow(t)
                if t.isEpisodic { seasonsSection(t) }
                sourcesSection(t)
                tagsSection(t)
                ratingSection(t)
                TabBarSpacer()
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            let r = store.resumePoint(for: t)
            selectedSeason = r.season > 0 ? r.season : (t.seasons.first?.number ?? 1)
        }
        .sheet(isPresented: $showEdit) { EditTitleView(existing: t, defaultType: t.type).environmentObject(store) }
        .sheet(isPresented: $showTagPicker) { TagPickerSheet(titleID: t.id).environmentObject(store) }
        .sheet(isPresented: $showCollectionPicker) { CollectionPickerSheet(titleID: t.id).environmentObject(store) }
        .confirmationDialog("Удалить «\(t.name)» из библиотеки?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { store.delete(t.id); dismiss() }
        }
    }

    // MARK: Banner

    private func banner(_ t: MediaTitle) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(title: t, useBackdrop: true, showTitleOnPlaceholder: false)
                .frame(height: 420)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.4), .clear, Theme.bg.opacity(0.85), Theme.bg],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    CircleIconButton(icon: "chevron.left") { dismiss() }
                    Spacer()
                    if let url = currentVideoURL(t), DownloadManager.canDownload(url) {
                        CircleIconButton(icon: "arrow.down.to.line") { download(t) }
                    }
                    CircleIconButton(icon: t.isBookmarked ? "bookmark.fill" : "bookmark", tint: t.isBookmarked ? Theme.accent2 : .white) {
                        store.toggleBookmark(t.id)
                    }
                    Menu {
                        Button { showEdit = true } label: { Label("Редактировать", systemImage: "pencil") }
                        Button { store.toggleFavorite(t.id) } label: {
                            Label(t.isFavorite ? "Убрать из избранного" : "В избранное", systemImage: t.isFavorite ? "heart.slash" : "heart")
                        }
                        Button { showCollectionPicker = true } label: { Label("В коллекцию", systemImage: "folder.badge.plus") }
                        Button { store.resetProgress(for: t.id); store.showToast("Прогресс сброшен") } label: {
                            Label("Сбросить прогресс", systemImage: "arrow.counterclockwise")
                        }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                            .overlay(Circle().stroke(Theme.stroke))
                    }
                }
                .padding(.horizontal, Theme.hPad)
                .padding(.top, 56)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 16) {
                PosterView(title: t)
                    .frame(width: 120, height: 172)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.strokeHi))
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
                VStack(alignment: .leading, spacing: 7) {
                    Text(t.name).font(.system(size: 28, weight: .heavy)).foregroundStyle(.white).lineLimit(3).minimumScaleFactor(0.7)
                    if !t.originalName.isEmpty && t.originalName != t.name {
                        Text(t.originalName).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.accentSoft)
                    }
                    HStack(spacing: 8) {
                        if t.rating > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").foregroundStyle(Theme.gold)
                                Text(String(format: "%.1f", t.rating)).foregroundStyle(Theme.gold).fontWeight(.bold)
                            }
                            .font(.system(size: 15))
                        }
                        if t.imdbRating > 0 {
                            Text("IMDb \(String(format: "%.1f", t.imdbRating))")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                    }
                    Text([t.yearText, t.durationText, t.ageRating].filter { !$0.isEmpty }.joined(separator: "  •  "))
                        .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    FlowLayout(spacing: 6) {
                        Chip(title: t.type.singular, compact: true)
                        ForEach(t.genres.prefix(4), id: \.self) { Chip(title: $0, compact: true) }
                    }
                }
            }
            .padding(.horizontal, Theme.hPad)
        }
        .frame(height: 420)
    }

    // MARK: Overview

    @ViewBuilder
    private func overview(_ t: MediaTitle) -> some View {
        if !t.overview.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text(t.overview)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(expanded ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { withAnimation { expanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Свернуть" : "Подробнее")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent2)
                }
            }
            .padding(.horizontal, Theme.hPad)
        }
    }

    // MARK: Actions

    private func actionButtons(_ t: MediaTitle) -> some View {
        let r = store.resumePoint(for: t)
        let hasProgress = store.lastProgress(for: t.id) != nil
        let subtitle: String = {
            if t.isEpisodic { return "Сезон \(r.season) • Серия \(r.episode)" + (r.position > 0 ? " • \(TimeFmt.clock(r.position))" : "") }
            return r.position > 0 ? "с \(TimeFmt.clock(r.position))" : (t.durationText.isEmpty ? "" : t.durationText)
        }()
        return HStack(spacing: 10) {
            PrimaryButton(title: hasProgress ? "Продолжить" : "Смотреть", subtitle: subtitle.isEmpty ? nil : subtitle, height: 58) {
                Watch.start(t, store: store, router: router, player: player)
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            downloadButton(t)
            Menu {
                Button { showTagPicker = true } label: { Label("Теги", systemImage: "tag") }
                Button { showCollectionPicker = true } label: { Label("Коллекции", systemImage: "folder") }
                Button { store.toggleFavorite(t.id) } label: { Label(t.isFavorite ? "Убрать из избранного" : "В избранное", systemImage: "heart") }
            } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke))
            }
        }
        .padding(.horizontal, Theme.hPad)
    }

    @ViewBuilder
    private func downloadButton(_ t: MediaTitle) -> some View {
        let r = store.resumePoint(for: t)
        let key = DownloadManager.key(t.id, r.season, r.episode)
        let downloaded = downloads.isDownloaded(titleID: t.id, season: r.season, episode: r.episode)
        Button { download(t) } label: {
            VStack(spacing: 2) {
                if let p = downloads.active[key] {
                    ProgressView(value: p).tint(Theme.accent2).frame(width: 60)
                    Text("\(Int(p * 100))%").font(.system(size: 12))
                } else {
                    Image(systemName: downloaded ? "checkmark.circle.fill" : "arrow.down.to.line").font(.system(size: 18, weight: .semibold))
                    Text(downloaded ? "Скачано" : "Скачать").font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(downloaded ? Theme.green : .white)
            .frame(width: 96, height: 58)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke))
        }
        .buttonStyle(PressableStyle())
    }

    private func currentVideoURL(_ t: MediaTitle) -> String? {
        let r = store.resumePoint(for: t)
        if t.isEpisodic {
            return t.seasons.first { $0.number == r.season }?.episodes.first { $0.number == r.episode }?.videoURL
        }
        return t.videoURL
    }

    private func download(_ t: MediaTitle) {
        let r = store.resumePoint(for: t)
        guard let url = currentVideoURL(t), !url.isEmpty else {
            store.showToast("Скачивание доступно только для прямых ссылок на файл")
            return
        }
        downloads.start(urlString: url, titleID: t.id, season: r.season, episode: r.episode)
    }

    // MARK: Progress

    @ViewBuilder
    private func progressCard(_ t: MediaTitle) -> some View {
        if let last = store.lastProgress(for: t.id) {
            let watched = store.watchedEpisodesCount(t)
            let total = max(t.totalEpisodes, 1)
            let fraction = t.isEpisodic ? Double(watched) / Double(total) : last.fraction
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                    Circle().trim(from: 0, to: max(0.03, fraction)).stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "play.fill").foregroundStyle(Theme.accent2).font(.system(size: 16))
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Вы смотрели").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Text(t.isEpisodic ? "\(watched) из \(t.totalEpisodes) серий • \(Int(fraction * 100))%" : "\(TimeFmt.clock(last.position)) из \(TimeFmt.clock(last.duration)) • \(Int(fraction * 100))%")
                        .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    ProgressLine(value: fraction, height: 5)
                }
                Button {
                    let first = t.seasons.first
                    Watch.start(t, season: first?.number ?? 0, episode: first?.episodes.first?.number ?? 0, fromStart: true,
                                store: store, router: router, player: player)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("С начала").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .glass()
            .padding(.horizontal, Theme.hPad)
        }
    }

    // MARK: Status

    private func statusRow(_ t: MediaTitle) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([WatchStatus.planned, .watching, .watched, .dropped]) { s in
                    Button {
                        hapticTap()
                        store.setStatus(t.id, t.status == s ? .none : s)
                    } label: {
                        Chip(title: s.title, icon: s.icon, selected: t.status == s, tint: s == .watched ? Color(hex: 0x16A34A) : (s == .dropped ? Color(hex: 0xB91C1C) : Theme.accent))
                    }
                    .buttonStyle(.plain)
                }
                Button { store.toggleFavorite(t.id) } label: {
                    Chip(title: "Избранное", icon: t.isFavorite ? "heart.fill" : "heart", selected: t.isFavorite, tint: Theme.pink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.hPad)
        }
    }

    // MARK: Seasons

    private func seasonsSection(_ t: MediaTitle) -> some View {
        let season = t.seasons.first { $0.number == selectedSeason } ?? t.seasons.first
        let episodes = season?.episodes ?? []
        let visible = showAllEpisodes ? episodes : Array(episodes.prefix(12))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Сезоны").font(.system(size: 22, weight: .bold)).foregroundStyle(.white).padding(.horizontal, Theme.hPad)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(t.seasons) { s in
                        let sel = s.number == (season?.number ?? -1)
                        Button { withAnimation { selectedSeason = s.number; showAllEpisodes = false } } label: {
                            VStack(spacing: 2) {
                                Text("\(s.number) сезон").font(.system(size: 15, weight: .semibold))
                                Text("\(s.episodes.count) серий").font(.system(size: 12)).opacity(0.8)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 110, height: 54)
                            .background(RoundedRectangle(cornerRadius: 16).fill(sel ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card)))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(sel ? Color.clear : Theme.stroke))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.hPad)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(visible) { ep in
                    EpisodeCell(title: t, season: season?.number ?? 1, episode: ep)
                }
            }
            .padding(.horizontal, Theme.hPad)

            if episodes.count > 12 {
                Button { withAnimation { showAllEpisodes.toggle() } } label: {
                    Text(showAllEpisodes ? "Свернуть" : "Показать все \(episodes.count) серий")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Sources

    private func sourcesSection(_ t: MediaTitle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Источники для просмотра", action: "Все источники") { router.push(.sources) }
            if player.canPlayNatively(t, season: store.resumePoint(for: t).season, episode: store.resumePoint(for: t).episode) {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 26)).foregroundStyle(Theme.accent2).frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Плеер KINORA").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            Text("Рекомендуем").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(Theme.accentDeep))
                        }
                        Text("Прямая ссылка • точная позиция • выбор озвучки").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                    Spacer()
                    SmallPlayButton { Watch.start(t, store: store, router: router, player: player) }
                }
                .padding(12)
                .glass(radius: 18)
                .padding(.horizontal, Theme.hPad)
            }
            if store.enabledSources.isEmpty {
                Button { router.push(.sources) } label: {
                    Label("Подключить сайт-источник", systemImage: "link.badge.plus")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent2)
                        .frame(maxWidth: .infinity).frame(height: 50).glass(radius: 16)
                }
                .padding(.horizontal, Theme.hPad)
            }
            ForEach(Array(store.enabledSources.enumerated()), id: \.element.id) { i, s in
                HStack(spacing: 12) {
                    SourceIcon(source: s, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(s.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            HealthDot(health: s.health)
                        }
                        Text(t.sourceLinks[s.id.uuidString] != nil ? "Сохранённая страница • озвучка через источник" : (s.note.isEmpty ? "Поиск по сайту" : s.note))
                            .font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                    }
                    Spacer()
                    SmallPlayButton(prominent: i == 0 && !player.canPlayNatively(t, season: store.resumePoint(for: t).season, episode: store.resumePoint(for: t).episode)) {
                        Watch.start(t, preferredSource: s.id, store: store, router: router, player: player)
                    }
                }
                .padding(12)
                .glass(radius: 18)
                .padding(.horizontal, Theme.hPad)
            }
        }
    }

    // MARK: Tags

    private func tagsSection(_ t: MediaTitle) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Теги").font(.system(size: 20, weight: .bold)).foregroundStyle(.white).padding(.top, 6)
            FlowLayout(spacing: 8) {
                ForEach(t.tagIDs.compactMap { store.tag($0) }) { tag in
                    Button { router.push(.tag(tag.id)) } label: {
                        Chip(title: tag.name, emoji: tag.emoji, selected: true, tint: tag.color.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
                Button { showTagPicker = true } label: { Chip(title: "", icon: "plus") }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.hPad)
    }

    // MARK: Rating

    private func ratingSection(_ t: MediaTitle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Моя оценка").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Spacer()
                if let r = t.userRating {
                    Text(String(format: "%.1f", r)).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.gold)
                    Button { store.update(t.id) { $0.userRating = nil } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text3) }
                } else {
                    Text("нет оценки").font(.system(size: 14)).foregroundStyle(Theme.text3)
                }
            }
            HStack(spacing: 4) {
                ForEach(1...10, id: \.self) { i in
                    let on = Double(i) <= (t.userRating ?? 0)
                    Button { hapticTap(); store.update(t.id) { $0.userRating = Double(i) } } label: {
                        Image(systemName: on ? "star.fill" : "star")
                            .font(.system(size: 22))
                            .foregroundStyle(on ? Theme.gold : Theme.text3)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }
}

// MARK: - Episode cell

struct EpisodeCell: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var downloads: DownloadManager
    var title: MediaTitle
    var season: Int
    var episode: Episode

    var body: some View {
        let p = store.progress(title.id, season: season, episode: episode.number)
        let resume = store.resumePoint(for: title)
        let isCurrent = resume.season == season && resume.episode == episode.number
        let finished = p?.isFinished ?? false
        let downloaded = downloads.isDownloaded(titleID: title.id, season: season, episode: episode.number)
        let dlProgress = downloads.active[DownloadManager.key(title.id, season, episode.number)]

        Button {
            hapticTap()
            Watch.start(title, season: season, episode: episode.number, store: store, router: router, player: player)
        } label: {
            VStack(spacing: 3) {
                HStack {
                    if finished { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.green) }
                    Spacer()
                    if let dlProgress {
                        Text("\(Int(dlProgress * 100))%").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent2)
                    } else if downloaded {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.green)
                    } else if DownloadManager.canDownload(episode.videoURL) {
                        Image(systemName: "arrow.down.to.line").font(.system(size: 11)).foregroundStyle(Theme.accent2)
                    }
                }
                .frame(height: 12)
                Text("\(episode.number)").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text(episode.name).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 28)
                if let p, !p.isFinished, p.position > 0 {
                    ProgressLine(value: p.fraction, height: 3)
                } else {
                    Color.clear.frame(height: 3)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(isCurrent ? Theme.accentDeep.opacity(0.45) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isCurrent ? Theme.accent2 : Theme.stroke, lineWidth: isCurrent ? 1.5 : 1))
            .opacity(finished && !isCurrent ? 0.65 : 1)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button { Watch.start(title, season: season, episode: episode.number, fromStart: true, store: store, router: router, player: player) } label: {
                Label("Смотреть с начала", systemImage: "arrow.counterclockwise")
            }
            Button {
                store.saveProgress(titleID: title.id, season: season, episode: episode.number,
                                   position: max(episode.duration, 1), duration: max(episode.duration, 1))
            } label: { Label("Отметить просмотренной", systemImage: "checkmark") }
            if DownloadManager.canDownload(episode.videoURL) {
                Button { downloads.start(urlString: episode.videoURL, titleID: title.id, season: season, episode: episode.number) } label: {
                    Label("Скачать", systemImage: "arrow.down.to.line")
                }
            }
        }
    }
}
