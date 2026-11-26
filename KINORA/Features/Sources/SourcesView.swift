import SwiftUI

struct SourceIcon: View {
    var source: VideoSource
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28).fill(Color.white.opacity(0.08))
            Text(String(source.name.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.logoGradient)
            AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(source.host)&sz=128")) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFit().padding(size * 0.16)
                        .background(RoundedRectangle(cornerRadius: size * 0.28).fill(Theme.cardHi))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
    }
}

struct HealthDot: View {
    var health: SourceHealth
    var body: some View {
        Group {
            switch health {
            case .checking: ProgressView().scaleEffect(0.6)
            default:
                Circle().fill(color).frame(width: 8, height: 8).shadow(color: color, radius: 3)
            }
        }
        .frame(width: 14, height: 14)
    }
    private var color: Color {
        switch health {
        case .online: return Theme.green
        case .offline: return Theme.red
        case .unknown, .checking: return Theme.text3
        }
    }
}

/// Готовые легальные площадки для быстрого добавления
struct SourcePreset: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let search: String
    let category: ContentType?
    let label: String
    let icon: String

    static let all: [SourcePreset] = [
        SourcePreset(name: "YouTube", url: "https://m.youtube.com", search: "https://m.youtube.com/results?search_query={query}", category: nil, label: "Видео", icon: "play.rectangle.fill"),
        SourcePreset(name: "Vimeo", url: "https://vimeo.com", search: "https://vimeo.com/search?q={query}", category: nil, label: "Авторское", icon: "v.circle.fill"),
        SourcePreset(name: "Internet Archive", url: "https://archive.org", search: "https://archive.org/search?query={query}", category: .movie, label: "Фильмы", icon: "building.columns.fill"),
        SourcePreset(name: "Dailymotion", url: "https://www.dailymotion.com", search: "https://www.dailymotion.com/search/{query}/videos", category: nil, label: "Видео", icon: "d.circle.fill"),
        SourcePreset(name: "RUTUBE", url: "https://rutube.ru", search: "https://rutube.ru/search/?query={query}", category: nil, label: "Видео", icon: "r.circle.fill"),
        SourcePreset(name: "Crunchyroll", url: "https://www.crunchyroll.com", search: "https://www.crunchyroll.com/search?q={query}", category: .anime, label: "Аниме", icon: "sparkles"),
    ]
}

struct SourcesView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    @Environment(\.dismiss) var dismiss
    @State private var urlText = ""
    @State private var editing: VideoSource? = nil
    @State private var reordering = false
    @State private var adding = false

    var body: some View {
        List {
            Group {
                header
                addField
                presets
                myHeader
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))

            ForEach(store.sortedSources) { s in
                SourceRow(source: s, onEdit: { editing = s })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: Theme.hPad, bottom: 4, trailing: Theme.hPad))
                    .swipeActions {
                        Button(role: .destructive) { store.deleteSource(s.id) } label: { Label("Удалить", systemImage: "trash") }
                    }
            }
            .onMove { store.moveSources(from: $0, to: $1) }

            Group {
                if !store.isPlus { premiumBanner }
                tips
                TabBarSpacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .sheet(item: $editing) { s in SourceEditView(source: s).environmentObject(store) }

    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavBar(title: "") {
                if store.isRefreshingAny {
                    ProgressView().tint(Theme.accent2).frame(width: 44, height: 44)
                } else {
                    CircleIconButton(icon: "arrow.clockwise") { Task { await store.refreshAll(force: true) } }
                }
            }
            Text("Добавление сайтов").font(.system(size: 32, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, Theme.hPad)
            Text("Подключайте свои любимые сайты и смотрите контент в одном приложении")
                .font(.system(size: 15)).foregroundStyle(Theme.text2)
                .padding(.horizontal, Theme.hPad)
        }
    }

    private var addField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(Theme.text2)
                TextField("", text: $urlText, prompt: Text("Введите URL сайта…").foregroundColor(Theme.text3))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .onSubmit(addFromField)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Theme.accent.opacity(0.35)))
            Button(action: addFromField) {
                HStack(spacing: 6) {
                    if adding { ProgressView().tint(.white) } else { Image(systemName: "plus") }
                    Text(adding ? "Сканирую" : "Добавить")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).frame(height: 52)
                .background(Capsule().fill(Theme.accentGradient))
                .shadow(color: Theme.accent.opacity(0.5), radius: 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.hPad)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.gold)
                Text("Популярные источники").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SourcePreset.all) { p in
                        let added = store.data.sources.contains { URL(string: $0.baseURL)?.host == URL(string: p.url)?.host }
                        Button { addPreset(p) } label: {
                            VStack(spacing: 6) {
                                Image(systemName: added ? "checkmark.circle.fill" : p.icon)
                                    .font(.system(size: 26)).foregroundStyle(added ? Theme.green : Theme.accent2)
                                Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                Text(p.label).font(.system(size: 11)).foregroundStyle(Theme.text2)
                                    .padding(.horizontal, 8).frame(height: 18)
                                    .background(Capsule().fill(Color.white.opacity(0.07)))
                            }
                            .frame(width: 96, height: 112)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke))
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(added)
                    }
                }
            }
        }
        .padding(14)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }

    private var myHeader: some View {
        HStack {
            Image(systemName: "gearshape.fill").foregroundStyle(.white)
            Text("Мои источники").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
            Text("\(store.data.sources.count)\(store.isPlus ? "" : "/\(FreeLimits.sources)")").font(.system(size: 13)).foregroundStyle(Theme.text3)
            Spacer()
            Button(reordering ? "Готово" : "Управление") { withAnimation { reordering.toggle() } }
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent2)
        }
        .padding(.horizontal, Theme.hPad)
        .padding(.top, 6)
    }

    private var premiumBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "crown.fill").foregroundStyle(Theme.gold)
                    Text("Премиум возможности").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                }
                Text("Добавляйте неограниченное количество источников, используйте расширенные настройки и резервное копирование.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2)
                Button { router.tab = .plus } label: {
                    HStack(spacing: 6) { Text("Оформить подписку"); Image(systemName: "arrow.right") }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(Capsule().fill(Theme.accentGradient))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Text("👑").font(.system(size: 54))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.plusGradient))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.accent.opacity(0.6)))
        .padding(.horizontal, Theme.hPad)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("💡")
                Text("Полезные советы").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            }
            tip("Просто вставьте адрес сайта — KINORA сама найдёт тайтлы и поиск")
            tip("Если тайтлов 0 — откройте сайт кнопкой 🌐 и пройдите проверку «я не робот»")
            tip("Поиск не нашёлся автоматически? Укажите шаблон с {query} в настройках сайта")
            tip("Позиция просмотра на сайте сохраняется автоматически")
            tip("Если сайт не открывается — KINORA предложит другой источник")
            tip("Видео с DRM-защитой проигрываются только на самом сайте")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
        }
    }

    private func addFromField() {
        guard !adding else { return }
        adding = true
        let text = urlText
        Task {
            if await store.addSite(text) { urlText = "" }
            adding = false
        }
    }

    private func addPreset(_ p: SourcePreset) {
        let src = VideoSource(name: p.name, baseURL: p.url, searchTemplate: p.search, category: p.category)
        if store.addSource(src) {
            store.showToast("\(p.name) добавлен")
            Task { await store.refreshFeed(src.id) }
        }
    }
}

