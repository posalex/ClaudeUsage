import Foundation

enum SharedDefaults {
    static let usageDataKey = "cachedUsageData"
    static let codexUsageDataKey = "cachedCodexUsageData"
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

    // MARK: - Codex Usage Data

    static func saveCodexUsageData(_ data: CodexUsageDisplayData) {
        if let encoded = try? JSONEncoder().encode(data) {
            suite.set(encoded, forKey: codexUsageDataKey)
        }
    }

    static func loadCodexUsageData() -> CodexUsageDisplayData {
        guard let data = suite.data(forKey: codexUsageDataKey),
              let decoded = try? JSONDecoder().decode(CodexUsageDisplayData.self, from: data)
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
    static let menuBarShowFablePercentKey = "menuBarShowFablePercent"
    static let menuBarShowFableResetKey = "menuBarShowFableReset"
    static let menuBarShowCodexPercentKey = "menuBarShowCodexPercent"
    static let menuBarShowCodexResetKey = "menuBarShowCodexReset"
    static let menuBarSessionFormatKey = "menuBarSessionFormat"
    static let menuBarWeeklyFormatKey = "menuBarWeeklyFormat"
    static let menuBarSonnetFormatKey = "menuBarSonnetFormat"
    static let menuBarFableFormatKey = "menuBarFableFormat"
    static let menuBarCodexFormatKey = "menuBarCodexFormat"
    static let menuBarDelimiterKey = "menuBarDelimiter"
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

/// Renders the user-editable pieces of the menu-bar label. Templates stay
/// deliberately small: users can place plain text and the live placeholders
/// wherever they prefer without needing a separate formatting language.
enum MenuBarTextFormat {
    static let sessionDefault = "{percent}/{reset}"
    static let weeklyDefault = "W{percent}/{reset}"
    static let sonnetDefault = "{model}{percent}/{reset}"
    static let fableDefault = "F{percent}/{reset}"
    static let codexDefault = "C{duration}:{percent}/{reset}"
    static let delimiterDefault = "·"

    static func template(for key: String, default defaultValue: String) -> String {
        let template = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return template.isEmpty ? defaultValue : template
    }

    /// Kept separate from templates so an intentionally empty delimiter is
    /// valid and means that adjacent enabled sections touch directly.
    static var delimiter: String {
        UserDefaults.standard.string(forKey: SharedDefaults.menuBarDelimiterKey) ?? delimiterDefault
    }

    static func render(
        template: String,
        percent: String?,
        reset: String?,
        duration: String? = nil,
        model: String? = nil
    ) -> String? {
        guard percent != nil || reset != nil else { return nil }

        let values = [
            "{percent}": percent,
            "{reset}": reset,
            "{duration}": duration,
            "{model}": model
        ]

        var rendered = template
        for (token, value) in values where value == nil {
            while rendered.contains(token) {
                rendered = removingMissingToken(token, from: rendered)
            }
        }
        for (token, value) in values {
            if let value {
                rendered = rendered.replacingOccurrences(of: token, with: value)
            }
        }

        let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// If a toggle hides a placeholder, remove one adjoining separator as
    /// well. This keeps the bundled formats readable (for example `W3d`
    /// instead of `W/3d`) while still permitting arbitrary literal text.
    private static func removingMissingToken(_ token: String, from template: String) -> String {
        guard let range = template.range(of: token) else { return template }

        var removalEnd = range.upperBound
        while removalEnd < template.endIndex, isSeparator(template[removalEnd]) {
            removalEnd = template.index(after: removalEnd)
        }
        if removalEnd > range.upperBound {
            var result = template
            result.removeSubrange(range.lowerBound..<removalEnd)
            return result
        }

        var removalStart = range.lowerBound
        while removalStart > template.startIndex {
            let previous = template.index(before: removalStart)
            guard isSeparator(template[previous]) else { break }
            removalStart = previous
        }

        var result = template
        result.removeSubrange(removalStart..<range.upperBound)
        return result
    }

    private static func isSeparator(_ character: Character) -> Bool {
        let separators = CharacterSet(charactersIn: " /:·|,-")
        return character.unicodeScalars.allSatisfy(separators.contains)
    }
}
