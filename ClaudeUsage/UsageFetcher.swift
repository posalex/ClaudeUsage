import Foundation
import WebKit

@MainActor
class UsageFetcher: ObservableObject {
    @Published var usageData: UsageDisplayData = SharedDefaults.loadUsageData()
    @Published var isLoggedIn: Bool = false
    @Published var isFetching: Bool = false
    @Published var lastError: String?

    private var timer: Timer?

    init() {
        // Check if we have stored cookies (i.e. previously logged in)
        isLoggedIn = SharedDefaults.loadCookieHeader() != nil && usageData.isLoggedIn
    }

    // MARK: - Cookie Management

    /// Extract cookies from a WKWebView after login and store them
    func captureCookies(from webView: WKWebView) async -> Bool {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }

        guard !claudeCookies.isEmpty else { return false }

        let cookieHeader = claudeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        SharedDefaults.saveCookieHeader(cookieHeader)
        return true
    }

    func logout() {
        SharedDefaults.clearCookieHeader()
        SharedDefaults.saveOrgUUID(nil)
        isLoggedIn = false
        updateData(.empty)
        stopAutoRefresh()

        // Clear WKWebView cookies so the next login doesn't auto-restore the session
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let claudeRecords = records.filter { $0.displayName.contains("claude") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: claudeRecords) {}
        }
    }

    // MARK: - Auto-refresh Timer

    func startAutoRefresh() {
        stopAutoRefresh()
        let interval = TimeInterval(SharedDefaults.loadRefreshInterval() * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsage()
            }
        }
        // Also fetch immediately
        Task {
            await fetchUsage()
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func restartAutoRefresh() {
        startAutoRefresh()
    }

    // MARK: - Fetch Usage

    func fetchUsage() async {
        guard !isFetching else { return }
        isFetching = true
        lastError = nil

        defer { isFetching = false }

        // Use stored cookies
        guard let cookieHeader = SharedDefaults.loadCookieHeader() else {
            isLoggedIn = false
            updateData(.empty)
            lastError = L.errorNotLoggedIn
            return
        }

        // Get org UUID (fetch from bootstrap if not cached)
        let orgUUID: String
        if let cached = SharedDefaults.loadOrgUUID() {
            orgUUID = cached
        } else {
            guard let uuid = await fetchOrgUUID(cookieHeader: cookieHeader) else {
                isLoggedIn = false
                updateData(.empty)
                lastError = L.errorOrgFailed
                return
            }
            orgUUID = uuid
            SharedDefaults.saveOrgUUID(orgUUID)
        }

        // Fetch usage data
        let urlString = "https://claude.ai/api/organizations/\(orgUUID)/usage"
        guard let url = URL(string: urlString) else {
            lastError = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:149.0) Gecko/20100101 Firefox/149.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("1.0.0", forHTTPHeaderField: "anthropic-client-version")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                isLoggedIn = false
                SharedDefaults.clearCookieHeader()
                updateData(.empty)
                lastError = L.errorSessionExpired
                return
            }

            guard httpResponse.statusCode == 200 else {
                lastError = "HTTP \(httpResponse.statusCode)"
                return
            }

            let rateLimits: RateLimitResponse
            do {
                rateLimits = try JSONDecoder().decode(RateLimitResponse.self, from: data)
            } catch let decodeError {
                // Log the raw response for debugging, then show 0 instead of stale cache
                let raw = String(data: data, encoding: .utf8) ?? "(binary)"
                print("[ClaudeUsage] JSON decode failed: \(decodeError)\nRaw: \(raw)")
                updateData(.empty)
                isLoggedIn = true
                lastError = L.errorUnexpectedFormat
                return
            }
            isLoggedIn = true

            let displayData = UsageDisplayData(
                sessionPercent: normalizeUtilization(rateLimits.fiveHour?.utilization ?? 0),
                sessionResetISO: rateLimits.fiveHour?.resetsAt ?? "--",
                weeklyPercent: normalizeUtilization(rateLimits.sevenDay?.utilization ?? 0),
                weeklyResetISO: rateLimits.sevenDay?.resetsAt ?? "--",
                weeklySonnetPercent: rateLimits.sevenDaySonnet?.utilization.map { normalizeUtilization($0) },
                weeklySonnetResetISO: rateLimits.sevenDaySonnet?.resetsAt,
                lastUpdated: Date(),
                isLoggedIn: true
            )

            updateData(displayData)

            // Record to history for charts, including session reset time for gap interpolation
            let sessionResetsAt: Date? = rateLimits.fiveHour?.resetsAt.flatMap { parseISO8601($0) }
            UsageHistoryStore.shared.record(
                sessionPercent: displayData.sessionPercent,
                weeklyPercent: displayData.weeklyPercent,
                sonnetPercent: displayData.weeklySonnetPercent,
                sessionResetsAt: sessionResetsAt
            )

        } catch {
            lastError = error.localizedDescription
            // Don't preserve stale cache — show error state
            if !isLoggedIn { updateData(.empty) }
        }
    }

    // MARK: - Fetch Org UUID from Bootstrap

    private func fetchOrgUUID(cookieHeader: String) async -> String? {
        guard let url = URL(string: "https://claude.ai/api/bootstrap") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) {
                lastError = "Session expired (HTTP \(httpResponse.statusCode))"
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let account = json["account"] as? [String: Any],
               let memberships = account["memberships"] as? [[String: Any]],
               let firstMembership = memberships.first,
               let org = firstMembership["organization"] as? [String: Any],
               let uuid = org["uuid"] as? String {
                return uuid
            }

            lastError = "Could not parse organization from bootstrap response"
        } catch {
            lastError = "Bootstrap fetch failed: \(error.localizedDescription)"
        }

        return nil
    }

    // MARK: - Normalization

    /// The claude.ai usage API returns utilization as a percentage (0–100).
    /// Values above 100 are clamped. If the API ever changes to 0–1 fractions,
    /// the displayed values will be visibly wrong (all <1%) and easy to spot.
    private func normalizeUtilization(_ value: Double) -> Double {
        return min(value, 100.0)
    }

    // MARK: - Update & Persist

    private func updateData(_ data: UsageDisplayData) {
        usageData = data
        SharedDefaults.saveUsageData(data)
    }
}
