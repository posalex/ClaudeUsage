import SwiftUI
import Charts

/// A compact usage chart designed for the menu bar dropdown.
struct MenuBarChartView: View {
    let period: ChartPeriod
    let lastUpdated: Date
    @State private var records: [UsageHistoryRecord] = []

    // Observe language changes so legend labels update
    @AppStorage(SharedDefaults.languageKey) private var languageRaw: String = AppLanguage.english.rawValue

    var body: some View {
        Group {
            if records.isEmpty {
                emptyState
            } else {
                chart
            }
        }
        .onAppear { loadData() }
        .onChange(of: period) { _, _ in loadData() }
        .onChange(of: lastUpdated) { _, _ in loadData() }
    }

    // MARK: - Chart

    private var chart: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Compact legend
            HStack(spacing: 10) {
                legendDot(color: .blue, label: L.sessionTitle)
                legendDot(color: .orange, label: L.weeklyTitle)
                if records.contains(where: { $0.sonnetPercent != nil }) {
                    legendDot(color: .purple, label: L.sonnetTitle)
                }
            }
            .padding(.horizontal, 4)

            UsageChartContent(records: records, lineWidth: 1.5, period: period)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(Color.gray.opacity(0.25))
                        AxisValueLabel {
                            if let intVal = value.as(Int.self) {
                                Text("\(intVal)%")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(Color.gray.opacity(0.15))
                        AxisValueLabel(format: UsageChartContent.xAxisFormat(for: period))
                            .font(.system(size: 9))
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 120)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 18))
                .foregroundColor(.gray)
            Text(L.noDataForPeriod)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }

    // MARK: - Data

    private func loadData() {
        UsageHistoryStore.shared.fetch(since: period.startDate) { result in
            records = result
        }
    }
}
