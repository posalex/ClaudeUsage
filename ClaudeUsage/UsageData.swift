import Foundation

// MARK: - API Response Model

/// Dynamic representation of the claude.ai usage API.
///
/// Older versions of this app hard‑coded individual fields like
/// `seven_day_sonnet`. The API now returns different model names (e.g. Fable),
/// and new ones may be added over time. To stay future‑proof we keep a
/// dictionary of all limits keyed by their raw JSON field name so new
/// categories automatically show up in the UI without code changes.
struct RateLimitResponse: Codable {
	/// All rate limits returned by the API, keyed by field name
	/// (e.g. "five_hour", "seven_day", "seven_day_fable").
	let limits: [String: RateLimit]
	let extraUsage: ExtraUsage?

	/// Convenience accessors for the well‑known windows used across the UI.
	var fiveHour: RateLimit? { limits["five_hour"] }
	var sevenDay: RateLimit? { limits["seven_day"] }

	/// Sorted list of all available metric keys (stable ordering).
	var sortedLimitKeys: [String] {
		limits.keys.sorted()
	}

	init(limits: [String: RateLimit], extraUsage: ExtraUsage?) {
		self.limits = limits
		self.extraUsage = extraUsage
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: AnyCodingKey.self)

		// The current Claude Code response places actual windows in a `limits`
		// array. Its older flat fields still contain placeholder codenames such
		// as `nimbus_quill`, so prefer the canonical array whenever it exists.
		if let limitsKey = container.allKeys.first(where: { $0.stringValue == "limits" }),
		   let canonicalLimits = try? container.decode([CanonicalRateLimit].self, forKey: limitsKey) {
			self.limits = Dictionary(
				uniqueKeysWithValues: canonicalLimits.compactMap { limit in
					guard let key = limit.metricKey else { return nil }
					return (key, RateLimit(
						utilization: limit.utilization,
						resetsAt: limit.resetsAt
					))
				}
			)
			self.extraUsage = nil
			return
		}

		var limits: [String: RateLimit] = [:]
		var extra: ExtraUsage?

		for key in container.allKeys {
			let name = key.stringValue
			if name == "extra_usage" {
				// Separate object with credit information
				extra = try container.decode(ExtraUsage.self, forKey: key)
				continue
			}

			// Treat any other top‑level object that looks like a RateLimit
			// as a dynamic usage category (e.g. five_hour, seven_day_fable, ...).
			if let limit = try? container.decode(RateLimit.self, forKey: key) {
				limits[name] = limit
			}
		}

		self.limits = limits
		self.extraUsage = extra
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: AnyCodingKey.self)
		for (name, limit) in limits {
			if let codingKey = AnyCodingKey(stringValue: name) {
				try container.encode(limit, forKey: codingKey)
			}
		}
		if let extraUsage {
			if let key = AnyCodingKey(stringValue: "extra_usage") {
				try container.encode(extraUsage, forKey: key)
			}
		}
	}

	/// Normalized utilization map (0–100) for all limits that have a value.
	/// `normalize` is injected so callers can clamp/transform values.
	func normalizedUtilizations(using normalize: (Double) -> Double) -> [String: Double] {
		var result: [String: Double] = [:]
		for (key, limit) in limits {
			if let raw = limit.utilization {
				result[key] = normalize(raw)
			}
		}
		return result
	}

	/// Heuristic to select a "highlight" per‑model weekly key that should be
	/// surfaced in compact UI elements (bars, menu bar text).
	func highlightedModelKey(excluding excludedKey: String? = nil) -> String? {
		let modelKeys = limits.keys.filter {
			isWeeklyModelMetricKey($0) && $0 != excludedKey
		}
		return pickHighlightedModelKey(from: Array(modelKeys))
	}

	/// Returns the raw weekly-limit key for a named model, regardless of
	/// whether the API uses its historical `seven_day_<model>` form or the
	/// newer bare `<model>` form.
	func weeklyModelKey(containing fragment: String) -> String? {
		limits.keys
			.filter {
				isWeeklyModelMetricKey($0) &&
				$0.localizedCaseInsensitiveContains(fragment)
			}
			.sorted()
			.first
	}
}

/// A window in Claude's current `limits` array. Model-specific weekly windows
/// are identified by the model display name rather than a flat top-level key.
private struct CanonicalRateLimit: Decodable {
	let kind: String?
	let group: String?
	let percent: Double?
	let utilizationValue: Double?
	let resetsAt: String?
	let scope: CanonicalRateLimitScope?

	enum CodingKeys: String, CodingKey {
		case kind, group, percent, utilizationValue = "utilization"
		case resetsAt = "resets_at"
		case scope
	}

	var utilization: Double? { percent ?? utilizationValue }

