import Foundation

// MARK: - Display model

/// A single rolling Codex usage window returned by the local Codex app server.
struct CodexUsageWindow: Codable, Equatable {
    let usedPercent: Double
    let resetISO: String?
    let windowDurationMinutes: Int?

    var resetLabel: String {
        guard let resetISO else { return L.resetsUnknown }
        return formatResetTime(from: resetISO)
    }

    var resetCompact: String {
        guard let resetISO else { return "--" }
        return compactResetFromISO(resetISO)
    }

    /// Examples: "5h", "7d", or "90m". The Codex service decides the
    /// actual window, so this intentionally does not assume fixed limits.
    var durationLabel: String {
        guard let windowDurationMinutes, windowDurationMinutes > 0 else {
            return ""
        }

        let day = 24 * 60
        if windowDurationMinutes.isMultiple(of: day) {
            return "\(windowDurationMinutes / day)d"
        }
        if windowDurationMinutes.isMultiple(of: 60) {
            return "\(windowDurationMinutes / 60)h"
        }
        return "\(windowDurationMinutes)m"
    }

    var title: String {
        durationLabel.isEmpty ? L.codexUsage : "\(L.codexUsage) (\(durationLabel))"
    }
}

struct CodexUsageDisplayData: Codable {
    let primary: CodexUsageWindow?
    let secondary: CodexUsageWindow?
    let planType: String?
    let lastUpdated: Date
    let isAvailable: Bool

    static var empty: CodexUsageDisplayData {
        CodexUsageDisplayData(
            primary: nil,
            secondary: nil,
            planType: nil,
            lastUpdated: Date(),
            isAvailable: false
        )
    }

