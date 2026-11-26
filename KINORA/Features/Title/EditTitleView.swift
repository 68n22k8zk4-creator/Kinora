import SwiftUI

/// Добавление / редактирование тайтла вручную
struct EditTitleView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss

    var existing: MediaTitle?
    var defaultType: ContentType

    @State private var t = MediaTitle(name: "", type: .movie)
    @State private var altNamesText = ""
    @State private var genresText = ""
    @State private var seasonsCount = 1
    @State private var episodesPerSeason = 12
    @State private var urlPattern = ""
    @State private var showAdultGate = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    TextField("Название", text: $t.name)
                    TextField("Оригинальное название", text: $t.originalName)
                    TextField("Альтернативные названия (через запятую)", text: $altNamesText)
                    Picker("Тип", selection: $t.type) {
                        ForEach(store.visibleTypes) { Text($0.singular).tag($0) }
                    }
                    Stepper("Год: \(t.year == 0 ? "—" : String(t.year))", value: $t.year, in: 0...2100)
                    if t.type != .movie {
                        Toggle("Завершён", isOn: Binding(get: { t.endYear != nil }, set: { t.endYear = $0 ? max(t.year, 1900) : nil }))
                        if t.endYear != nil {
                            Stepper("Год окончания: \(t.endYear ?? 0)", value: Binding(get: { t.endYear ?? t.year }, set: { t.endYear = $0 }), in: 1900...2100)
                        }
                    }
                    Stepper("Длительность: \(t.durationMinutes) мин.", value: $t.durationMinutes, in: 0...600, step: 1)
                    TextField("Возраст (например 16+)", text: $t.ageRating)
                    TextField("Жанры (через запятую)", text: $genresText)
                }

                Section("Описание и постеры") {
                    TextEditor(text: $t.overview).frame(minHeight: 90)
                    TextField("URL постера", text: $t.posterURL).keyboardType(.URL).textInputAutocapitalization(.never)
                    TextField("URL баннера", text: $t.backdropURL).keyboardType(.URL).textInputAutocapitalization(.never)
                }

                Section("Рейтинги") {
                    HStack {
                        Text("Рейтинг")
                        Slider(value: $t.rating, in: 0...10, step: 0.1)
                        Text(String(format: "%.1f", t.rating)).monospacedDigit()
                    }
                    HStack {
                        Text("IMDb")
                        Slider(value: $t.imdbRating, in: 0...10, step: 0.1)
                        Text(String(format: "%.1f", t.imdbRating)).monospacedDigit()
                    }
                }

                if t.type == .movie {
                    Section {
                        TextField("Прямая ссылка на видео (mp4 / m3u8)", text: $t.videoURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never)
                    } header: { Text("Видео") } footer: {
                        Text("Необязательно. Без ссылки фильм открывается через подключённый источник.")
                    }
                } else {
                    Section {
                        if t.seasons.isEmpty {
                            Stepper("Сезонов: \(seasonsCount)", value: $seasonsCount, in: 1...50)
                            Stepper("Серий в сезоне: \(episodesPerSeason)", value: $episodesPerSeason, in: 1...2000)
                            TextField("Шаблон ссылки, напр. https://site/s{s}e{e}.mp4", text: $urlPattern)
                                .keyboardType(.URL).textInputAutocapitalization(.never)
                            Button("Создать сезоны") { generateSeasons() }
                        } else {
                            ForEach($t.seasons) { $season in
                                NavigationLink {
                                    EpisodesEditor(season: $season)
                                } label: {
                                    HStack {
                                        Text("\(season.number) сезон")
                                        Spacer()
                                        Text("\(season.episodes.count) серий").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .onDelete { t.seasons.remove(atOffsets: $0) }
                            Button("Добавить сезон") {
                                let n = (t.seasons.map(\.number).max() ?? 0) + 1
                                t.seasons.append(Season(number: n, episodes: (1...episodesPerSeason).map { Episode(number: $0, name: "Серия \($0)") }))
                            }
                        }
                    } header: { Text("Сезоны и серии") } footer: {
                        Text("Ссылки на серии необязательны: {s} — номер сезона, {e} — номер серии.")
                    }
                }

                if !store.enabledSources.isEmpty {
                    Section {
                        ForEach(store.sortedSources) { s in
                            TextField(s.name, text: Binding(
                                get: { t.sourceLinks[s.id.uuidString] ?? "" },
                                set: { t.sourceLinks[s.id.uuidString] = $0.isEmpty ? nil : $0 }))
                            .keyboardType(.URL).textInputAutocapitalization(.never)
                        }
                    } header: { Text("Страница тайтла на источниках") } footer: {
                        Text("Если указать — «Смотреть» откроет сразу эту страницу, а не поиск по сайту.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(existing == nil ? "Новый тайтл" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(t.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        if let existing {
            t = existing
        } else if t.name.isEmpty {
            t = MediaTitle(name: "", type: defaultType)
            t.year = Calendar.current.component(.year, from: Date())
        }
        altNamesText = t.altNames.joined(separator: ", ")
        genresText = t.genres.joined(separator: ", ")
    }

    private func generateSeasons() {
        t.seasons = (1...seasonsCount).map { s in
            Season(number: s, episodes: (1...episodesPerSeason).map { e in
                Episode(number: e, name: "Серия \(e)",
                        videoURL: urlPattern.isEmpty ? "" : urlPattern.replacingOccurrences(of: "{s}", with: "\(s)").replacingOccurrences(of: "{e}", with: "\(e)"))
            })
        }
    }

    private func save() {
        t.altNames = altNamesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        t.genres = genresText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if t.type != .movie && t.seasons.isEmpty { generateSeasons() }
        store.upsert(t)
        store.showToast(existing == nil ? "Тайтл добавлен" : "Сохранено")
        dismiss()
    }
}

struct EpisodesEditor: View {
    @Binding var season: Season

    var body: some View {
        Form {
            Section {
                ForEach($season.episodes) { $ep in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(ep.number).").foregroundStyle(.secondary)
                            TextField("Название серии", text: $ep.name)
                        }
                        TextField("Ссылка на видео (необязательно)", text: $ep.videoURL)
                            .font(.footnote)
                            .keyboardType(.URL).textInputAutocapitalization(.never)
                    }
                }
                .onDelete { season.episodes.remove(atOffsets: $0) }
                Button("Добавить серию") {
                    let n = (season.episodes.map(\.number).max() ?? 0) + 1
                    season.episodes.append(Episode(number: n, name: "Серия \(n)"))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("\(season.number) сезон")
    }
}

// MARK: - Tag picker

struct TagPickerSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let titleID: UUID
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        let selected = store.title(titleID)?.tagIDs ?? []
                        FlowLayout(spacing: 8) {
                            ForEach(store.data.tags) { tag in
                                Button { hapticTap(); store.toggleTag(tag.id, on: titleID) } label: {
                                    Chip(title: tag.name, emoji: tag.emoji, selected: selected.contains(tag.id), tint: tag.color, showsCheck: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button { showNew = true } label: {
                            Label("Новый тег", systemImage: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent2)
                        }
                    }
                    .padding(Theme.hPad)
                }
            }
            .navigationTitle("Теги")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .sheet(isPresented: $showNew) { NewTagSheet().environmentObject(store) }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

struct NewTagSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    var editing: UserTag? = nil
    @State private var name = ""
    @State private var emoji = "💜"
    @State private var color: UInt32 = 0xA855F7

    static let palette: [UInt32] = [0xA855F7, 0x8B5CF6, 0xEC4899, 0xF43F5E, 0xF97316, 0xFBBF24, 0x4ADE80, 0x22D3EE, 0x60A5FA, 0x94A3B8]
    static let emojis = ["💜", "🔥", "⭐️", "🍿", "🎬", "📺", "🌸", "😂", "😱", "💀", "🧠", "❤️", "✅", "🚫", "🎞️", "🐉", "👀", "🌙"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") { TextField("Например: На выходные", text: $name) }
                Section("Эмодзи") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Text(e).font(.system(size: 26))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(emoji == e ? Theme.accent.opacity(0.4) : .clear))
                                .onTapGesture { emoji = e }
                        }
                    }
                    TextField("Своё эмодзи", text: $emoji)
                }
                Section("Цвет") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Self.palette, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 36, height: 36)
                                .overlay(Circle().stroke(.white, lineWidth: color == c ? 3 : 0))
                                .onTapGesture { color = c }
                        }
                    }
                }
                Section {
                    HStack { Text("Превью"); Spacer(); Chip(title: name.isEmpty ? "Тег" : name, emoji: emoji, selected: true, tint: Color(hex: color)) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(editing == nil ? "Новый тег" : "Изменить тег")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if let editing, let i = store.data.tags.firstIndex(where: { $0.id == editing.id }) {
                            store.data.tags[i].name = n
                            store.data.tags[i].emoji = String(emoji.prefix(2))
                            store.data.tags[i].colorHex = color
                            dismiss()
                        } else if store.addTag(name: n, emoji: String(emoji.prefix(2)), colorHex: color) {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let editing { name = editing.name; emoji = editing.emoji; color = editing.colorHex }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Collection picker

struct CollectionPickerSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let titleID: UUID
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.data.collections) { c in
                        Button { store.toggle(titleID, inCollection: c.id) } label: {
                            HStack {
                                Text(c.emoji)
                                Text(c.name).foregroundStyle(.white)
                                Spacer()
                                if c.titleIDs.contains(titleID) { Image(systemName: "checkmark").foregroundStyle(Theme.accent2) }
                            }
                        }
                    }
                }
                Section("Новая коллекция") {
                    HStack {
                        TextField("Название", text: $newName)
                        Button("Создать") {
                            if store.addCollection(name: newName, emoji: "📁"), let c = store.data.collections.last {
                                store.toggle(titleID, inCollection: c.id)
                                newName = ""
                            }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Коллекции")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
