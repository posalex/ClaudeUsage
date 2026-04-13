import SwiftUI
import WebKit
import ServiceManagement

struct ContentView: View {
    @ObservedObject var fetcher: UsageFetcher
    @State private var showLoginSheet = false

    // Observe language changes so the view re-renders when language switches
    @AppStorage(SharedDefaults.languageKey) private var languageRaw: String = AppLanguage.english.rawValue

    /// The language at launch — used to detect if user switched language mid-session
    @State private var initialLanguage: String = UserDefaults.standard.string(forKey: SharedDefaults.languageKey) ?? AppLanguage.english.rawValue

    private var languageChanged: Bool { languageRaw != initialLanguage }

    // Menu bar display settings (moved from MenuBarView)
    @AppStorage(SharedDefaults.menuBarShowSessionPercentKey)
    private var showSessionPercent: Bool = true
    @AppStorage(SharedDefaults.menuBarShowSessionResetKey)
    private var showSessionReset: Bool = true
    @AppStorage(SharedDefaults.menuBarShowWeeklyPercentKey)
    private var showWeeklyPercent: Bool = false
    @AppStorage(SharedDefaults.menuBarShowWeeklyResetKey)
    private var showWeeklyReset: Bool = false
    @AppStorage(SharedDefaults.menuBarShowSonnetPercentKey)
    private var showSonnetPercent: Bool = false
    @AppStorage(SharedDefaults.menuBarShowSonnetResetKey)
    private var showSonnetReset: Bool = false

    // Menu bar chart period
    @AppStorage(SharedDefaults.menuBarChartPeriodKey)
    private var menuBarChartPeriodRaw: String = ""

