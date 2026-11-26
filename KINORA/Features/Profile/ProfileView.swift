import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @State private var editingProfile = false
    @State private var selectedPlan: PlanPeriod = .year

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                AppHeader(showsCrown: false).padding(.top, 6)

                profileHeader

                HStack(spacing: 8) {
                    StatTile(icon: "play.fill", iconColor: Theme.accent2, value: TimeFmt.hours(store.statTotalSeconds), label: "Просмотрено\n(часов)")
                    StatTile(icon: "film.stack.fill", iconColor: Theme.accentSoft, value: "\(store.statTitlesInLibrary)", label: "Тайтлов")
                    StatTile(icon: "star.fill", iconColor: Theme.gold, value: store.statAverageRating > 0 ? String(format: "%.1f", store.statAverageRating) : "—", label: "Средний рейтинг")
                    StatTile(icon: "flame.fill", iconColor: .orange, value: "\(store.statActiveDays) дн.", label: "Активность")
                }
                .padding(.horizontal, Theme.hPad)

                plusBanner

                VStack(alignment: .leading, spacing: 10) {
                    Text("Тарифные планы").font(.system(size: 20, weight: .bold)).foregroundStyle(.white).padding(.horizontal, Theme.hPad)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach([PlanPeriod.month, .quarter, .halfYear, .year, .lifetime]) { p in
                                Button { router.tab = .plus } label: {
                                    PlanCard(plan: p, currency: store.data.settings.currency, selected: p == .year, popular: p == .year)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        .padding(.horizontal, Theme.hPad)
                        .padding(.vertical, 12)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Дополнительно").font(.system(size: 20, weight: .bold)).foregroundStyle(.white).padding(.horizontal, Theme.hPad)
                    VStack(spacing: 0) {
                        menuRow("gearshape", "Настройки приложения", "18+, плеер, подписка и другое") { router.push(.settings) }
                        menuRow("link", "Источники", "\(store.data.sources.count) подключено") { router.push(.sources) }
                        menuRow("arrow.down.to.line", "Загрузки", "Ваши скачанные файлы") { router.push(.downloads) }
                        menuRow("arrow.triangle.2.circlepath.icloud", "Синхронизация и бэкап", "Экспорт и импорт прогресса и данных") { router.push(.backup) }
                        menuRow("chart.bar.fill", "Статистика", "Активность и жанры") { router.push(.stats) }
                        menuRow("info.circle", "О приложении", "Версия \(Bundle.main.appVersion)", last: true) { router.push(.about) }
                    }
                    .glass()
                    .padding(.horizontal, Theme.hPad)
                }

                thanks
                TabBarSpacer()
            }
        }
        .sheet(isPresented: $editingProfile) { ProfileEditSheet().environmentObject(store) }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                Text(store.data.profile.avatarEmoji)
                    .font(.system(size: 54))
                    .frame(width: 104, height: 104)
                    .background(Circle().fill(LinearGradient(colors: [Theme.accentDeep, Color(hex: 0x1E1B4B)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().stroke(Theme.accentGradient, lineWidth: 3))
                    .shadow(color: Theme.accent.opacity(0.5), radius: 14)
                Button { editingProfile = true } label: {
                    Image(systemName: "pencil").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Circle().fill(Theme.accentDeep))
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(store.data.profile.nickname).font(.system(size: 24, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    if store.isPlus { Text("👑") }
                }
                HStack(spacing: 5) {
                    Image(systemName: store.isPlus ? "crown.fill" : "person.fill").foregroundStyle(store.isPlus ? Theme.gold : Theme.text2)
                    Text(store.isPlus ? "Премиум пользователь" : "Бесплатный аккаунт")
                        .foregroundStyle(store.isPlus ? Theme.accent2 : Theme.text2)
                }
                .font(.system(size: 14, weight: .medium))
                Text("ID: #\(store.data.profile.userID)").font(.system(size: 13)).foregroundStyle(Theme.text3)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.hPad)
    }

    private var plusBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill").foregroundStyle(Theme.gold)
                        Text("KINORA Plus").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.gold)
                    }
                    Text("Больше возможностей для максимального наслаждения от просмотра!")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Button { router.tab = .plus } label: {
                    HStack(spacing: 4) {
                        Text(store.isPlus ? "Управлять" : "Оформить")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(Capsule().fill(Theme.accentGradient))
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    benefit("Неограниченные коллекции и теги")
                    benefit("Синхронизация и бэкап")
                    benefit("Расширенная статистика")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    let c = store.data.settings.currency
                    if let s = Pricing.savings(.year, c) {
                        Text("-\(s)%").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black)
                            .padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(Theme.gold))
                    }
                    Text("от \(c.format(Pricing.price(.month, c))) / мес.").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    Text("или \(c.format(Pricing.price(.year, c))) / год").font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.plusGradient))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.accent.opacity(0.7)))
        .shadow(color: Theme.accent.opacity(0.3), radius: 16)
        .padding(.horizontal, Theme.hPad)
    }

    private func benefit(_ t: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent2).font(.system(size: 13))
            Text(t).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
        }
    }

    private func menuRow(_ icon: String, _ title: String, _ sub: String, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: icon).font(.system(size: 19)).foregroundStyle(.white).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Text(sub).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.text3)
                }
                .padding(.horizontal, 16)
                .frame(height: 64)
                if !last { Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 60) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var thanks: some View {
        HStack(spacing: 14) {
            Text("🦊💜").font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                Text("Спасибо, что вы с нами! 💜").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text("С KINORA просмотр становится ещё лучше ♡").font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [Color(hex: 0x2E1065), Theme.card], startPoint: .leading, endPoint: .trailing)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.accent.opacity(0.4)))
        .padding(.horizontal, Theme.hPad)
    }
}

extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

struct ProfileEditSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var nick = ""
    @State private var emoji = ""
    private let avatars = ["🦊", "🐱", "🐼", "🐉", "👾", "🦄", "🐺", "🦉", "🐸", "🤖", "👻", "🌙", "⭐️", "🍿", "🎬", "😎"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Никнейм") { TextField("Никнейм", text: $nick) }
                Section("Аватар") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(avatars, id: \.self) { a in
                            Text(a).font(.system(size: 30)).frame(width: 46, height: 46)
                                .background(Circle().fill(emoji == a ? Theme.accent.opacity(0.4) : .clear))
                                .onTapGesture { emoji = a }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if !nick.trimmingCharacters(in: .whitespaces).isEmpty { store.data.profile.nickname = nick }
                        store.data.profile.avatarEmoji = emoji
                        dismiss()
                    }
                }
            }
            .onAppear { nick = store.data.profile.nickname; emoji = store.data.profile.avatarEmoji }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @Environment(\.dismiss) var dismiss
    @State private var askAdult = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Показывать раздел 18+", isOn: Binding(
                    get: { store.data.settings.adultEnabled },
                    set: { on in
                        if on && !store.data.settings.adultConfirmed { askAdult = true }
                        else { store.data.settings.adultEnabled = on }
                    }))
            } header: { Text("Контент") } footer: {
                Text("По умолчанию раздел 18+ скрыт везде: в каталоге, поиске, на главной и в источниках.")
            }

            Section("Плеер") {
                Toggle("Автопереход к следующей серии", isOn: $store.data.settings.autoplayNext)
                Stepper("Таймер автоперехода: \(store.data.settings.autoplayDelay) сек", value: $store.data.settings.autoplayDelay, in: 3...30)
                Stepper("«Пропустить заставку» до: \(store.data.settings.skipIntroSeconds) сек", value: $store.data.settings.skipIntroSeconds, in: 30...240, step: 5)
                Picker("Скорость по умолчанию", selection: $store.data.settings.defaultSpeed) {
                    ForEach(PlayerManager.speeds, id: \.self) { s in Text("\(String(format: "%g", s))x").tag(Double(s)) }
                }
            }

            Section("Подписка") {
                Picker("Валюта цен", selection: $store.data.settings.currency) {
                    ForEach(Currency.allCases) { c in Text("\(c.code) (\(c.symbol))").tag(c) }
                }
                Button("KINORA Plus") { router.push(.plus) }
            }

            Section("Данные") {
                Button("Источники") { router.push(.sources) }
                Button("Резервная копия и синхронизация") { router.push(.backup) }
                Button("Сбросить все данные", role: .destructive) { confirmReset = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .safeAreaInset(edge: .top) { NavBar(title: "Настройки").padding(.bottom, 6).background(Theme.bg.opacity(0.9)) }
        .alert("Вам есть 18 лет?", isPresented: $askAdult) {
            Button("Да, мне 18+") {
                store.data.settings.adultConfirmed = true
                store.data.settings.adultEnabled = true
            }
            Button("Нет", role: .cancel) {}
        } message: {
            Text("Раздел содержит материалы для взрослых.")
        }
        .confirmationDialog("Удалить все данные и вернуть демо?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) { store.resetAll() }
        }
    }
}

// MARK: - Downloads

