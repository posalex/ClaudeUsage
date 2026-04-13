import Foundation

// MARK: - API Response Model

struct RateLimitResponse: Codable {
    let fiveHour: RateLimit?
    let sevenDay: RateLimit?
    let sevenDayOauthApps: RateLimit?
    let sevenDayOpus: RateLimit?
    let sevenDaySonnet: RateLimit?
    let sevenDayCowork: RateLimit?
    let extraUsage: ExtraUsage?
    
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extra_usage"
    }
}

struct RateLimit: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let monthlyLimit: Int?
    let usedCredits: Double?
    let utilization: Double?
    
    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

// MARK: - Widget Display Model

struct UsageDisplayData: Codable {
    let sessionPercent: Double
    /// Raw ISO 8601 reset time string, or "--" when unavailable
    let sessionResetISO: String
    let weeklyPercent: Double
    let weeklyResetISO: String
    let weeklySonnetPercent: Double?
    let weeklySonnetResetISO: String?
    let lastUpdated: Date
    let isLoggedIn: Bool

    /// Maps old cached field names to new property names for backward compatibility.
    /// Previously these were stored as `sessionResetLabel`, `weeklyResetLabel`, etc.
    enum CodingKeys: String, CodingKey {
        case sessionPercent
        case sessionResetISO = "sessionResetLabel"
        case weeklyPercent
        case weeklyResetISO = "weeklyResetLabel"
        case weeklySonnetPercent
        case weeklySonnetResetISO = "weeklySonnetResetLabel"
        case lastUpdated
        case isLoggedIn
    }

    /// Full localized label: "Resets in 3h"
    var sessionResetLabel: String { formatResetTime(from: sessionResetISO) }
    var weeklyResetLabel: String { formatResetTime(from: weeklyResetISO) }
    var weeklySonnetResetLabel: String? { weeklySonnetResetISO.map { formatResetTime(from: $0) } }

    static var empty: UsageDisplayData { UsageDisplayData(
        sessionPercent: 0,
        sessionResetISO: "--",
        weeklyPercent: 0,
        weeklyResetISO: "--",
        weeklySonnetPercent: nil,
        weeklySonnetResetISO: nil,
        lastUpdated: Date(),
        isLoggedIn: false
    ) }
}

// MARK: - Compact Labels for Menu Bar

extension UsageDisplayData {
    /// Compact localized reset label for the menu bar (e.g. "3h", "58m", "now")
    var sessionResetCompact: String {
        compactResetFromISO(sessionResetISO)
    }

    var weeklyResetCompact: String {
        compactResetFromISO(weeklyResetISO)
    }

    var sonnetResetCompact: String? {
        weeklySonnetResetISO.map { compactResetFromISO($0) }
    }

    /// Build the menu bar label based on user preferences.
    /// Reads directly from UserDefaults.standard — same store @AppStorage uses in MenuBarView.
    func menuBarLabel() -> String {
        guard isLoggedIn else { return "—" }

        let ud = UserDefaults.standard
        // For keys that haven't been set yet, object(forKey:) returns nil.
        // Default to true for session%, session reset; false for everything else.
        func pref(_ key: String, default defaultVal: Bool) -> Bool {
            ud.object(forKey: key) == nil ? defaultVal : ud.bool(forKey: key)
        }

        var parts: [String] = []

        // Session section
        var sessionParts: [String] = []
        if pref(SharedDefaults.menuBarShowSessionPercentKey, default: true) {
            sessionParts.append("\(Int(sessionPercent))%")
        }
        if pref(SharedDefaults.menuBarShowSessionResetKey, default: true) {
            sessionParts.append(sessionResetCompact)
        }
        if !sessionParts.isEmpty { parts.append(sessionParts.joined(separator: " ")) }

        // Weekly section
        var weeklyParts: [String] = []
        if pref(SharedDefaults.menuBarShowWeeklyPercentKey, default: false) {
            weeklyParts.append("W:\(Int(weeklyPercent))%")
        }
        if pref(SharedDefaults.menuBarShowWeeklyResetKey, default: false) {
            weeklyParts.append(weeklyResetCompact)
        }
        if !weeklyParts.isEmpty { parts.append(weeklyParts.joined(separator: " ")) }

        // Sonnet section
        if let sonnet = weeklySonnetPercent {
            var sonnetParts: [String] = []
            if pref(SharedDefaults.menuBarShowSonnetPercentKey, default: false) {
                sonnetParts.append("S:\(Int(sonnet))%")
            }
            if pref(SharedDefaults.menuBarShowSonnetResetKey, default: false),
               let reset = sonnetResetCompact {
                sonnetParts.append(reset)
            }
            if !sonnetParts.isEmpty { parts.append(sonnetParts.joined(separator: " ")) }
        }

        return parts.isEmpty ? "—" : parts.joined(separator: "  ·  ")
    }
}

// MARK: - Helpers

/// Parse an ISO 8601 date string into a Date, trying with and without fractional seconds.
func parseISO8601(_ isoString: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: isoString) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: isoString)
}

/// Duration components extracted from a reset time, independent of display format.
enum ResetDuration {
    case days(Int)
    case hours(Int)
    case minutes(Int)
    case soon
    case now
    case unknown
}

/// Parse an ISO string and return structured duration components.
func resetDuration(from isoString: String) -> ResetDuration {
    guard let date = parseISO8601(isoString) else { return .unknown }
    let interval = date.timeIntervalSince(Date())
    if interval <= 0 { return .now }
    let minutes = Int(interval) / 60
    let hours = minutes / 60
    let days = hours / 24
    if days > 0 { return .days(days) }
    if hours > 0 { return .hours(hours) }
    if minutes > 0 { return .minutes(minutes) }
    return .soon
}

/// Full localized label: "Resets in 3h", "Resets soon", "now"
func formatResetTime(from isoString: String) -> String {
    switch resetDuration(from: isoString) {
    case .days(let n): return L.resetsInDays(n)
    case .hours(let n): return L.resetsInHours(n)
    case .minutes(let n): return L.resetsInMinutes(n)
    case .soon: return L.resetsSoon
    case .now: return L.resetsNow
    case .unknown: return L.resetsUnknown
    }
}

/// Compact localized label for menu bar: "3h", "58m", "now"
func compactResetFromISO(_ isoString: String) -> String {
    switch resetDuration(from: isoString) {
    case .days(let n): return L.compactDays(n)
    case .hours(let n): return L.compactHours(n)
    case .minutes(let n): return L.compactMinutes(n)
    case .soon: return L.compactSoon
    case .now: return L.compactNow
    case .unknown: return "--"
    }
}
