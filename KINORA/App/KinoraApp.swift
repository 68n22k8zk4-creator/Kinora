import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

enum Orientation {
    @MainActor
    static func set(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        var vc = scene.windows.first { $0.isKeyWindow }?.rootViewController ?? scene.windows.first?.rootViewController
        while let current = vc {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = current.presentedViewController
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

@main
struct KinoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = LibraryStore()
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(PlayerManager.shared)
                .environmentObject(DownloadManager.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.accent2)
                .onAppear {
                    PlayerManager.shared.store = store
                    DownloadManager.shared.store = store
                    configureAppearance()
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                PlayerManager.shared.saveProgress(force: true)
                store.saveNow()
            }
        }
    }

    private func configureAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UITableView.appearance().backgroundColor = .clear
    }
}

// MARK: - Router

enum AppTab: Int, CaseIterable {
    case home, catalog, library, plus, profile

    var title: String {
        switch self {
        case .home: return "Главная"
        case .catalog: return "Каталог"
        case .library: return "Мои"
        case .plus: return "Подписка"
        case .profile: return "Профиль"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .catalog: return "safari"
        case .library: return "bookmark"
        case .plus: return "crown"
        case .profile: return "person"
        }
    }

    var iconSelected: String {
        switch self {
        case .home: return "house.fill"
        case .catalog: return "safari.fill"
        case .library: return "bookmark.fill"
        case .plus: return "crown.fill"
        case .profile: return "person.fill"
        }
    }
}

enum Route: Hashable {
    case title(UUID)
    case item(SiteItem)
    case sourceFeed(UUID)
    case sitePage(UUID, String, String)   // источник, название раздела, адрес
    case search(String)
    case sources
    case settings
    case plus
    case collection(UUID)
    case tag(UUID)
    case tagsManager
    case history
    case downloads
    case stats
    case backup
    case about
    case list(String, ListFilter)
}

enum ListFilter: Hashable {
    case status(WatchStatus)
    case favorites
    case bookmarks
    case type(ContentType)
    case trending
    case recent
}

struct WebSession: Identifiable {
    let id = UUID()
    /// nil — свободный просмотр сайта; тайтл создаётся, когда начнётся видео
    var titleID: UUID?
    var season: Int
    var episode: Int
    var sourceID: UUID
    var url: URL
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var homePath = NavigationPath()
    @Published var catalogPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var plusPath = NavigationPath()
    @Published var profilePath = NavigationPath()
    @Published var webSession: WebSession? = nil
    @Published var showNotifications = false
    @Published var catalogType: ContentType? = nil

    func push(_ route: Route) {
        switch tab {
        case .home: homePath.append(route)
        case .catalog: catalogPath.append(route)
        case .library: libraryPath.append(route)
        case .plus: plusPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func openCatalog(_ type: ContentType?) {
        catalogType = type
        tab = .catalog
    }
}

// MARK: - Свайп «назад» при скрытой навигационной панели

extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