	var metricKey: String? {
		switch kind?.lowercased() {
		case "session":
			return "five_hour"
		case "weekly_all":
			return "seven_day"
		case "weekly_scoped":
			guard group?.lowercased() == "weekly",
				  let modelName = scope?.model?.displayName,
				  let suffix = Self.metricSuffix(from: modelName) else { return nil }
			return "seven_day_\(suffix)"
		default:
			return nil
		}
	}

	private static func metricSuffix(from displayName: String) -> String? {
		let parts = displayName
			.lowercased()
			.components(separatedBy: CharacterSet.alphanumerics.inverted)
			.filter { !$0.isEmpty }
		guard !parts.isEmpty else { return nil }
		return parts.joined(separator: "_")
	}
}

private struct CanonicalRateLimitScope: Decodable {
	let model: CanonicalRateLimitModel?
}

private struct CanonicalRateLimitModel: Decodable {
	let displayName: String?

	enum CodingKeys: String, CodingKey {
		case displayName = "display_name"
	}
}

/// CodingKey that can be constructed from any string so we can iterate over
/// arbitrary top‑level keys in the usage API response.
private struct AnyCodingKey: CodingKey {
	let stringValue: String
	let intValue: Int?

	init(_ string: String) {
		self.stringValue = string
		self.intValue = nil
	}

	init?(stringValue: String) {
		self.init(stringValue)
	}

	init?(intValue: Int) {
		self.stringValue = String(intValue)
		self.intValue = intValue
	}
}