    // Refresh interval
    @AppStorage(SharedDefaults.refreshIntervalKey)
    private var refreshInterval: Int = 5

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Scrollable content: settings on top, usage + chart below
            ScrollView {
                VStack(spacing: 20) {
                    settingsSection
                    if fetcher.isLoggedIn || fetcher.lastError != nil {
                        usageDashboard
                    } else {
                        welcomeState
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showLoginSheet) {
            LoginSheetView(fetcher: fetcher, isPresented: $showLoginSheet)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.claudeUsage)
                    .font(.system(size: 18, weight: .semibold))

                if fetcher.isLoggedIn {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text(L.connected)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text(L.notLoggedIn)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if fetcher.isLoggedIn {
                Button(action: {
                    Task { await fetcher.fetchUsage() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(fetcher.isFetching ? 360 : 0))
                        .animation(fetcher.isFetching ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: fetcher.isFetching)
                }
                .buttonStyle(.borderless)
                .disabled(fetcher.isFetching)

                Button(L.logout) {
                    fetcher.logout()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(L.logIn) {
                    showLoginSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.settingsTitle)
                .font(.headline)

            // Language
            settingRow(L.language) {
                VStack(alignment: .leading, spacing: 8) {
                    languagePicker

                    if languageChanged {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)
                                .font(.system(size: 11))
                            Text(L.restartToApply)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(L.restartNow) {
                                restartApp()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }

            // Refresh interval
            settingRow(L.refreshInterval) {
                refreshIntervalPicker
            }

            // Menu bar chart
            settingRow(L.usageChart) {
                chartPeriodPicker
            }

            // Menu bar display toggles
            VStack(alignment: .leading, spacing: 8) {
                Text(L.menuBarDisplay)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ], spacing: 6) {
                    displayToggle(L.sessionPercent, isOn: $showSessionPercent)
                    displayToggle(L.sessionResetTime, isOn: $showSessionReset)
                    displayToggle(L.weeklyPercent, isOn: $showWeeklyPercent)
                    displayToggle(L.weeklyResetTime, isOn: $showWeeklyReset)
                    displayToggle(L.sonnetPercent, isOn: $showSonnetPercent)
                    displayToggle(L.sonnetResetTime, isOn: $showSonnetReset)
                }
            }

            // Org info
            if let orgUUID = SharedDefaults.loadOrgUUID() {
                HStack {
                    Text(L.org)
                        .foregroundStyle(.secondary)
                    Text(orgUUID)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func displayToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 12))
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Restart

    private func restartApp() {
        // Launch a new instance of the app, then terminate the current one
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.launch()
        // Give the new instance a moment to launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Language Picker

    private var languagePicker: some View {
        HStack(spacing: 1) {
            ForEach(AppLanguage.allCases, id: \.self) { lang in
                pillButton(
                    label: "\(lang.flag) \(lang.rawValue.uppercased())",
                    isSelected: languageRaw == lang.rawValue
                ) {
                    languageRaw = lang.rawValue
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
    }

    // MARK: - Refresh Interval Picker

    private static let refreshOptions: [(String, Int)] = [("1m", 1), ("2m", 2), ("5m", 5), ("10m", 10), ("15m", 15), ("30m", 30)]

    private var refreshIntervalPicker: some View {
        HStack(spacing: 1) {
            ForEach(Self.refreshOptions, id: \.1) { label, minutes in
                pillButton(label: label, isSelected: refreshInterval == minutes) {
                    refreshInterval = minutes
                    SharedDefaults.saveRefreshInterval(minutes)
                    fetcher.restartAutoRefresh()
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
    }

    // MARK: - Chart Period Picker

    private var chartPeriodPicker: some View {
        HStack(spacing: 1) {
            pillButton(label: L.off, isSelected: menuBarChartPeriodRaw.isEmpty) {
                menuBarChartPeriodRaw = ""
            }
            ForEach(ChartPeriod.allCases, id: \.self) { period in
                pillButton(label: period.rawValue, isSelected: menuBarChartPeriodRaw == period.rawValue) {
                    menuBarChartPeriodRaw = period.rawValue
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
    }

    // MARK: - Pill Button

    private func pillButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.blue : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Welcome State

    private var welcomeState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(L.logInToSeeUsage)
                .font(.headline)
                .foregroundStyle(.secondary)

            Button(L.logInToClaude) {
                showLoginSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Usage Dashboard

    private var usageDashboard: some View {
        VStack(spacing: 16) {
            // Error banner
            if let error = fetcher.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    if !fetcher.isLoggedIn {
                        Button(L.logIn) {
                            showLoginSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .background(.orange.opacity(0.1))
                .cornerRadius(8)
            }

            // Usage bars
            VStack(spacing: 16) {
                UsageBarView(
                    title: L.sessionTitle,
                    percent: fetcher.usageData.sessionPercent,
                    resetLabel: fetcher.usageData.sessionResetLabel,
                    color: .blue
                )

                UsageBarView(
                    title: L.weeklyTitle,
                    percent: fetcher.usageData.weeklyPercent,
                    resetLabel: fetcher.usageData.weeklyResetLabel,
                    color: .blue
                )

                if let sonnetPercent = fetcher.usageData.weeklySonnetPercent {
                    UsageBarView(
                        title: L.sonnetTitle,
                        percent: sonnetPercent,
                        resetLabel: fetcher.usageData.weeklySonnetResetLabel ?? "--",
                        color: .purple
                    )
                }
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)

            // Last updated
            if fetcher.usageData.isLoggedIn {
                Text("\(L.updated): \(fetcher.usageData.lastUpdated.formatted(.dateTime.hour().minute().second()))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Usage history chart
            UsageChartView(fetcher: fetcher)
        }
    }
}

// MARK: - Usage Bar

struct UsageBarView: View {
    let title: String
    let percent: Double
    let resetLabel: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text("\(Int(percent))%")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * CGFloat(percent / 100.0)), height: 8)
                        .animation(.easeInOut(duration: 0.5), value: percent)
                }
            }
            .frame(height: 8)

            Text(resetLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var barColor: Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return color
    }
}

// MARK: - Login Sheet

enum LoginMethod {
    case chooser
    case webView
    case browserCookie
}

struct LoginSheetView: View {
    let fetcher: UsageFetcher
    @Binding var isPresented: Bool
    @State private var loginMethod: LoginMethod = .chooser
    @State private var loginStatus: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Sheet header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.logInToClaude)
                        .font(.headline)
                    if !loginStatus.isEmpty {
                        Text(loginStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if loginMethod != .chooser {
                    Button(L.back) {
                        withAnimation { loginMethod = .chooser }
                        loginStatus = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(L.cancel) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            switch loginMethod {
            case .chooser:
                loginChooser
            case .webView:
                webViewLogin
            case .browserCookie:
                BrowserCookieLoginView(fetcher: fetcher, isPresented: $isPresented, loginStatus: $loginStatus)
            }
        }
        .frame(width: 800, height: loginMethod == .chooser ? 340 : 700)
        .animation(.easeInOut(duration: 0.2), value: loginMethod)
    }

    // MARK: - Method Chooser

    private var loginChooser: some View {
        VStack(spacing: 20) {
            Spacer()

            Text(L.chooseLoginMethod)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                // Option 1: Built-in WebView
                LoginOptionCard(
                    icon: "globe",
                    title: L.signInHere,
                    description: L.signInHereDesc,
                    action: {
                        withAnimation { loginMethod = .webView }
                        loginStatus = L.pleaseLogIn
                    }
                )

                // Option 2: Browser Cookie Import
                LoginOptionCard(
                    icon: "safari",
                    title: L.importFromBrowser,
                    description: L.importFromBrowserDesc,
                    action: {
                        withAnimation { loginMethod = .browserCookie }
                    }
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(.vertical, 20)
    }

    // MARK: - WebView Login

    private var webViewLogin: some View {
        LoginWebView(fetcher: fetcher, onLoginDetected: {
            loginStatus = L.loginSuccessful
            Task {
                await fetcher.fetchUsage()
                fetcher.startAutoRefresh()
                try? await Task.sleep(nanoseconds: 500_000_000)
                isPresented = false
            }
        }, onStatusUpdate: { status in
            loginStatus = status
        })
    }
}

// MARK: - Login Option Card

struct LoginOptionCard: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: isHovering ? .blue.opacity(0.3) : .clear, radius: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Browser Cookie Import

struct BrowserCookieLoginView: View {
    let fetcher: UsageFetcher
    @Binding var isPresented: Bool
    @Binding var loginStatus: String
    @State private var cookieText: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Step 1
                stepView(number: 1, title: L.openClaudeInBrowser) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.logInWithSSO)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button(action: {
                            if let url = URL(string: "https://claude.ai") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.up.forward.app")
                                Text(L.openInBrowser)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Step 2
                stepView(number: 2, title: L.copyCookies) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.copyInstructions)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            instructionRow("1.", "Press \u{2325}\u{2318}I (Option+Cmd+I) to open Developer Tools")
                            instructionRow("2.", "Go to the Network tab, reload the page (\u{2318}R)")
                            instructionRow("3.", "Click any request to claude.ai")
                            instructionRow("4.", "Copy the \"Cookie\" header value, or right-click the request and copy as cURL")
                        }

                        Text(L.cookieTip)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }

                // Step 3
                stepView(number: 3, title: L.pasteCookiesBelow) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.pasteCookiePrompt)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $cookieText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading, content: {
                                if cookieText.isEmpty {
                                    Text("sessionKey=sk-ant-...; ...")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .padding(6)
                                        .allowsHitTesting(false)
                                }
                            })

                        if showError {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        HStack {
                            Spacer()
                            Button(action: importCookies) {
                                HStack {
                                    Image(systemName: "checkmark.circle")
                                    Text(L.connect)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(cookieText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func stepView(number: Int, title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                content()
            }
        }
    }

    private func instructionRow(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Parse the pasted text into a flat cookie header string.
    /// Supports:
    ///   - Flat header: "key1=value1; key2=value2"
    ///   - JSON object: {"key1": "value1", "key2": "value2"}
    ///   - Nested JSON (browser dev tools): {"Anfrage-Cookies": {"key1": "value1", ...}}
    ///                                  or  {"Request Cookies": {"key1": "value1", ...}}
    private func parseCookieHeader(from text: String) -> (header: String, orgUUID: String?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var cookieDict: [String: String]?

        // Try JSON parsing first
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // Check for nested format: {"Some-Header": {"key": "value"}}
            // The outer key could be in any language (e.g. "Anfrage-Cookies", "Request Cookies")
            if let firstValue = json.values.first as? [String: Any],
               json.count == 1,
               firstValue["sessionKey"] != nil || firstValue.count > 3 {
                // Nested format — use the inner dict
                cookieDict = firstValue.compactMapValues { value in
                    if let str = value as? String { return str }
                    // Handle non-string values (e.g. JSON objects stored as cookie values)
                    if let jsonValue = value as? [String: Any],
                       let jsonData = try? JSONSerialization.data(withJSONObject: jsonValue),
                       let jsonStr = String(data: jsonData, encoding: .utf8) {
                        return jsonStr
                    }
                    return "\(value)"
                }
            } else {
                // Flat JSON: {"key": "value", ...}
                cookieDict = json.compactMapValues { value in
                    if let str = value as? String { return str }
                    if let jsonValue = value as? [String: Any],
                       let jsonData = try? JSONSerialization.data(withJSONObject: jsonValue),
                       let jsonStr = String(data: jsonData, encoding: .utf8) {
                        return jsonStr
                    }
                    return "\(value)"
                }
            }
        }

        var orgUUID: String? = nil

        if let dict = cookieDict {
            // Extract org UUID from lastActiveOrg cookie if present
            orgUUID = dict["lastActiveOrg"]
            // Build flat cookie header from parsed dict
            let header = dict.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            return (header, orgUUID)
        }

        // Not JSON — treat as a flat cookie header string
        guard trimmed.contains("=") else { return nil }

        // Try to extract lastActiveOrg from flat string
        let parts = trimmed.components(separatedBy: "; ")
        for part in parts {
            let kv = part.components(separatedBy: "=")
            if kv.count >= 2, kv[0].trimmingCharacters(in: .whitespaces) == "lastActiveOrg" {
                orgUUID = kv[1].trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return (trimmed, orgUUID)
    }

    private func importCookies() {
        let trimmed = cookieText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            showError = true
            errorMessage = L.pasteCookieError
            return
        }

        guard let parsed = parseCookieHeader(from: trimmed) else {
            showError = true
            errorMessage = L.parseCookieError
            return
        }

        showError = false
        loginStatus = L.validatingSession

        // Store the cookie header
        SharedDefaults.saveCookieHeader(parsed.header)

        // If we found the org UUID in the cookies, store it directly
        if let orgUUID = parsed.orgUUID {
            SharedDefaults.saveOrgUUID(orgUUID)
        }

        // Try to fetch usage to validate the cookies work
        Task {
            await fetcher.fetchUsage()
            if fetcher.isLoggedIn {
                loginStatus = L.connected
                fetcher.startAutoRefresh()
                try? await Task.sleep(nanoseconds: 500_000_000)
                isPresented = false
            } else {
                SharedDefaults.clearCookieHeader()
                SharedDefaults.saveOrgUUID(nil)
                showError = true
                errorMessage = fetcher.lastError ?? L.couldNotAuth
                loginStatus = ""
            }
        }
    }
}

// MARK: - Login WebView

struct LoginWebView: NSViewRepresentable {
    let fetcher: UsageFetcher
    let onLoginDetected: () -> Void
    let onStatusUpdate: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.startObserving(webView)

        // Load claude.ai login page
        if let url = URL(string: "https://claude.ai/login") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(fetcher: fetcher, onLoginDetected: onLoginDetected, onStatusUpdate: onStatusUpdate)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let fetcher: UsageFetcher
        let onLoginDetected: () -> Void
        let onStatusUpdate: (String) -> Void
        weak var webView: WKWebView?
        private var hasDetectedLogin = false
        private var urlObservation: NSKeyValueObservation?

        init(fetcher: UsageFetcher, onLoginDetected: @escaping () -> Void, onStatusUpdate: @escaping (String) -> Void) {
            self.fetcher = fetcher
            self.onLoginDetected = onLoginDetected
            self.onStatusUpdate = onStatusUpdate
        }

        /// Start observing URL changes via KVO — catches both server redirects
        /// and client-side pushState navigation (SPA routing).
        func startObserving(_ webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                self?.checkURL(of: wv)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkURL(of: webView)
        }

        private func checkURL(of webView: WKWebView) {
            guard let url = webView.url?.absoluteString else { return }
            guard !hasDetectedLogin else { return }

            if url.contains("claude.ai") && !url.contains("/login") && !url.contains("/oauth") {
                hasDetectedLogin = true
                onStatusUpdate(L.capturingSession)

                // Extract and store cookies, then notify
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    Task { @MainActor in
                        let success = await self.fetcher.captureCookies(from: webView)
                        if success {
                            self.onLoginDetected()
                        } else {
                            self.hasDetectedLogin = false
                            self.onStatusUpdate(L.couldNotCapture)
                        }
                    }
                }
            } else if url.contains("/login") {
                onStatusUpdate(L.pleaseLogIn)
            }
        }

        deinit {
            urlObservation?.invalidate()
        }
    }
}
