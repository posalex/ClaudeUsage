import Foundation

enum SharedDefaults {
    static let usageDataKey = "cachedUsageData"
    static let orgUUIDKey = "organizationUUID"
    static let refreshIntervalKey = "refreshIntervalMinutes"
    static let cookieHeaderKey = "claudeCookieHeader"

    static let suite: UserDefaults = .standard

    // MARK: - Usage Data

    static func saveUsageData(_ data: UsageDisplayData) {
        if let encoded = try? JSONEncoder().encode(data) {
            suite.set(encoded, forKey: usageDataKey)
        }
    }

    static func loadUsageData() -> UsageDisplayData {
        guard let data = suite.data(forKey: usageDataKey),
              let decoded = try? JSONDecoder().decode(UsageDisplayData.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    // MARK: - Organization UUID

    static func saveOrgUUID(_ uuid: String?) {
        if let uuid = uuid {
            suite.set(uuid, forKey: orgUUIDKey)
        } else {
            suite.removeObject(forKey: orgUUIDKey)
        }
    }

    static func loadOrgUUID() -> String? {
        suite.string(forKey: orgUUIDKey)
    }

    // MARK: - Cookie Header (stored in Keychain)

    static func saveCookieHeader(_ header: String) {
        KeychainHelper.save(header)
    }

    static func loadCookieHeader() -> String? {
        // Migrate from UserDefaults if present (one-time)
        if let legacy = suite.string(forKey: cookieHeaderKey) {
            KeychainHelper.save(legacy)
            suite.removeObject(forKey: cookieHeaderKey)
            return legacy
        }
        return KeychainHelper.load()
    }

    static func clearCookieHeader() {
        KeychainHelper.delete()
        suite.removeObject(forKey: cookieHeaderKey) // clean up legacy
    }

    // MARK: - Menu Bar Settings

    static let menuBarShowSessionPercentKey = "menuBarShowSessionPercent"
    static let menuBarShowSessionResetKey = "menuBarShowSessionReset"
    static let menuBarShowWeeklyPercentKey = "menuBarShowWeeklyPercent"
    static let menuBarShowWeeklyResetKey = "menuBarShowWeeklyReset"
    static let menuBarShowSonnetPercentKey = "menuBarShowSonnetPercent"
    static let menuBarShowSonnetResetKey = "menuBarShowSonnetReset"
    static let menuBarChartPeriodKey = "menuBarChartPeriod"
    static let languageKey = "appLanguage"

    // MARK: - Chart Period

    static let chartPeriodKey = "chartPeriod"

    static func saveChartPeriod(_ rawValue: String) {
        suite.set(rawValue, forKey: chartPeriodKey)
    }

    static func loadChartPeriod() -> String? {
        suite.string(forKey: chartPeriodKey)
    }

    // MARK: - Refresh Interval

    static func saveRefreshInterval(_ minutes: Int) {
        suite.set(minutes, forKey: refreshIntervalKey)
    }

    static func loadRefreshInterval() -> Int {
        let val = suite.integer(forKey: refreshIntervalKey)
        return val > 0 ? val : 5 // Default 5 minutes
    }
}
