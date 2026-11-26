import Foundation

/// Первый запуск: никаких демо-тайтлов, прогресса и истории.
/// Только пара стартовых тегов — их можно удалить.
enum SeedData {
    static func make() -> AppData {
        var d = AppData()
        d.tags = [
            UserTag(name: "Любимые", emoji: "💜", colorHex: 0xA855F7),
            UserTag(name: "Посмотреть позже", emoji: "🕒", colorHex: 0x60A5FA),
            UserTag(name: "С друзьями", emoji: "🍿", colorHex: 0xFBBF24),
        ]
        return d
    }
}