struct SourceRow: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var router: AppRouter
    var source: VideoSource
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SourceIcon(source: source, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Text(source.baseURL).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                Text(store.indexing[source.id] ?? (store.refreshing.contains(source.id) ? "Сканирую…" : "\(max(store.items(of: source.id).count, store.indexCount(source.id))) тайтлов" + (source.searchTemplate.isEmpty ? " • без поиска" : " • поиск ✓")))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.items(of: source.id).isEmpty ? Theme.gold : Theme.accentSoft)
                if let c = source.category {
                    Text(c.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(c.tint)
                }
            }
            Spacer(minLength: 6)
            Button {
                var s = source
                s.isEnabled.toggle()
                store.updateSource(s)
            } label: { statusPill }
            .buttonStyle(.plain)
            Button(action: onEdit) {
                Image(systemName: "pencil").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            Button { store.deleteSource(source.id) } label: {
                Image(systemName: "trash").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .glass(radius: 18)
        .opacity(source.isEnabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture { router.push(.sourceFeed(source.id)) }
        .contextMenu {
            Button { router.push(.sourceFeed(source.id)) } label: { Label("Лента сайта", systemImage: "square.grid.2x2") }
            Button {
                if let url = URL(string: source.baseURL) {
                    router.webSession = WebSession(titleID: nil, season: 0, episode: 0, sourceID: source.id, url: url)
                }
            } label: { Label("Открыть сайт", systemImage: "globe") }
            Button { Task { await store.refreshFeed(source.id) } } label: { Label("Пересканировать", systemImage: "arrow.clockwise") }
            Button(action: onEdit) { Label("Изменить", systemImage: "pencil") }
        }
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            if !source.isEnabled { return ("Выключен", Theme.text3) }
            switch source.health {
            case .offline: return ("Офлайн", Theme.red)
            case .checking: return ("Проверка", Theme.gold)
            default: return ("Активен", Theme.green)
            }
        }()
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct SourceEditView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State var source: VideoSource

    var body: some View {
        NavigationStack {
            Form {
                Section("Сайт") {
                    TextField("Название", text: $source.name)
                    TextField("Адрес (https://…)", text: $source.baseURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Включён", isOn: $source.isEnabled)
                }
                Section {
                    TextField("https://site.com/search?q={query}", text: $source.searchTemplate)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Шаблон поиска") } footer: {
                    Text("Откройте поиск на сайте, скопируйте адрес страницы результатов и замените текст запроса на {query}.")
                }
                Section("Категория") {
                    Picker("Категория", selection: $source.category) {
                        Text("Любая").tag(ContentType?.none)
                        ForEach(store.visibleTypes) { Text($0.title).tag(ContentType?.some($0)) }
                    }
                    TextField("Заметка (качество, озвучка…)", text: $source.note)
                }
                Section {
                    Button("Пересканировать сайт") {
                        store.updateSource(source)
                        Task { await store.refreshFeed(source.id); if let s = store.source(source.id) { source.health = s.health; source.searchTemplate = s.searchTemplate } }
                    }
                    HStack {
                        Text("Статус")
                        Spacer()
                        HealthDot(health: store.source(source.id)?.health ?? source.health)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Источник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if !source.baseURL.lowercased().hasPrefix("http") { source.baseURL = "https://" + source.baseURL }
                        store.updateSource(source)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
