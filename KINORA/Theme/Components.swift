import SwiftUI

// MARK: - Logo

struct KinoraLogo: View {
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                PlayTriangle()
                    .fill(LinearGradient(colors: [Color(hex: 0x6D28D9), Color(hex: 0xA855F7), Color(hex: 0xC084FC)],
                                         startPoint: .bottomLeading, endPoint: .topTrailing))
                    .frame(width: size * 1.15, height: size * 1.25)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 8)
            }
            Text("KINORA")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Theme.logoGradient)
        }
    }
}

struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r: CGFloat = rect.width * 0.12
        let a = CGPoint(x: rect.minX, y: rect.minY)
        let b = CGPoint(x: rect.maxX, y: rect.midY)
        let c = CGPoint(x: rect.minX, y: rect.maxY)
        p.move(to: CGPoint(x: a.x, y: a.y + r))
        p.addArc(tangent1End: a, tangent2End: b, radius: r)
        p.addArc(tangent1End: b, tangent2End: c, radius: r)
        p.addArc(tangent1End: c, tangent2End: a, radius: r)
        p.closeSubpath()
        return p
    }
}

// MARK: - Buttons

struct CircleIconButton: View {
    var icon: String
    var tint: Color = .white
    var filled: Bool = false
    var badge: Bool = false
    var size: CGFloat = 44
    var action: () -> Void

    var body: some View {
        Button(action: { hapticTap(); action() }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(
                        Circle().fill(filled ? AnyShapeStyle(Theme.accentDeep.opacity(0.55)) : AnyShapeStyle(Color.white.opacity(0.08)))
                    )
                    .overlay(Circle().stroke(filled ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
                if badge {
                    Circle().fill(Theme.pink).frame(width: 9, height: 9).offset(x: -6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryButton: View {
    var title: String
    var subtitle: String? = nil
    var icon: String? = "play.fill"
    var height: CGFloat = 52
    var action: () -> Void

    var body: some View {
        Button(action: { hapticTap(.medium); action() }) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 18, weight: .bold)) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 16, weight: .bold))
                    if let subtitle { Text(subtitle).font(.system(size: 11, weight: .medium)).opacity(0.85) }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(Theme.accentGradient))
            .shadow(color: Theme.accent.opacity(0.45), radius: 14, y: 4)
        }
        .buttonStyle(PressableStyle())
    }
}

struct SecondaryButton: View {
    var title: String
    var icon: String? = nil
    var height: CGFloat = 52
    var action: () -> Void

    var body: some View {
        Button(action: { hapticTap(); action() }) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().stroke(Theme.stroke))
        }
        .buttonStyle(PressableStyle())
    }
}

struct SmallPlayButton: View {
    var title: String = "Смотреть"
    var prominent: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: { hapticTap(); action() }) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(Capsule().stroke(prominent ? Color.clear : Theme.stroke))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Chips

struct Chip: View {
    var title: String
    var icon: String? = nil
    var emoji: String? = nil
    var selected: Bool = false
    var tint: Color = Theme.accent
    var compact: Bool = false
    var showsCheck: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: compact ? 11 : 13, weight: .semibold)) }
            Text(title).font(.system(size: compact ? 12 : 14, weight: .medium))
            if let emoji, !emoji.isEmpty { Text(emoji).font(.system(size: compact ? 11 : 13)) }
            if showsCheck && selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
        }
        .foregroundStyle(selected ? .white : Theme.text.opacity(0.88))
        .padding(.horizontal, compact ? 10 : 14)
        .frame(height: compact ? 26 : 36)
        .background(
            Capsule().fill(selected ? AnyShapeStyle(tint.opacity(0.9)) : AnyShapeStyle(Color.white.opacity(0.06)))
        )
        .overlay(Capsule().stroke(selected ? tint : Theme.stroke, lineWidth: 1))
        .shadow(color: selected ? tint.opacity(0.4) : .clear, radius: 8)
    }
}

struct GenreTag: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

struct TypeBadge: View {
    var type: ContentType
    var body: some View {
        Text(type.singular)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accentDeep.opacity(0.85)))
    }
}

struct RatingBadge: View {
    var rating: Double
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.gold)
            Text(String(format: "%.1f", rating)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}

// MARK: - Section header

struct SectionHeader: View {
    var title: String
    var emoji: String? = nil
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                if let emoji { Text(emoji) }
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            }
            Spacer()
            if let action, let onAction {
                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Text(action)
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent2)
                }
            }
        }
        .padding(.horizontal, Theme.hPad)
    }
}

// MARK: - Progress bar

struct ProgressLine: View {
    var value: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Theme.accentGradient)
                    .frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, value)))))
                    .shadow(color: Theme.accent.opacity(0.6), radius: 4)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Poster

/// Постер: если есть URL — грузим картинку, иначе рисуем красивую градиентную заглушку.
struct PosterView: View {
    var title: MediaTitle
    var useBackdrop: Bool = false
    var showTitleOnPlaceholder: Bool = true

    var body: some View {
        let urlString = useBackdrop ? (title.backdropURL.isEmpty ? title.posterURL : title.backdropURL) : title.posterURL
        ZStack {
            placeholder
            if let url = ImageURL.resolve(urlString) {
                RemoteImage(url: url)
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: title.type.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.white.opacity(0.06)).frame(width: 160).offset(x: 50, y: -60)
            Circle().fill(Color.black.opacity(0.18)).frame(width: 120).offset(x: -60, y: 70)
            if showTitleOnPlaceholder {
                VStack(spacing: 6) {
                    Image(systemName: title.type.icon).font(.system(size: 22, weight: .semibold)).opacity(0.85)
                    Text(title.name)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 8)
                }
                .foregroundStyle(.white.opacity(0.92))
            }
        }
    }
}

enum ImageURL {
    static func resolve(_ s: String) -> URL? {
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        if s.hasPrefix("/") { return URL(string: "https://image.tmdb.org/t/p/w500\(s)") }
        return nil
    }
}

// MARK: - Search field

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void = {}
    var focused: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.text2)
            Group {
                if let focused {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.text3))
                        .focused(focused)
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.text3))
                }
            }
            .foregroundStyle(.white)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text2)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Theme.stroke))
    }
}

// MARK: - Stat tile

struct StatTile: View {
    var icon: String
    var iconColor: Color
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(iconColor)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glass(radius: 16)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    var icon: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(Theme.accent2)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(subtitle).font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glass()
        .padding(.horizontal, Theme.hPad)
    }
}

// MARK: - Toast

struct ToastView: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Theme.cardHi))
            .overlay(Capsule().stroke(Theme.accent.opacity(0.6)))
            .shadow(color: .black.opacity(0.4), radius: 12)
    }
}