struct DownloadsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var downloads: DownloadManager

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                NavBar(title: "Загрузки")
                Text("Занято: \(ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2).padding(.horizontal, Theme.hPad)
                if !downloads.active.isEmpty {
                    ForEach(Array(downloads.active.keys.sorted()), id: \.self) { key in
                        HStack {
                            ProgressView(value: downloads.active[key] ?? 0).tint(Theme.accent2)
                            Text("\(Int((downloads.active[key] ?? 0) * 100))%").font(.system(size: 12)).foregroundStyle(.white)
                        }
                        .padding(12).glass(radius: 14).padding(.horizontal, Theme.hPad)
                    }
                }
                if store.data.downloads.isEmpty && downloads.active.isEmpty {
                    EmptyStateView(icon: "arrow.down.circle", title: "Нет загрузок",
                                   subtitle: "Скачивать можно видео с прямой ссылкой на файл (mp4/mov). Потоковые и DRM-источники не скачиваются.")
                }
                ForEach(store.data.downloads) { d in
                    if let t = store.title(d.titleID) {
                        HStack(spacing: 12) {
                            PosterView(title: t).frame(width: 50, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                Text((t.isEpisodic ? "S\(d.season)E\(d.episode) • " : "") + ByteCountFormatter.string(fromByteCount: d.sizeBytes, countStyle: .file))
                                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                            }
                            Spacer()
                            Button { player.play(title: t, season: d.season, episode: d.episode) } label: {
                                Image(systemName: "play.fill").foregroundStyle(.white).frame(width: 36, height: 36)
                                    .background(Circle().fill(Theme.accentGradient))
                            }
                            Button { downloads.delete(d) } label: {
                                Image(systemName: "trash").foregroundStyle(Theme.red).frame(width: 32, height: 36)
                            }
                        }
                        .padding(10).glass(radius: 16).padding(.horizontal, Theme.hPad)
                    }
                }
                Text("Файлы также видны в приложении «Файлы» → На iPhone → KINORA → Downloads.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3).padding(.horizontal, Theme.hPad)
                TabBarSpacer()
            }
        }
        .background(AppBackground())
    }
}

// MARK: - Backup / sync

struct BackupView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var exportURL: URL? = nil
    @State private var importing = false
    @State private var resultText: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                NavBar(title: "Синхронизация")
                card(icon: "square.and.arrow.up.fill", title: "Экспорт резервной копии",
                     text: "Один JSON-файл: библиотека, точные позиции просмотра, история, теги, коллекции, источники и настройки.") {
                    if let url = exportURL {
                        ShareLink(item: url) {
                            Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(Capsule().fill(Theme.accentGradient))
                        }
                    } else {
                        PrimaryButton(title: "Создать копию", icon: "doc.badge.plus", height: 46) {
                            exportURL = store.exportBackup()
                        }
                    }
                }
                card(icon: "square.and.arrow.down.fill", title: "Восстановление / перенос",
                     text: "Импорт файла заменит текущие данные. Так можно перенести всё на другой iPhone (через AirDrop, Telegram, Файлы).") {
                    SecondaryButton(title: "Выбрать файл", icon: "folder", height: 46) { importing = true }
                }
                if !store.isPlus {
                    Text("Автоматическая синхронизация между устройствами — часть KINORA Plus и появится вместе с облаком. Ручной бэкап доступен всем.")
                        .font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.horizontal, Theme.hPad)
                }
                if let resultText {
                    Text(resultText).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.green).padding(.horizontal, Theme.hPad)
                }
                TabBarSpacer()
            }
        }
        .background(AppBackground())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                resultText = store.importBackup(from: url) ? "Данные восстановлены ✅" : "Не удалось прочитать файл"
            }
        }
    }

    private func card<C: View>(icon: String, title: String, text: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.accent2)
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            }
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.text2)
            content()
        }
        .padding(16)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                NavBar(title: "О приложении")
                VStack(spacing: 12) {
                    KinoraLogo(size: 34)
                    Text("Версия \(Bundle.main.appVersion)").font(.system(size: 14)).foregroundStyle(Theme.text2)
                    Text("Все ваши сайты с фильмами, сериалами и аниме в одном приложении: общий каталог, поиск сразу по всем сайтам, точное продолжение просмотра, теги и коллекции.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .glass()
                .padding(.horizontal, Theme.hPad)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Важно").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text("• KINORA не хранит и не распространяет видео — приложение открывает сайты и ссылки, которые добавляете вы.")
                    Text("• Защита DRM не обходится. Скачивание и запись экрана работают только там, где это разрешает источник и iOS.")
                    Text("• Данные хранятся только на устройстве.")
                }
                .font(.system(size: 13)).foregroundStyle(Theme.text2)
                .padding(16)
                .glass()
                .padding(.horizontal, Theme.hPad)
                TabBarSpacer()
            }
        }
        .background(AppBackground())
    }
}