    /// Compact menu-bar text. A window's duration is included because Codex
    /// accounts can have different primary and secondary rolling windows.
    func menuBarLabel() -> String? {
        guard isAvailable else { return nil }

        let defaults = UserDefaults.standard
        func preference(_ key: String, default defaultValue: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
        }

        let showPercent = preference(SharedDefaults.menuBarShowCodexPercentKey, default: true)
        let showReset = preference(SharedDefaults.menuBarShowCodexResetKey, default: true)
        var parts: [String] = []

        func append(_ window: CodexUsageWindow) {
            let prefix = window.durationLabel.isEmpty ? "C" : "C\(window.durationLabel)"
            var windowParts: [String] = []
            if showPercent {
                windowParts.append("\(prefix):\(Int(window.usedPercent))%")
            }
            if showReset {
                windowParts.append(window.resetCompact)
            }
            if !windowParts.isEmpty {
                parts.append(windowParts.joined(separator: " "))
            }
        }

        if let primary { append(primary) }
        if let secondary { append(secondary) }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - Fetcher

/// Reads Codex rate limits through the installed Codex CLI's local app server.
///
/// The app never reads, stores, or forwards Codex credentials itself. The CLI
/// owns authentication and only returns the already-sanitized usage snapshot.
@MainActor
final class CodexUsageFetcher: ObservableObject {
    @Published var usageData: CodexUsageDisplayData
    @Published var isAvailable: Bool
    @Published var isFetching = false
    @Published var lastError: String?

    private var timer: Timer?

    init() {
        let cachedData = SharedDefaults.loadCodexUsageData()
        usageData = cachedData
        isAvailable = cachedData.isAvailable
    }

    func startAutoRefresh() {
        stopAutoRefresh()

        let interval = TimeInterval(SharedDefaults.loadRefreshInterval() * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsage()
            }
        }

        Task { await fetchUsage() }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func restartAutoRefresh() {
        startAutoRefresh()
    }

    func fetchUsage() async {
        guard !isFetching else { return }
        isFetching = true
        lastError = nil
        defer { isFetching = false }

        guard let executableURL = CodexAppServerClient.executableURL() else {
            setUnavailable(message: L.codexNotInstalled)
            return
        }

        do {
            let limits = try await CodexAppServerClient.readRateLimits(executableURL: executableURL)
            guard let primary = limits.primary else {
                setUnavailable(message: L.codexUsageUnavailable)
                return
            }

            let data = CodexUsageDisplayData(
                primary: Self.displayWindow(from: primary),
                secondary: limits.secondary.map(Self.displayWindow(from:)),
                planType: limits.planType,
                lastUpdated: Date(),
                isAvailable: true
            )
            usageData = data
            SharedDefaults.saveCodexUsageData(data)
            isAvailable = true

            // Keep Codex in the same time-series store as Claude, but with
            // dedicated metric keys so neither provider overwrites the other.
            var historyMetrics = ["codex_primary": primary.usedPercent]
            if let secondary = limits.secondary {
                historyMetrics["codex_secondary"] = secondary.usedPercent
            }
            UsageHistoryStore.shared.record(metrics: historyMetrics)
        } catch let error as CodexAppServerError {
            setUnavailable(message: error.userMessage)
        } catch {
            setUnavailable(message: L.codexUsageUnavailable)
        }
    }

    private static func displayWindow(from window: CodexRateLimitWindow) -> CodexUsageWindow {
        let percentage = min(max(window.usedPercent, 0), 100)
        let resetISO = window.resetsAt.map {
            Date(timeIntervalSince1970: TimeInterval($0)).ISO8601Format()
        }
        return CodexUsageWindow(
            usedPercent: percentage,
            resetISO: resetISO,
            windowDurationMinutes: window.windowDurationMins
        )
    }

    private func setUnavailable(message: String) {
        usageData = .empty
        SharedDefaults.saveCodexUsageData(.empty)
        isAvailable = false
        lastError = message
    }
}

// MARK: - Local Codex app-server client

private enum CodexAppServerError: Error {
    case noResponse
    case invalidResponse
    case timedOut
    case server(String)

    var userMessage: String {
        switch self {
        case .server:
            return L.codexUsageUnavailable
        case .noResponse, .invalidResponse, .timedOut:
            return L.codexUsageUnavailable
        }
    }
}

private enum CodexAppServerClient {
    private static let requestID = 2

    static func executableURL() -> URL? {
        var candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        return candidates.lazy
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func readRateLimits(executableURL: URL) async throws -> CodexRateLimitSnapshot {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()

        defer {
            input.fileHandleForWriting.closeFile()
            if process.isRunning {
                process.terminate()
            }
        }

        for message in requestMessages() {
            let data = try JSONSerialization.data(withJSONObject: message)
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data("\n".utf8))
        }

        return try await withThrowingTaskGroup(of: CodexRateLimitSnapshot.self) { group in
            group.addTask {
                for try await line in output.fileHandleForReading.bytes.lines {
                    let responseData = Data(line.utf8)
                    guard Self.responseMatchesRequest(responseData) else { continue }

                    let response = try JSONDecoder().decode(CodexAppServerResponse.self, from: responseData)
                    if let message = response.error?.message {
                        throw CodexAppServerError.server(message)
                    }
                    guard let result = response.result else {
                        throw CodexAppServerError.invalidResponse
                    }
                    return result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
                }
                throw CodexAppServerError.noResponse
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                try Task.checkCancellation()
                throw CodexAppServerError.timedOut
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CodexAppServerError.noResponse
            }
            return result
        }
    }

    private static func requestMessages() -> [[String: Any]] {
        [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "ClaudeUsage", "version": "1.0.0"],
                    "capabilities": [:]
                ]
            ],
            ["method": "initialized"],
            ["id": requestID, "method": "account/rateLimits/read", "params": NSNull()]
        ]
    }

    private static func responseMatchesRequest(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["id"] as? Int == requestID
    }
}

private struct CodexAppServerResponse: Decodable {
    let result: CodexRateLimitsResult?
    let error: CodexAppServerResponseError?
}

private struct CodexAppServerResponseError: Decodable {
    let message: String
}

private struct CodexRateLimitsResult: Decodable {
    let rateLimits: CodexRateLimitSnapshot
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
}

private struct CodexRateLimitSnapshot: Decodable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let planType: String?
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int?
}
