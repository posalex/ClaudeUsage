import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var fetcher: UsageFetcher
    var openMainWindow: () -> Void

    /// nil = "do not show", otherwise the selected chart period
    @AppStorage(SharedDefaults.menuBarChartPeriodKey)
    private var menuBarChartPeriodRaw: String = ""

    // Observe language changes so the view re-renders
    @AppStorage(SharedDefaults.languageKey)
    private var languageRaw: String = AppLanguage.english.rawValue

    private var menuBarChartPeriod: ChartPeriod? {
        menuBarChartPeriodRaw.isEmpty ? nil : ChartPeriod(rawValue: menuBarChartPeriodRaw)
    }

    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if fetcher.isLoggedIn {
                usageSection
            } else {
                notLoggedInSection
            }

            if let period = menuBarChartPeriod, fetcher.isLoggedIn {
                sectionDivider
                MenuBarChartView(period: period, lastUpdated: fetcher.usageData.lastUpdated)
                    .padding(.horizontal, 12)
            }

            sectionDivider

            menuButton(L.settings, icon: "gear", shortcut: ",") {
                openMainWindow()
            }
            menuButton(L.usageOnClaude, icon: "safari", shortcut: "U") {
                if let url = URL(string: "https://claude.ai/settings/usage") {
                    NSWorkspace.shared.open(url)
                }
            }
            menuButton(L.refreshNow, icon: "arrow.clockwise", shortcut: "R") {
                Task { await fetcher.fetchUsage() }
            }
            .opacity(fetcher.isFetching ? 0.5 : 1)

            sectionDivider

            Toggle(isOn: $launchAtLogin) {
                Text(L.launchAtLogin)
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = !enabled
                }
            }

            if fetcher.isLoggedIn {
                sectionDivider
                menuButton(L.logout, icon: "rectangle.portrait.and.arrow.right", shortcut: "L") {
                    fetcher.logout()
                }
            } else {
                sectionDivider
                menuButton(L.logIn, icon: "person.crop.circle", shortcut: "L") {
                    openMainWindow()
                }
            }

            sectionDivider

            menuButton(L.quit, icon: "xmark.circle", shortcut: "Q") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 280)
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Divider().padding(.vertical, 4).padding(.horizontal, 8)
    }

    private func menuButton(_ title: String, icon: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
                Text("⌘\(shortcut)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(shortcut.first ?? "?"), modifiers: .command)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Usage Section

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            usageBlock(
                title: L.sessionTitle,
                reset: fetcher.usageData.sessionResetCompact,
                percent: fetcher.usageData.sessionPercent,
                color: .blue
            )

            usageBlock(
                title: L.weeklyTitle,
                reset: fetcher.usageData.weeklyResetCompact,
                percent: fetcher.usageData.weeklyPercent,
                color: .blue
            )

            if let sonnet = fetcher.usageData.weeklySonnetPercent {
                usageBlock(
                    title: L.sonnetTitle,
                    reset: fetcher.usageData.sonnetResetCompact ?? "--",
                    percent: sonnet,
                    color: .purple
                )
            }

            if fetcher.usageData.isLoggedIn {
                Text("\(L.updated): \(fetcher.usageData.lastUpdated.formatted(.dateTime.hour().minute()))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
            }
        }
    }

    private func usageBlock(title: String, reset: String, percent: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(L.resetIn) \(reset)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 18)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(percent: percent, base: color))
                        .frame(width: max(0, geo.size.width * CGFloat(percent / 100.0)), height: 18)
                }
                .frame(height: 18)

                HStack {
                    Text("\(Int(percent))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(percent > 45 ? .white : .primary)
                        .padding(.leading, 8)
                    Spacer()
                }
            }
            .frame(height: 18)
            .padding(.horizontal, 12)
        }
    }

    private func barColor(percent: Double, base: Color) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return base
    }

    // MARK: - Not Logged In

    private var notLoggedInSection: some View {
        VStack(spacing: 4) {
            Text(L.notLoggedIn)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(L.openAppToLogIn)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
