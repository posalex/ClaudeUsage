import SwiftUI
import Charts

/// Descriptor for a single metric series in the usage charts.
struct UsageMetricSeriesDescriptor: Hashable {
	let key: String
	let name: String
	let color: Color
}

extension Color {
    /// Deliberately distinct from Claude's blue session line.
    static let codexMagenta = Color(red: 0.84, green: 0.12, blue: 0.72)
}

/// Shared chart content used by both the main app chart and the menu bar mini chart.
/// Parameterized by line width for size adaptation.
struct UsageChartContent: View {
    let records: [UsageHistoryRecord]
    let lineWidth: CGFloat
    let period: ChartPeriod
    var showTooltip: Bool = true

    @AppStorage(SharedDefaults.languageKey) private var languageRaw: String = AppLanguage.english.rawValue
    @State private var hoverDate: Date?

	/// Series descriptors derived from the history records.
	private var seriesDescriptors: [UsageMetricSeriesDescriptor] {
		Self.buildSeriesDescriptors(from: records)
	}

	    var body: some View {
	        Chart {
	            ForEach(seriesDescriptors, id: \.key) { series in
					let seriesRecords = records.filter { $0.metrics[series.key] != nil }
	                ForEach(seriesRecords) { record in
	                    if let value = record.metrics[series.key] {
	                        let style = record.isSynthetic
	                            ? StrokeStyle(lineWidth: lineWidth, dash: [4, 3])
	                            : StrokeStyle(lineWidth: lineWidth)

	                        LineMark(
	                            x: .value("Time", record.timestamp),
	                            y: .value("Usage", value),
	                            series: .value("Type", series.name)
	                        )
	                        .foregroundStyle(series.color)
	                        .interpolationMethod(.monotone)
	                        .lineStyle(style)
	                    }
	                }

					// A newly connected provider has only one history point. A line
					// needs two points, so render that first Codex sample visibly.
					if seriesRecords.count == 1, let record = seriesRecords.first,
					   let value = record.metrics[series.key] {
						PointMark(
							x: .value("Time", record.timestamp),
							y: .value("Usage", value)
						)
						.foregroundStyle(series.color)
						.symbolSize(28)
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

			ForEach(seriesDescriptors, id: \.key) { series in
				if let value = record.metrics[series.key] {
					HStack(spacing: 4) {
						Circle().fill(series.color).frame(width: 5, height: 5)
						Text("\(series.name): \(Int(value))%")
							.font(.system(size: 9, weight: .semibold))
					}
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

	    // MARK: - Metric series helpers (shared with MenuBarChartView)

	    static func buildSeriesDescriptors(from records: [UsageHistoryRecord]) -> [UsageMetricSeriesDescriptor] {
	        var keys = Set<String>()
	        for record in records {
	            for key in record.metrics.keys {
	                keys.insert(key)
	            }
	        }
	        // These codenames are inert placeholders in the legacy flat Claude
	        // payload, not customer-facing usage windows. Old history can still
	        // contain them, so hide them while retaining the underlying data.
	        keys.subtract(["nimbus_quill", "amber_ladder"])

	        var descriptors: [UsageMetricSeriesDescriptor] = []

	        // Ensure stable, compact ordering for the menu-bar legend.
	        if keys.contains("five_hour") {
	            descriptors.append(UsageMetricSeriesDescriptor(key: "five_hour", name: L.chartClaude5h, color: .blue))
	            keys.remove("five_hour")
	        }
	        if keys.contains("seven_day") {
	            descriptors.append(UsageMetricSeriesDescriptor(key: "seven_day", name: L.chartClaude7d, color: .orange))
	            keys.remove("seven_day")
	        }
			if let fableKey = ["seven_day_fable", "fable"].first(where: keys.contains) {
				descriptors.append(UsageMetricSeriesDescriptor(key: fableKey, name: L.chartFable7d, color: .green))
				keys.remove(fableKey)
			}
			if keys.contains("codex_primary") {
				descriptors.append(UsageMetricSeriesDescriptor(key: "codex_primary", name: L.chartCodex7d, color: .codexMagenta))
				keys.remove("codex_primary")
			}
			if keys.contains("codex_secondary") {
				descriptors.append(UsageMetricSeriesDescriptor(key: "codex_secondary", name: "\(L.codexUsage) 2", color: .codexMagenta.opacity(0.6)))
				keys.remove("codex_secondary")
			}

	        // Remaining keys for additional models / limits
	        for key in keys.sorted() {
	            let name = usageMetricDisplayName(for: key)
	            let color: Color
	            let lower = key.lowercased()
	            if lower.contains("sonnet") {
	                color = .purple
	            } else if lower.contains("fable") {
	                color = .green
	            } else if lower.contains("opus") {
	                color = .pink
	            } else {
	                color = .purple
	            }
	            descriptors.append(UsageMetricSeriesDescriptor(key: key, name: name, color: color))
	        }

	        return descriptors
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
