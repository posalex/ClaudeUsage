import SwiftUI
import Charts

/// Shared chart content used by both the main app chart and the menu bar mini chart.
/// Parameterized by line width for size adaptation.
struct UsageChartContent: View {
    let records: [UsageHistoryRecord]
    let lineWidth: CGFloat
    let period: ChartPeriod
    var showTooltip: Bool = true

    @AppStorage(SharedDefaults.languageKey) private var languageRaw: String = AppLanguage.english.rawValue
    @State private var hoverDate: Date?

    var body: some View {
        Chart {
            ForEach(records) { record in
                let style = record.isSynthetic
                    ? StrokeStyle(lineWidth: lineWidth, dash: [4, 3])
                    : StrokeStyle(lineWidth: lineWidth)

                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Usage", record.sessionPercent),
                    series: .value("Type", "Session (5h)")
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.monotone)
                .lineStyle(style)

                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Usage", record.weeklyPercent),
                    series: .value("Type", "Weekly (7d)")
                )
                .foregroundStyle(.orange)
                .interpolationMethod(.monotone)
                .lineStyle(style)

                if let sonnet = record.sonnetPercent {
                    LineMark(
                        x: .value("Time", record.timestamp),
                        y: .value("Usage", sonnet),
                        series: .value("Type", "Sonnet")
                    )
                    .foregroundStyle(.purple)
                    .interpolationMethod(.monotone)
                    .lineStyle(style)
                }
            }

            // Vertical rule line at hover position
            if let hover = hoverDate, showTooltip {
                RuleMark(x: .value("Hover", hover))
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYScale(domain: 0...100)
        .chartForegroundStyleScale([
            "Session (5h)": Color.blue,
            "Weekly (7d)": Color.orange,
            "Sonnet": Color.purple
        ])
        .chartOverlay { proxy in
            if showTooltip {
                tooltipOverlay(proxy: proxy)
            }
        }
    }

    // MARK: - Tooltip Overlay

    @ViewBuilder
    private func tooltipOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if let date: Date = proxy.value(atX: location.x) {
                            hoverDate = date
                        }
                    case .ended:
                        hoverDate = nil
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let hover = hoverDate, let nearest = nearestRecord(to: hover) {
                        tooltipView(record: nearest, proxy: proxy, geoSize: geo.size)
                    }
                }
        }
    }

    @ViewBuilder
    private func tooltipView(record: UsageHistoryRecord, proxy: ChartProxy, geoSize: CGSize) -> some View {
        let xPos = proxy.position(forX: record.timestamp) ?? 0

        VStack(alignment: .leading, spacing: 2) {
            Text(record.timestamp.formatted(tooltipDateFormat))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Circle().fill(.blue).frame(width: 5, height: 5)
                Text("\(L.sessionTitle): \(Int(record.sessionPercent))%")
                    .font(.system(size: 9, weight: .semibold))
            }

            HStack(spacing: 4) {
                Circle().fill(.orange).frame(width: 5, height: 5)
                Text("\(L.weeklyTitle): \(Int(record.weeklyPercent))%")
                    .font(.system(size: 9, weight: .semibold))
            }

            if let sonnet = record.sonnetPercent {
                HStack(spacing: 4) {
                    Circle().fill(.purple).frame(width: 5, height: 5)
                    Text("\(L.sonnetTitle): \(Int(sonnet))%")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        )
        // Position: keep tooltip within chart bounds
        .offset(x: tooltipXOffset(xPos: xPos, geoWidth: geoSize.width), y: 4)
    }

    /// Keep the tooltip within the chart area horizontally.
    private func tooltipXOffset(xPos: CGFloat, geoWidth: CGFloat) -> CGFloat {
        let tooltipWidth: CGFloat = 120
        let x = xPos + 8
        if x + tooltipWidth > geoWidth {
            return xPos - tooltipWidth - 8
        }
        return x
    }

    /// Find the record closest in time to the hover position using binary search.
    /// Records are sorted by timestamp, so this is O(log n).
    private func nearestRecord(to date: Date) -> UsageHistoryRecord? {
        guard !records.isEmpty else { return nil }
        let target = date.timeIntervalSince1970
        var lo = 0, hi = records.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if records[mid].timestamp.timeIntervalSince1970 < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        // lo is the first record >= target; compare with lo-1 to find the closest
        if lo > 0 {
            let distLo = abs(records[lo].timestamp.timeIntervalSince(date))
            let distPrev = abs(records[lo - 1].timestamp.timeIntervalSince(date))
            return distPrev < distLo ? records[lo - 1] : records[lo]
        }
        return records[lo]
    }

    /// Date format for the tooltip varies by chart period.
    private var tooltipDateFormat: Date.FormatStyle {
        switch period {
        case .hour, .fiveHours, .day:
            return .dateTime.hour().minute()
        case .week:
            return .dateTime.weekday(.abbreviated).hour().minute()
        case .month, .threeMonths, .year, .allTime:
            return .dateTime.month(.abbreviated).day().hour().minute()
        }
    }

    // MARK: - X-Axis Format

    static func xAxisFormat(for period: ChartPeriod) -> Date.FormatStyle {
        switch period {
        case .hour, .fiveHours, .day:
            return .dateTime.hour().minute()
        case .week:
            return .dateTime.weekday(.abbreviated)
        case .month, .threeMonths, .year, .allTime:
            return .dateTime.month(.abbreviated).day()
        }
    }
}
