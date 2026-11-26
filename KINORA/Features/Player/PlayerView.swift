import SwiftUI
import AVKit

struct PlayerView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    @StateObject private var volume = SystemVolume.shared
    @StateObject private var recorder = ScreenRecorder.shared

    @State private var showControls = true
    @State private var locked = false
    @State private var brightness: Double = 0.5
    @State private var scrubbing: Double? = nil
    @State private var hideTask: Task<Void, Never>? = nil
    @State private var gestureHUD: String? = nil
    @State private var dragStart: (value: Double, kind: Int)? = nil   // kind: 0 brightness, 1 volume, 2 seek
    @State private var forcedLandscape = false
    @State private var showTagPicker = false
    @AppStorage("player.gestureHintClosed") private var hintClosed = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if landscape {
                    videoArea(fullscreen: true)
                        .ignoresSafeArea()
                } else {
                    portraitLayout(geo)
                }
                HiddenVolumeView().frame(width: 1, height: 1).opacity(0.01)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            brightness = Double(Brightness.current)
            Orientation.set(.allButUpsideDown)
            scheduleHide()
        }
        .onDisappear {
            Orientation.set(.portrait)
            player.saveProgress(force: true)
        }
        .sheet(isPresented: $showTagPicker) {
            if let id = player.titleID { TagPickerSheet(titleID: id).environmentObject(store) }
        }
    }

    // MARK: Portrait

    private func portraitLayout(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            videoArea(fullscreen: false)
                .frame(height: geo.size.width * 9 / 16 + 70)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    controlStrip
                    if let t = player.currentTitle, t.isEpisodic { episodesStrip(t) }
                    HStack(alignment: .top, spacing: 12) {
                        settingsCard
                    }
                    progressCard
                    if !hintClosed { gestureHint }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .background(
                LinearGradient(colors: [Theme.bg2, Theme.bg], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    // MARK: Video area with overlay

    private func videoArea(fullscreen: Bool) -> some View {
        GeometryReader { g in
            ZStack {
                Color.black
                VideoSurface(player: player.player, fill: player.aspectFill)

                // Жесты: тап, двойной тап, свайпы
                gestureLayer(size: g.size)

                if player.isBuffering {
                    ProgressView().tint(.white).scaleEffect(1.4)
                }

                if let hud = gestureHUD {
                    Text(hud)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.6)))
                }

                if locked {
                    lockedOverlay
                } else if showControls {
                    controlsOverlay(fullscreen: fullscreen)
                        .transition(.opacity)
                }

                if player.showSkipIntro && !locked {
                    VStack { Spacer(); HStack { Spacer()
                        Button { player.skipIntro(); hapticTap() } label: {
                            Label("Пропустить заставку", systemImage: "forward.fill")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 16).frame(height: 40)
                                .background(Capsule().fill(.black.opacity(0.65)))
                                .overlay(Capsule().stroke(.white.opacity(0.35)))
                        }
                    } }
                    .padding(.bottom, fullscreen ? 90 : 62)
                    .padding(.trailing, 16)
                }

                if let c = player.nextCountdown { nextEpisodeOverlay(c) }
                if let err = player.errorText { errorOverlay(err) }
            }
            .clipped()
        }
    }

    private func gestureLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .local) { loc in
                guard !locked else { return }
                let forward = loc.x > size.width / 2
                player.skip(forward ? 10 : -10)
                flashHUD(forward ? "+10 сек" : "−10 сек")
            }
            .onTapGesture(count: 1) {
                withAnimation(.easeOut(duration: 0.2)) { showControls.toggle() }
                if showControls { scheduleHide() }
            }
            .simultaneousGesture(
                MagnificationGesture().onEnded { s in
                    withAnimation { player.aspectFill = s > 1 }
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { g in
                        guard !locked else { return }
                        if dragStart == nil {
                            let horizontal = abs(g.translation.width) > abs(g.translation.height)
                            if horizontal {
                                dragStart = (player.currentTime, 2)
                            } else if g.startLocation.x < size.width / 2 {
                                dragStart = (brightness, 0)
                            } else {
                                dragStart = (Double(volume.value), 1)
                            }
                        }
                        guard let start = dragStart else { return }
                        switch start.kind {
                        case 0:
                            let v = min(1, max(0, start.value - Double(g.translation.height / max(size.height, 1)) * 1.4))
                            brightness = v
                            Brightness.current = CGFloat(v)
                            gestureHUD = "☀️ \(Int(v * 100))%"
                        case 1:
                            let v = min(1, max(0, start.value - Double(g.translation.height / max(size.height, 1)) * 1.4))
                            volume.set(Float(v))
                            gestureHUD = "🔊 \(Int(v * 100))%"
                        default:
                            let delta = Double(g.translation.width / max(size.width, 1)) * 120
                            let target = min(max(0, start.value + delta), max(player.duration, 0))
                            scrubbing = target
                            gestureHUD = "\(delta >= 0 ? "+" : "−")\(Int(abs(delta))) сек • \(TimeFmt.clock(target))"
                        }
                    }
                    .onEnded { _ in
                        if dragStart?.kind == 2, let s = scrubbing { player.seek(to: s) }
                        scrubbing = nil
                        dragStart = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { gestureHUD = nil }
                    }
            )
    }

    private func controlsOverlay(fullscreen: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Top bar
                HStack(spacing: 12) {
                    CircleIconButton(icon: fullscreen ? "chevron.down" : "chevron.left", size: 42) {
                        if fullscreen { rotate(toLandscape: false) } else { player.minimize() }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topTitle)
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        if !player.episodeName.isEmpty {
                            Text(player.episodeName).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                        }
                    }
                    Spacer()
                    AirPlayButton().frame(width: 42, height: 42)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                    if let id = player.titleID {
                        CircleIconButton(icon: store.title(id)?.isBookmarked == true ? "bookmark.fill" : "bookmark", size: 42) { store.toggleBookmark(id) }
                    }
                    Menu {
                        Button { player.minimize() } label: { Label("Мини-плеер", systemImage: "pip") }
                        Button { player.close() } label: { Label("Закрыть плеер", systemImage: "xmark") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 42, height: 42).background(Circle().fill(Color.white.opacity(0.1)))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, fullscreen ? 14 : 8)

                Spacer()

                // Center
                HStack {
                    VerticalSlider(value: brightness, icon: "sun.max.fill") { v in
                        brightness = v; Brightness.current = CGFloat(v); scheduleHide()
                    }
                    .opacity(fullscreen ? 1 : 0.95)
                    .scaleEffect(fullscreen ? 1 : 0.72)
                    Spacer()
                    HStack(spacing: fullscreen ? 56 : 34) {
                        Button { player.skip(-10); scheduleHide() } label: {
                            Image(systemName: "gobackward.10").font(.system(size: fullscreen ? 34 : 28, weight: .medium)).foregroundStyle(.white)
                        }
                        Button { player.togglePlay(); scheduleHide() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: fullscreen ? 36 : 30, weight: .bold)).foregroundStyle(.white)
                                .frame(width: fullscreen ? 84 : 70, height: fullscreen ? 84 : 70)
                                .background(Circle().fill(.black.opacity(0.45)))
                                .overlay(Circle().stroke(.white.opacity(0.2)))
                        }
                        Button { player.skip(10); scheduleHide() } label: {
                            Image(systemName: "goforward.10").font(.system(size: fullscreen ? 34 : 28, weight: .medium)).foregroundStyle(.white)
                        }
                    }
                    Spacer()
                    VerticalSlider(value: Double(volume.value), icon: "speaker.wave.2.fill") { v in
                        volume.set(Float(v)); scheduleHide()
                    }
                    .scaleEffect(fullscreen ? 1 : 0.72)
                }
                .padding(.horizontal, fullscreen ? 40 : 6)

                Spacer()

                // Bottom
                HStack(spacing: 12) {
                    Text("\(TimeFmt.clock(scrubbing ?? player.currentTime)) / \(TimeFmt.clock(player.duration))")
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                    Scrubber(current: player.currentTime, duration: player.duration, onSeek: { player.seek(to: $0); scheduleHide() }, dragging: $scrubbing)
                    speedMenu(pill: true)
                    qualityMenu(pill: true)
                    Button { rotate(toLandscape: !fullscreen) } label: {
                        Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(.white).frame(width: 34, height: 34)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, fullscreen ? 18 : 10)

                if fullscreen {
                    HStack(spacing: 18) {
                        stripButton("lock", "Блокировка") { locked = true }
                        audioMenu(compact: true)
                        subtitleMenu(compact: true)
                        if player.hasNext { stripButton("forward.end.fill", "След. серия") { player.playNext() } }
                    }
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private var lockedOverlay: some View {
        VStack {
            Spacer()
            Button { withAnimation { locked = false; showControls = true }; scheduleHide() } label: {
                Label("Разблокировать", systemImage: "lock.open.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .overlay(Capsule().stroke(.white.opacity(0.3)))
            }
            .padding(.bottom, 24)
        }
    }

    private func nextEpisodeOverlay(_ c: Int) -> some View {
        ZStack {
            Color.black.opacity(0.65)
            VStack(spacing: 14) {
                Text("Следующая серия через \(c)").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 5)
                    Circle().trim(from: 0, to: CGFloat(c) / CGFloat(max(store.data.settings.autoplayDelay, 1)))
                        .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: c)
                    Text("\(c)").font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                }
                .frame(width: 70, height: 70)
                HStack(spacing: 12) {
                    Button("Отмена") { player.cancelCountdown() }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 20).frame(height: 42)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    Button { player.playNext() } label: {
                        Label("Смотреть сейчас", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 20).frame(height: 42)
                            .background(Capsule().fill(Theme.accentGradient))
                    }
                }
            }
        }
    }

    private func errorOverlay(_ err: String) -> some View {
        ZStack {
            Color.black.opacity(0.8)
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(Theme.gold)
                Text("Видео не воспроизводится").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text(err).font(.system(size: 13)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).padding(.horizontal, 30)
                if let t = player.currentTitle, !store.enabledSources.isEmpty {
                    Button {
                        let s = player.season, e = player.episode
                        player.close()
                        Watch.start(t, season: s, episode: e, preferredSource: store.enabledSources.first?.id, store: store, router: router, player: player)
                    } label: {
                        Label("Открыть через источник", systemImage: "globe")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 20).frame(height: 42)
                            .background(Capsule().fill(Theme.accentGradient))
                    }
                }
                Button("Закрыть") { player.close() }.foregroundStyle(Theme.text2)
            }
        }
    }

    // MARK: Control strip (под видео)

    private var controlStrip: some View {
        HStack(spacing: 0) {
            stripButton(locked ? "lock.fill" : "lock", "Блокировка\nэкрана") { withAnimation { locked.toggle() } }
            divider
            stripButton("rectangle.landscape.rotate", "Повернуть\nэкран") { rotate(toLandscape: true) }
            divider
            stripButton("pip", "Мини-\nэкран") { player.minimize() }
            divider
            stripButton(recorder.isRecording ? "record.circle.fill" : "record.circle", recorder.isRecording ? "Стоп\nзапись" : "Запись\nэкрана",
                        tint: recorder.isRecording ? Theme.red : .white) { recorder.toggle() }
            divider
            qualityMenu(pill: false)
            divider
            audioMenu(compact: false)
            divider
            speedMenu(pill: false)
        }
        .padding(.vertical, 10)
        .glass(radius: 20)
    }

    private var divider: some View { Rectangle().fill(Theme.stroke).frame(width: 1, height: 34) }

    private func stripButton(_ icon: String, _ text: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button { hapticTap(); action() } label: { stripLabel(icon, text, tint: tint) }
            .buttonStyle(.plain)
    }

    private func stripLabel(_ icon: String, _ text: String, tint: Color = .white) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(tint)
            Text(text).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private func speedMenu(pill: Bool) -> some View {
        Menu {
            ForEach(PlayerManager.speeds, id: \.self) { s in
                Button { player.setRate(s) } label: {
                    if s == player.rate { Label(speedText(s), systemImage: "checkmark") } else { Text(speedText(s)) }
                }
            }
        } label: {
            if pill {
                Text(speedText(player.rate)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().stroke(.white.opacity(0.4)))
            } else {
                stripLabel("speedometer", "Скорость\n\(speedText(player.rate))")
            }
        }
    }

    private func qualityMenu(pill: Bool) -> some View {
        Menu {
            ForEach(QualityLevel.allCases) { q in
                Button { player.setQuality(q) } label: {
                    if q == player.quality { Label(q.title, systemImage: "checkmark") } else { Text(q.title) }
                }
            }
        } label: {
            if pill {
                Text(player.quality == .auto ? "HD" : player.quality.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().stroke(.white.opacity(0.4)))
            } else {
                stripLabel("gearshape", "Качество\n\(player.quality.title)")
            }
        }
    }

    private func audioMenu(compact: Bool) -> some View {
        Menu {
            if player.audioOptions.isEmpty {
                Text("Одна дорожка (озвучку меняйте в источнике)")
            }
            ForEach(player.audioOptions) { o in
                Button { player.selectAudio(o) } label: {
                    if o.id == player.selectedAudio { Label(o.name, systemImage: "checkmark") } else { Text(o.name) }
                }
            }
        } label: {
            stripLabel("waveform", "Озвучка\n\(currentAudioName)")
        }
    }

    private func subtitleMenu(compact: Bool) -> some View {
        Menu {
            if player.subtitleOptions.isEmpty { Text("Субтитры недоступны") }
            ForEach(player.subtitleOptions) { o in
                Button { player.selectSubtitle(o) } label: {
                    if o.id == player.selectedSubtitle { Label(o.name, systemImage: "checkmark") } else { Text(o.name) }
                }
            }
        } label: {
            stripLabel("captions.bubble", "Субтитры")
        }
    }

    private var topTitle: String {
        guard let t = player.currentTitle else { return "" }
        return t.isEpisodic ? t.name + " • " + player.headerSubtitle : t.name
    }

    private var currentAudioName: String {
        player.audioOptions.first { $0.id == player.selectedAudio }?.name ?? "Оригинал"
    }

    private func speedText(_ s: Float) -> String {
        s == Float(Int(s)) ? "\(Int(s)).0x" : "\(String(format: "%g", s))x"
    }

    // MARK: Episodes strip

    private func episodesStrip(_ t: MediaTitle) -> some View {
        let season = t.seasons.first { $0.number == player.season }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Серии • \(player.season) сезон").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(season?.episodes ?? []) { ep in
                            let current = ep.number == player.episode
                            let p = store.progress(t.id, season: player.season, episode: ep.number)
                            Button {
                                if player.canPlayNatively(t, season: player.season, episode: ep.number) {
                                    player.play(title: t, season: player.season, episode: ep.number)
                                } else {
                                    store.showToast("У серии нет прямой ссылки")
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(ep.number)").font(.system(size: 15, weight: .bold))
                                    if p?.isFinished == true { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.green) }
                                }
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(current ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(current ? .clear : Theme.stroke))
                            }
                            .buttonStyle(.plain)
                            .id(ep.number)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(player.episode, anchor: .center) }
            }
        }
        .padding(12)
        .glass(radius: 20)
    }

    // MARK: Settings card

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "gearshape.fill").foregroundStyle(.white)
                Text("Настройки").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Spacer()
            }
            .padding(.bottom, 10)
            settingRow(icon: "4k.tv", title: "Качество видео") { qualityValueMenu }
            settingRow(icon: "waveform", title: "Озвучка") {
                Menu {
                    ForEach(player.audioOptions) { o in Button(o.name) { player.selectAudio(o) } }
                } label: { valueLabel(currentAudioName) }
            }
            settingRow(icon: "speedometer", title: "Скорость воспроизведения") {
                Menu {
                    ForEach(PlayerManager.speeds, id: \.self) { s in Button(speedText(s)) { player.setRate(s) } }
                } label: { valueLabel(speedText(player.rate)) }
            }
            settingRow(icon: "captions.bubble", title: "Субтитры") {
                Menu {
                    ForEach(player.subtitleOptions) { o in Button(o.name) { player.selectSubtitle(o) } }
                } label: {
                    valueLabel(player.subtitleOptions.first { $0.id == player.selectedSubtitle }?.name ?? (player.subtitleOptions.isEmpty ? "Нет" : "Выкл."))
                }
            }
            settingRow(icon: "rectangle.expand.vertical", title: "Заполнить экран") {
                Toggle("", isOn: $player.aspectFill).labelsHidden().tint(Theme.accent)
            }
            settingRow(icon: "forward.end", title: "Автопереход к серии", last: true) {
                Toggle("", isOn: $store.data.settings.autoplayNext).labelsHidden().tint(Theme.accent)
            }
        }
        .padding(16)
        .glass(radius: 20)
    }

    private var qualityValueMenu: some View {
        Menu {
            ForEach(QualityLevel.allCases) { q in Button(q.title) { player.setQuality(q) } }
        } label: { valueLabel(player.isLocalFile ? "Файл" : player.quality.title) }
    }

    private func valueLabel(_ s: String) -> some View {
        HStack(spacing: 4) {
            Text(s).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent2)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text3)
        }
    }

    private func settingRow<V: View>(icon: String, title: String, last: Bool = false, @ViewBuilder trailing: () -> V) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(.white).frame(width: 26)
                Text(title).font(.system(size: 15)).foregroundStyle(.white)
                Spacer()
                trailing()
            }
            .frame(height: 46)
            if !last { Rectangle().fill(Theme.stroke).frame(height: 1) }
        }
    }

    // MARK: Progress card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bookmark").foregroundStyle(.white)
                Text("Прогресс просмотра").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Spacer()
            }
            if let t = player.currentTitle {
                HStack(spacing: 12) {
                    PosterView(title: t, useBackdrop: true, showTitleOnPlaceholder: false)
                        .frame(width: 110, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        if t.isEpisodic { Text(player.headerSubtitle).font(.system(size: 13)).foregroundStyle(Theme.text2) }
                        Text("Позиция: \(TimeFmt.clock(player.currentTime)) — сохраняется автоматически")
                            .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        HStack {
                            ProgressLine(value: player.duration > 0 ? player.currentTime / player.duration : 0)
                            Text("\(player.duration > 0 ? Int(player.currentTime / player.duration * 100) : 0)%")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                }
                if player.hasNext {
                    Button { player.playNext() } label: {
                        Label("Следующая серия", systemImage: "forward.end.fill")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Capsule().fill(Theme.accentDeep.opacity(0.5)))
                            .overlay(Capsule().stroke(Theme.accent.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                }
                Text("Теги").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                FlowLayout(spacing: 8) {
                    Button {
                        store.setStatus(t.id, t.status == .watching ? .none : .watching)
                    } label: { Chip(title: "Смотрю", icon: "checkmark", selected: t.status == .watching, compact: true) }
                        .buttonStyle(.plain)
                    Button { store.toggleFavorite(t.id) } label: {
                        Chip(title: "Любимое", emoji: "💗", selected: t.isFavorite, tint: Theme.pink, compact: true)
                    }
                    .buttonStyle(.plain)
                    ForEach(t.tagIDs.compactMap { store.tag($0) }) { tag in
                        Chip(title: tag.name, emoji: tag.emoji, selected: true, tint: tag.color.opacity(0.6), compact: true)
                    }
                    Button { showTagPicker = true } label: { Chip(title: "", icon: "plus", compact: true) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .glass(radius: 20)
    }

    private var gestureHint: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.point.up.left.fill").font(.system(size: 26)).foregroundStyle(.white)
                .frame(width: 54, height: 54).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Жесты управления").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Text("Свайп вверх/вниз слева — яркость, справа — звук").font(.system(size: 12)).foregroundStyle(Theme.text2)
                Text("Свайп влево/вправо — перемотка • 2× тап — ±10 сек").font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Button { hintClosed = true } label: { Image(systemName: "xmark").foregroundStyle(Theme.text2) }
        }
        .padding(14)
        .glass(radius: 20)
    }

    // MARK: Helpers

    private func rotate(toLandscape: Bool) {
        forcedLandscape = toLandscape
        Orientation.set(toLandscape ? .landscape : .portrait)
    }

    private func flashHUD(_ text: String) {
        gestureHUD = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if gestureHUD == text { gestureHUD = nil } }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            if player.isPlaying && scrubbing == nil {
                withAnimation(.easeOut(duration: 0.3)) { showControls = false }
            }
        }
    }
}
