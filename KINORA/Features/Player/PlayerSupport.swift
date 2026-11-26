import SwiftUI
import AVKit
import MediaPlayer
import ReplayKit

// MARK: - Video surface

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var fill: Bool = false

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        return v
    }

    func updateUIView(_ v: PlayerLayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}

// MARK: - AirPlay

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Theme.accent2)
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - System volume (через скрытый MPVolumeView)

@MainActor
final class SystemVolume: ObservableObject {
    static let shared = SystemVolume()
    @Published var value: Float = AVAudioSession.sharedInstance().outputVolume
    weak var slider: UISlider?
    private var obs: NSKeyValueObservation?

    init() {
        obs = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] s, _ in
            let v = s.outputVolume
            Task { @MainActor in self?.value = v }
        }
    }

    func set(_ v: Float) {
        let clamped = min(1, max(0, v))
        value = clamped
        slider?.value = clamped
        slider?.sendActions(for: .valueChanged)
    }
}

struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 10, height: 10))
        v.alpha = 0.01
        DispatchQueue.main.async {
            SystemVolume.shared.slider = v.subviews.compactMap { $0 as? UISlider }.first
        }
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Brightness

enum Brightness {
    @MainActor static var current: CGFloat {
        get { (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.brightness ?? 0.5 }
        set { (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.brightness = min(1, max(0, newValue)) }
    }
}

// MARK: - Screen recording (ReplayKit)

@MainActor
final class ScreenRecorder: NSObject, ObservableObject, RPPreviewViewControllerDelegate {
    static let shared = ScreenRecorder()
    @Published var isRecording = false

    func toggle() {
        let rec = RPScreenRecorder.shared()
        guard rec.isAvailable else { return }
        if rec.isRecording {
            rec.stopRecording { [weak self] preview, _ in
                Task { @MainActor in
                    self?.isRecording = false
                    guard let preview else { return }
                    preview.previewControllerDelegate = self
                    preview.modalPresentationStyle = .fullScreen
                    Self.topController()?.present(preview, animated: true)
                }
            }
        } else {
            rec.isMicrophoneEnabled = false
            rec.startRecording { [weak self] error in
                Task { @MainActor in self?.isRecording = error == nil }
            }
        }
    }

    nonisolated func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        Task { @MainActor in previewController.dismiss(animated: true) }
    }

    static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }
}

// MARK: - Sliders

struct VerticalSlider: View {
    var value: Double
    var icon: String
    var onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Theme.accentGradient)
                        .frame(height: max(6, geo.size.height * CGFloat(value)))
                    Circle().fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(radius: 3)
                        .offset(y: -max(0, geo.size.height * CGFloat(value) - 9))
                }
                .frame(width: 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let v = 1 - Double(g.location.y / geo.size.height)
                    onChange(min(1, max(0, v)))
                })
            }
        }
        .padding(.vertical, 14)
        .frame(width: 44, height: 170)
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().stroke(Color.white.opacity(0.1)))
    }
}

struct Scrubber: View {
    var current: Double
    var duration: Double
    var onSeek: (Double) -> Void
    @Binding var dragging: Double?

    var body: some View {
        GeometryReader { geo in
            let shown = dragging ?? current
            let f = duration > 0 ? min(1, max(0, shown / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22)).frame(height: 4)
                Capsule().fill(Theme.accentGradient).frame(width: geo.size.width * f, height: 4)
                    .shadow(color: Theme.accent, radius: 4)
                Circle().fill(.white)
                    .frame(width: dragging == nil ? 16 : 22, height: dragging == nil ? 16 : 22)
                    .overlay(Circle().stroke(Theme.accent2, lineWidth: 3))
                    .offset(x: geo.size.width * f - (dragging == nil ? 8 : 11))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard duration > 0 else { return }
                    dragging = min(1, max(0, g.location.x / geo.size.width)) * duration
                }
                .onEnded { _ in
                    if let d = dragging { onSeek(d) }
                    dragging = nil
                })
        }
        .frame(height: 26)
    }
}
