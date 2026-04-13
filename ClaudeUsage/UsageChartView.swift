import SwiftUI
import Charts

struct UsageChartView: View {
    @ObservedObject var fetcher: UsageFetcher

    @State private var selectedPeriod: ChartPeriod = {
        if let raw = SharedDefaults.loadChartPeriod(),
           let period = ChartPeriod(rawValue: raw) {
            return period
        }
        return .week
    }()

    @State private var records: [UsageHistoryRecord] = []

    // Observe language changes so the view re-renders
    @AppStorage(SharedDefaults.languageKey) private var languageRaw: String = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.usageOverTime)
                    .font(.headline)
                Spacer()
                periodPicker
            }

            if records.isEmpty {
                emptyState
            } else {
                chart
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .onAppear { loadData() }
        .onChange(of: selectedPeriod) { _, _ in loadData() }
        .onChange(of: fetcher.usageData.lastUpdated) { _, _ in loadData() }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        HStack(spacing: 2) {
            ForEach(ChartPeriod.allCases, id: \.self) { period in
                Button(period.rawValue) {
                    selectedPeriod = period
                    SharedDefaults.saveChartPeriod(period.rawValue)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: selectedPeriod == period ? .bold : .regular))
                .foregroundStyle(selectedPeriod == period ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selectedPeriod == period ? Color.blue : Color.clear)
                )
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.1))
        )
    }

    // MARK: - Chart

    private var chart: some View {
        UsageChartContent(records: records, lineWidth: 2, period: selectedPeriod)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)%")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel(format: UsageChartContent.xAxisFormat(for: selectedPeriod))
                        .font(.system(size: 10))
                }
            }
            .chartLegend(position: .top, alignment: .leading, spacing: 8)
            .frame(height: 200)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28))
                .foregroundColor(.gray)
            Text(L.noUsageDataYet)
                .font(.callout)
                .foregroundColor(.secondary)
            Text(L.dataWillAppear)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    // MARK: - Data Loading

    private func loadData() {
        UsageHistoryStore.shared.fetch(since: selectedPeriod.startDate) { result in
            records = result
        }
    }
}
