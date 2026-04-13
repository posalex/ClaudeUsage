import SwiftUI
import ServiceManagement

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(L.claudeUsage, id: "main") {
            ContentView(fetcher: appDelegate.fetcher)
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
                .onReceive(appDelegate.$shouldOpenWindow) { shouldOpen in
                    guard shouldOpen else { return }
                    appDelegate.shouldOpenWindow = false
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 520, height: 740)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            MenuBarView(fetcher: appDelegate.fetcher, openMainWindow: {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            })
        } label: {
            MenuBarLabel(fetcher: appDelegate.fetcher)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Observes both the fetcher's data and the display toggle preferences,
/// so the menu bar label updates when either changes.
struct MenuBarLabel: View {
    @ObservedObject var fetcher: UsageFetcher

    @AppStorage(SharedDefaults.languageKey) private var _lang = AppLanguage.english.rawValue
    @AppStorage(SharedDefaults.menuBarShowSessionPercentKey) private var _sp = true
    @AppStorage(SharedDefaults.menuBarShowSessionResetKey) private var _sr = true
    @AppStorage(SharedDefaults.menuBarShowWeeklyPercentKey) private var _wp = false
    @AppStorage(SharedDefaults.menuBarShowWeeklyResetKey) private var _wr = false
    @AppStorage(SharedDefaults.menuBarShowSonnetPercentKey) private var _snp = false
    @AppStorage(SharedDefaults.menuBarShowSonnetResetKey) private var _snr = false

    var body: some View {
        let _ = (_lang, _sp, _sr, _wp, _wr, _snp, _snr)
        let label = fetcher.usageData.menuBarLabel()
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
                .imageScale(.small)
            Text(label)
                .monospacedDigit()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let fetcher = UsageFetcher()
    @Published var shouldOpenWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if fetcher.isLoggedIn {
            NSApp.setActivationPolicy(.accessory)
            fetcher.startAutoRefresh()
        } else {
            NSApp.setActivationPolicy(.regular)
            // Signal the SwiftUI view to open the window.
            // Using @Published ensures it works even if the view
            // subscribes after this point — onReceive will fire
            // when the view appears and reads the current value.
            shouldOpenWindow = true
        }
    }
}