struct RateLimit: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

	init(utilization: Double?, resetsAt: String?) {
		self.utilization = utilization
		self.resetsAt = resetsAt
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
	/// Dedicated Fable weekly limit. Kept separate so it can be independently
	/// selected for the menu bar instead of sharing the legacy Sonnet toggle.
	let weeklyFablePercent: Double?
	let weeklyFableResetISO: String?
	/// Raw API key for the highlighted per‑model metric, such as
	/// "seven_day_fable" or "seven_day_sonnet". Historically this was always
	/// Sonnet, but the field is now used generically so new models can be
	/// displayed without code changes.
	let highlightedModelKey: String?
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
		case weeklyFablePercent
		case weeklyFableResetISO
		case highlightedModelKey
        case lastUpdated
        case isLoggedIn
    }

    /// Full localized label: "Resets in 3h"
    var sessionResetLabel: String { formatResetTime(from: sessionResetISO) }
    var weeklyResetLabel: String { formatResetTime(from: weeklyResetISO) }
    var weeklySonnetResetLabel: String? { weeklySonnetResetISO.map { formatResetTime(from: $0) } }
	var weeklyFableResetLabel: String? { weeklyFableResetISO.map { formatResetTime(from: $0) } }

    static var empty: UsageDisplayData { UsageDisplayData(
        sessionPercent: 0,
        sessionResetISO: "--",
        weeklyPercent: 0,
        weeklyResetISO: "--",
        weeklySonnetPercent: nil,
        weeklySonnetResetISO: nil,
		weeklyFablePercent: nil,
		weeklyFableResetISO: nil,
			highlightedModelKey: nil,
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

	var fableResetCompact: String? {
		weeklyFableResetISO.map { compactResetFromISO($0) }
	}

	/// Human‑readable name for the highlighted per‑model metric (e.g. "Fable (7d)").
	var highlightedModelTitle: String? {
		guard let key = effectiveHighlightedModelKey else { return nil }
		return usageMetricDisplayName(for: key)
	}

	/// Short code for the compact menu bar text (e.g. "F" for Fable).
	var highlightedModelShortCode: String? {
		guard let key = effectiveHighlightedModelKey else { return nil }
		return usageMetricShortCode(for: key)
	}

	/// For cached data from older versions we may not have a key stored but we
	/// still have `weeklySonnetPercent`. In that case assume the legacy
	/// "seven_day_sonnet" key so the UI shows a sensible label.
	private var effectiveHighlightedModelKey: String? {
		if let key = highlightedModelKey { return key }
		if weeklySonnetPercent != nil { return "seven_day_sonnet" }
		return nil
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
        let sessionPercentText = pref(SharedDefaults.menuBarShowSessionPercentKey, default: true)
            ? "\(Int(sessionPercent))%" : nil
        let sessionResetText = pref(SharedDefaults.menuBarShowSessionResetKey, default: true)
            ? sessionResetCompact : nil
        if let sessionPart = MenuBarTextFormat.render(
            template: MenuBarTextFormat.template(
                for: SharedDefaults.menuBarSessionFormatKey,
                default: MenuBarTextFormat.sessionDefault
            ),
            percent: sessionPercentText,
            reset: sessionResetText
        ) {
            parts.append(sessionPart)
        }

        // Weekly section
        let weeklyPercentText = pref(SharedDefaults.menuBarShowWeeklyPercentKey, default: false)
            ? "\(Int(weeklyPercent))%" : nil
        let weeklyResetText = pref(SharedDefaults.menuBarShowWeeklyResetKey, default: false)
            ? weeklyResetCompact : nil
        if let weeklyPart = MenuBarTextFormat.render(
            template: MenuBarTextFormat.template(
                for: SharedDefaults.menuBarWeeklyFormatKey,
                default: MenuBarTextFormat.weeklyDefault
            ),
            percent: weeklyPercentText,
            reset: weeklyResetText
        ) {
            parts.append(weeklyPart)
        }

		// Fable has an independent Claude Code limit. It uses dedicated
		// preferences so adding Fable does not change an existing Sonnet setup.
		if let fable = weeklyFablePercent {
			let fablePercentText = pref(SharedDefaults.menuBarShowFablePercentKey, default: false)
				? "\(Int(fable))%" : nil
			let fableResetText = pref(SharedDefaults.menuBarShowFableResetKey, default: false)
				? fableResetCompact : nil
			if let fablePart = MenuBarTextFormat.render(
				template: MenuBarTextFormat.template(
					for: SharedDefaults.menuBarFableFormatKey,
					default: MenuBarTextFormat.fableDefault
				),
				percent: fablePercentText,
				reset: fableResetText
			) {
				parts.append(fablePart)
			}
		}

        // Sonnet section
        if let sonnet = weeklySonnetPercent {
            let sonnetPercentText = pref(SharedDefaults.menuBarShowSonnetPercentKey, default: false)
                ? "\(Int(sonnet))%" : nil
            let sonnetResetText = pref(SharedDefaults.menuBarShowSonnetResetKey, default: false)
                ? sonnetResetCompact : nil
            if let sonnetPart = MenuBarTextFormat.render(
                template: MenuBarTextFormat.template(
                    for: SharedDefaults.menuBarSonnetFormatKey,
                    default: MenuBarTextFormat.sonnetDefault
                ),
                percent: sonnetPercentText,
                reset: sonnetResetText,
                model: sonnetPercentText == nil ? nil : highlightedModelShortCode ?? "S"
            ) {
                parts.append(sonnetPart)
            }
        }

        return parts.isEmpty ? "—" : parts.joined(separator: MenuBarTextFormat.delimiter)
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

// MARK: - Dynamic metric helpers

/// Returns true for per-model weekly usage keys. Claude has used both
/// `seven_day_fable` and the newer bare `fable` form for Fable.
func isWeeklyModelMetricKey(_ key: String) -> Bool {
	return (key.hasPrefix("seven_day_") && key != "seven_day") ||
		key.caseInsensitiveCompare("fable") == .orderedSame
}

/// Choose a stable "highlight" model key from the available per‑model weekly
/// metrics. Prefer Fable, then Sonnet, then Opus if present, otherwise use
/// the first key in alphabetical order so new models are picked up
/// automatically.
func pickHighlightedModelKey(from keys: [String]) -> String? {
	guard !keys.isEmpty else { return nil }
	let lowercased = keys.map { ($0, $0.lowercased()) }
	let preferredFragments = ["fable", "sonnet", "opus"]

	for fragment in preferredFragments {
		if let match = lowercased.first(where: { $0.1.contains(fragment) }) {
			return match.0
		}
	}

	return keys.sorted().first
}

/// Human‑readable name for a usage metric key from the API.
func usageMetricDisplayName(for key: String) -> String {
	switch key {
	case "five_hour":
		return L.sessionTitle
	case "seven_day":
		return L.weeklyTitle
	case "fable":
		return L.fableTitle
	default:
		// Keys like "seven_day_fable" → "Fable (7d)"
		if key.hasPrefix("seven_day_") {
			let suffix = String(key.dropFirst("seven_day_".count))
			let words = suffix
				.split(separator: "_")
				.map { $0.capitalized }
				.joined(separator: " ")
			return "\(words) (7d)"
		}
		// Fallback: replace underscores and capitalize
		return key
			.replacingOccurrences(of: "_", with: " ")
			.capitalized
	}
}

/// Short code used in the compact menu bar text, e.g. "S" for Session,
/// "W" for Weekly, "F" for Fable.
func usageMetricShortCode(for key: String) -> String {
	switch key {
	case "five_hour":
		return "S"
	case "seven_day":
		return "W"
	default:
		if key.hasPrefix("seven_day_") {
			let suffix = String(key.dropFirst("seven_day_".count))
			if let first = suffix.first {
				return String(first).uppercased()
			}
		}
		return String(key.first ?? "?").uppercased()
	}
}
