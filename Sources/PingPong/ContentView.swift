import Charts
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTime: Date?
    @State private var chartMode: ChartDisplayMode = .both
    @State private var chartScaleMode: ChartScaleMode = .focus
    @State private var zoomLevel: ChartZoomLevel = .minute1
    @State private var chartScrollPosition = Date()
    @State private var pendingScrollPosition: Date?
    @State private var followsLive = true

    private let cyan = Color(red: 0.12, green: 0.80, blue: 0.88)
    private let panel = Color(red: 0.08, green: 0.11, blue: 0.12)
    private let canvas = Color(red: 0.045, green: 0.065, blue: 0.07)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    header
                    controls
                    if let validationMessage = viewModel.validationMessage {
                        message(validationMessage, color: .red)
                    } else if let gatewayError = viewModel.gatewayError, viewModel.manualTarget.isEmpty {
                        message(gatewayError + " Enter a target manually to continue.", color: .orange)
                    }
                    summary
                    chartPanel(height: max(340, geometry.size.height - 470))
                }
                .padding(24)
            }
        }
        .background(canvas.ignoresSafeArea())
        .foregroundStyle(.white)
        .frame(minWidth: 940, minHeight: 700)
        .onDisappear { viewModel.stopForAppTermination() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.stopForAppTermination()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Ping-Pong")
                    .font(.system(size: 27, weight: .bold))
                Text("Live ICMP latency and packet-loss testing")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        Text(statusText)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(statusColor.opacity(0.18), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ROUTER")
                        .captionStyle()
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.router")
                            .foregroundStyle(cyan)
                        Text(viewModel.detectedGateway ?? "Not detected")
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                        Button {
                            viewModel.refreshGateway()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.session.state.isRunning)
                        .help("Refresh detected router")
                    }
                    .frame(height: 28)
                }
                .frame(minWidth: 190, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("MANUAL TARGET")
                        .captionStyle()
                    TextField("Optional hostname or IP", text: $viewModel.manualTarget)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                        .disabled(viewModel.session.state.isRunning)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("DURATION")
                        .captionStyle()
                    Picker("", selection: $viewModel.durationChoice) {
                        ForEach(DurationChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(viewModel.session.state.isRunning)
                }

                Button(action: primaryAction) {
                    HStack(spacing: 7) {
                        Image(systemName: viewModel.session.state.isRunning ? "stop.fill" : "play.fill")
                        Text(viewModel.session.state.isRunning ? "Stop test" : "Start test")
                    }
                    .fontWeight(.semibold)
                    .frame(width: 120, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.session.state.isRunning ? .red : cyan)
                .disabled(!viewModel.session.state.isRunning && !viewModel.canStart)
            }

            if viewModel.durationChoice == .custom, !viewModel.session.state.isRunning {
                HStack {
                    Spacer()
                    Text("Custom duration")
                        .foregroundStyle(.secondary)
                    TextField("10", value: $viewModel.customDurationValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Picker("", selection: $viewModel.customDurationUnit) {
                        ForEach(CustomDurationUnit.allCases) { unit in
                            Text(unit.rawValue.capitalized).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                metricLabel("Target", value: viewModel.session.configuration?.target ?? viewModel.activeTarget ?? "-")
                Spacer()
                metricLabel("Elapsed", value: formatDuration(viewModel.elapsed))
                Spacer()
                metricLabel("Remaining", value: viewModel.remaining.map(formatDuration) ?? (viewModel.session.state.isRunning ? "No limit" : "-"))
            }
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
    }

    private var summary: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                StatCard(title: "CURRENT", value: formatMilliseconds(viewModel.session.currentRTT), accent: cyan)
                StatCard(title: "MEDIAN", value: formatMilliseconds(viewModel.session.median.value), accent: cyan)
                StatCard(title: "MIN", value: formatMilliseconds(viewModel.session.minimumRTT), accent: .white)
                StatCard(title: "AVERAGE", value: formatMilliseconds(viewModel.session.averageRTT), accent: .white)
                StatCard(title: "MAX", value: formatMilliseconds(viewModel.session.maximumRTT), accent: .orange)
                StatCard(title: "JITTER", value: formatMilliseconds(viewModel.session.jitter), accent: .white)
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack(spacing: 0) {
                StatCard(title: "SENT", value: "\(viewModel.session.sentCount)", accent: .white)
                StatCard(title: "RECEIVED", value: "\(viewModel.session.receivedCount)", accent: cyan)
                StatCard(title: "LOST", value: "\(viewModel.session.lostCount)", accent: .red)
                StatCard(title: "PACKET LOSS", value: String(format: "%.1f%%", viewModel.session.lossPercentage), accent: viewModel.session.lostCount > 0 ? .red : cyan)
            }
        }
        .background(panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chartPanel(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latency")
                    .font(.headline)
                Text("1 ping per second")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Chart display", selection: $chartMode) {
                    ForEach(ChartDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
                Text("Scale")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Chart scale", selection: $chartScaleMode) {
                    ForEach(ChartScaleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                .help("Focus uses 0-50 ms. Full starts at 0-100 ms and expands for larger spikes.")
                zoomControls
                Button {
                    followsLive = true
                    scrollToLive()
                } label: {
                    Label("Live", systemImage: "arrow.right.to.line")
                }
                .buttonStyle(.bordered)
                .tint(followsLive ? cyan : .secondary)
                .help("Follow the newest sample")
            }

            HStack(spacing: 12) {
                Spacer()
                legend(color: cyan, text: "Normal", symbol: .circle)
                legend(color: .orange, text: "Spike", symbol: .circle)
                legend(color: .red, text: "Clipped", symbol: .circle)
                legend(color: .red, text: "Lost packet", symbol: .bar)
            }

            if viewModel.session.buckets.isEmpty {
                ContentUnavailableView(
                    "No samples yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Start a test to plot router latency.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 14)
            }
        }
        .frame(height: height)
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
    }

    private var chart: some View {
        Chart {
            if chartMode.showsBars {
                ForEach(viewModel.session.buckets) { bucket in
                    if let average = bucket.averageRTT {
                        BarMark(
                            x: .value("Time", bucket.midpoint),
                            y: .value("Latency", chartScale.displayValue(average))
                        )
                        .foregroundStyle(bucket.spikeCount > 0 ? Color.orange : cyan)
                        .opacity(chartMode == .both ? 0.62 : 0.9)
                    }
                }
            }

            if chartMode.showsLine {
                ForEach(linePoints) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Latency", chartScale.displayValue(point.milliseconds)),
                        series: .value("Connected segment", point.segment)
                    )
                    .foregroundStyle(cyan)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)

                    if point.isSpike {
                        PointMark(
                            x: .value("Spike time", point.time),
                            y: .value("Spike latency", chartScale.displayValue(point.milliseconds))
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(42)
                    }
                }
            }

            ForEach(viewModel.session.buckets) { bucket in
                if let maximum = bucket.maximumRTT, chartScale.clips(maximum) {
                    PointMark(
                        x: .value("Outlier time", bucket.midpoint),
                        y: .value("Outlier", chartScale.displayValue(maximum))
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)
                    .symbolSize(58)
                }
            }

            ForEach(viewModel.session.buckets) { bucket in
                if bucket.lossCount > 0 {
                    if chartMode.showsBars {
                        BarMark(
                            x: .value("Loss time", bucket.midpoint),
                            y: .value("Lost packet", chartScale.ceiling),
                            width: .fixed(chartMode == .both ? 6 : 8)
                        )
                        .foregroundStyle(Color.red.opacity(chartMode == .both ? 0.52 : 0.82))
                        .cornerRadius(2)
                    }

                    if chartMode == .line {
                        RuleMark(x: .value("Loss time", bucket.midpoint))
                            .foregroundStyle(Color.red.opacity(0.72))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))

                        PointMark(
                            x: .value("Loss time", bucket.midpoint),
                            y: .value("Lost packet baseline", chartScale.ceiling * 0.015)
                        )
                        .foregroundStyle(.red)
                        .symbol(.diamond)
                        .symbolSize(72)
                    }
                }
            }

            if let bucket = selectedBucket {
                PointMark(
                    x: .value("Selected time", bucket.midpoint),
                    y: .value("Selected latency", selectedMarkerY(for: bucket))
                )
                .foregroundStyle(.white)
                .symbolSize(32)
                .annotation(
                    position: tooltipPosition(for: bucket),
                    spacing: 9,
                    overflowResolution: AnnotationOverflowResolution(
                        x: .fit(to: .chart),
                        y: .fit(to: .chart)
                    )
                ) {
                    chartTooltip(bucket)
                }
            }
        }
        .chartXScale(domain: chartViewport.domain)
        .chartYScale(domain: 0...chartScale.ceiling)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: chartViewport.visibleDuration)
        .chartScrollPosition(x: $chartScrollPosition)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel(
                    format: .dateTime.hour().minute().second(),
                    anchor: xAxisLabelAnchor(for: value.as(Date.self))
                )
            }
        }
        .chartYAxis {
            AxisMarks(values: chartScale.axisValues) {
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel()
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
        }
        .chartXSelection(value: $selectedTime)
        .onChange(of: viewModel.session.buckets.count) { _, count in
            handleBucketCountChange(count)
        }
        .onChange(of: zoomLevel) { _, _ in
            if followsLive {
                scrollToLive()
            }
        }
        .onChange(of: chartScrollPosition) { _, position in
            handleScrollPositionChange(position)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                zoomLevel = zoomLevel.zoomedOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .disabled(!zoomLevel.canZoomOut)
            .help("Zoom out")

            Text(zoomLevel.title)
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(minWidth: 28)

            Button {
                zoomLevel = zoomLevel.zoomedIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .disabled(!zoomLevel.canZoomIn)
            .help("Zoom in")
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }

    private var linePoints: [LatencyLinePoint] {
        LatencyLinePointBuilder.make(from: viewModel.session.buckets)
    }

    private var chartScale: LatencyChartScale {
        LatencyChartScale.make(from: viewModel.session.buckets, mode: chartScaleMode)
    }

    private var chartViewport: ChartTimeViewport {
        let start = viewModel.session.startedAt ?? viewModel.session.buckets.first?.start ?? Date()
        return ChartTimeViewport.make(
            startedAt: start,
            lastSampleAt: viewModel.session.buckets.last?.end,
            zoomLevel: zoomLevel
        )
    }

    private var selectedBucket: ChartBucket? {
        guard let selectedTime else { return nil }
        return viewModel.session.buckets.min {
            abs($0.midpoint.timeIntervalSince(selectedTime)) < abs($1.midpoint.timeIntervalSince(selectedTime))
        }
    }

    private func selectedMarkerY(for bucket: ChartBucket) -> Double {
        if let averageRTT = bucket.averageRTT {
            return chartScale.displayValue(averageRTT)
        }
        return chartScale.ceiling * 0.03
    }

    private func tooltipPosition(for bucket: ChartBucket) -> AnnotationPosition {
        let visibleStart = zoomLevel == .all ? chartViewport.domain.lowerBound : chartScrollPosition
        let elapsed = bucket.midpoint.timeIntervalSince(visibleStart)
        let fraction = elapsed / max(1, chartViewport.visibleDuration)
        let isHigh = selectedMarkerY(for: bucket) > chartScale.ceiling * 0.72
        return switch ChartTooltipAnchor.make(horizontalFraction: fraction, isHigh: isHigh) {
        case .above: .top
        case .aboveLeft: .topLeading
        case .aboveRight: .topTrailing
        case .below: .bottom
        case .belowLeft: .bottomLeading
        case .belowRight: .bottomTrailing
        }
    }

    private func xAxisLabelAnchor(for date: Date?) -> UnitPoint {
        guard let date else { return .top }
        let visibleStart = zoomLevel == .all ? chartViewport.domain.lowerBound : chartScrollPosition
        let fraction = date.timeIntervalSince(visibleStart) / max(1, chartViewport.visibleDuration)
        return switch ChartHorizontalAnchor.make(horizontalFraction: fraction) {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }

    private func handleBucketCountChange(_ count: Int) {
        if count == 0 {
            selectedTime = nil
            followsLive = true
        }
        if followsLive {
            scrollToLive()
        }
    }

    private func scrollToLive() {
        let position = chartViewport.liveScrollPosition
        pendingScrollPosition = position
        chartScrollPosition = position
    }

    private func handleScrollPositionChange(_ position: Date) {
        if let pendingScrollPosition,
           abs(position.timeIntervalSince(pendingScrollPosition)) < 2 {
            self.pendingScrollPosition = nil
            return
        }
        pendingScrollPosition = nil
        followsLive = false
    }

    private func chartTooltip(_ bucket: ChartBucket) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(bucket.midpoint.formatted(date: .omitted, time: .standard))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatMilliseconds(bucket.averageRTT))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(bucket.lossCount > 0 ? .red : .white)
            HStack(spacing: 9) {
                Text("Seq \(bucket.firstSequence)\(bucket.lastSequence == bucket.firstSequence ? "" : "-\(bucket.lastSequence)")")
                Text("Min \(formatMilliseconds(bucket.minimumRTT))")
                Text("Max \(formatMilliseconds(bucket.maximumRTT))")
            }
            .font(.caption2.monospacedDigit())
            if bucket.lossCount > 0 {
                Text("Lost \(bucket.lossCount)/\(bucket.sentCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            } else if let maximumRTT = bucket.maximumRTT, chartScale.clips(maximumRTT) {
                Text("Outlier clipped by Focus scale")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(red: 0.055, green: 0.075, blue: 0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.16)))
        .shadow(color: .black.opacity(0.38), radius: 8, y: 3)
    }

    private func primaryAction() {
        if viewModel.session.state.isRunning {
            viewModel.stop()
        } else {
            viewModel.start()
        }
    }

    private func message(_ text: String, color: Color) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(color)
        .padding(.horizontal, 4)
    }

    private func metricLabel(_ label: String, value: String) -> some View {
        HStack(spacing: 7) {
            Text(label.uppercased())
                .captionStyle()
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .medium))
        }
    }

    private func legend(color: Color, text: String, symbol: LegendSymbol) -> some View {
        HStack(spacing: 5) {
            Group {
                switch symbol {
                case .circle:
                    Circle().fill(color)
                case .bar:
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                }
            }
            .frame(width: symbol == .bar ? 4 : 7, height: symbol == .bar ? 10 : 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch viewModel.session.state {
        case .idle: "READY"
        case .running: "RUNNING"
        case .completed: "COMPLETED"
        case .failed: "FAILED"
        }
    }

    private var statusColor: Color {
        switch viewModel.session.state {
        case .idle: .secondary
        case .running: cyan
        case .completed: .green
        case .failed: .red
        }
    }

    private func formatMilliseconds(_ value: Double?) -> String {
        value.map { String(format: $0 < 100 ? "%.1f ms" : "%.0f ms", $0) } ?? "-"
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}

private enum LegendSymbol {
    case circle
    case bar
}

private struct StatCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).captionStyle()
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
        }
    }
}

private extension View {
    func captionStyle() -> some View {
        font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }
}
