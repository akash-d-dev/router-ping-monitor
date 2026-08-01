import Foundation

enum RunState: Equatable {
    case idle
    case running
    case completed
    case failed(String)

    var isRunning: Bool {
        self == .running
    }
}

enum PingEvent: Equatable {
    case reply(sequence: Int, milliseconds: Double, timestamp: Date)
    case timeout(sequence: Int, timestamp: Date)
    case processError(message: String, timestamp: Date)
}

struct TestConfiguration: Equatable {
    let target: String
    let interval: TimeInterval
    let duration: TimeInterval?
}

enum DurationChoice: String, CaseIterable, Identifiable {
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case sixtyMinutes
    case custom
    case infinite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .sixtyMinutes: "60 minutes"
        case .custom: "Custom"
        case .infinite: "Infinite"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1_800
        case .sixtyMinutes: 3_600
        case .custom, .infinite: nil
        }
    }
}

enum CustomDurationUnit: String, CaseIterable, Identifiable {
    case seconds
    case minutes
    case hours

    var id: String { rawValue }

    var multiplier: TimeInterval {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3_600
        }
    }
}

enum ChartDisplayMode: String, CaseIterable, Identifiable {
    case bars
    case line
    case both

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var showsBars: Bool {
        self != .line
    }

    var showsLine: Bool {
        self != .bars
    }
}

enum ChartScaleMode: String, CaseIterable, Identifiable {
    case focus
    case full

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum ChartZoomLevel: String, CaseIterable, Identifiable {
    case seconds30
    case minute1
    case minutes2
    case minutes5
    case minutes15
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seconds30: "30s"
        case .minute1: "1m"
        case .minutes2: "2m"
        case .minutes5: "5m"
        case .minutes15: "15m"
        case .all: "All"
        }
    }

    var fixedDuration: TimeInterval? {
        switch self {
        case .seconds30: 30
        case .minute1: 60
        case .minutes2: 120
        case .minutes5: 300
        case .minutes15: 900
        case .all: nil
        }
    }

    var canZoomIn: Bool {
        self != Self.allCases.first
    }

    var canZoomOut: Bool {
        self != Self.allCases.last
    }

    func zoomedIn() -> ChartZoomLevel {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else { return self }
        return Self.allCases[index - 1]
    }

    func zoomedOut() -> ChartZoomLevel {
        guard let index = Self.allCases.firstIndex(of: self), index + 1 < Self.allCases.count else { return self }
        return Self.allCases[index + 1]
    }
}

struct ChartTimeViewport: Equatable {
    let domain: ClosedRange<Date>
    let visibleDuration: TimeInterval
    let liveScrollPosition: Date

    static func make(
        startedAt: Date,
        lastSampleAt: Date?,
        zoomLevel: ChartZoomLevel
    ) -> ChartTimeViewport {
        let lastSampleAt = max(lastSampleAt ?? startedAt, startedAt)
        let runDuration = lastSampleAt.timeIntervalSince(startedAt)
        let visibleDuration = zoomLevel.fixedDuration ?? max(60, runDuration + 1)
        let domainEnd = max(
            startedAt.addingTimeInterval(visibleDuration),
            lastSampleAt.addingTimeInterval(1)
        )
        let liveScrollPosition = max(
            startedAt,
            domainEnd.addingTimeInterval(-visibleDuration)
        )
        return ChartTimeViewport(
            domain: startedAt...domainEnd,
            visibleDuration: visibleDuration,
            liveScrollPosition: liveScrollPosition
        )
    }
}

enum ChartTooltipAnchor: Equatable {
    case above
    case aboveLeft
    case aboveRight
    case below
    case belowLeft
    case belowRight

    static func make(horizontalFraction: Double, isHigh: Bool) -> ChartTooltipAnchor {
        if horizontalFraction >= 0.78 {
            return isHigh ? .belowLeft : .aboveLeft
        }
        if horizontalFraction <= 0.22 {
            return isHigh ? .belowRight : .aboveRight
        }
        return isHigh ? .below : .above
    }
}

enum ChartHorizontalAnchor: Equatable {
    case leading
    case center
    case trailing

    static func make(horizontalFraction: Double) -> ChartHorizontalAnchor {
        if horizontalFraction <= 0.08 {
            return .leading
        }
        if horizontalFraction >= 0.92 {
            return .trailing
        }
        return .center
    }
}

struct ChartBucket: Identifiable, Equatable {
    let id: UUID
    var start: Date
    var end: Date
    var sentCount: Int
    var replyCount: Int
    var lossCount: Int
    var spikeCount: Int
    var rttSum: Double
    var minimumRTT: Double?
    var maximumRTT: Double?
    var firstSequence: Int
    var lastSequence: Int

    init(reply sequence: Int, milliseconds: Double, spike: Bool, timestamp: Date) {
        id = UUID()
        start = timestamp
        end = timestamp
        sentCount = 1
        replyCount = 1
        lossCount = 0
        spikeCount = spike ? 1 : 0
        rttSum = milliseconds
        minimumRTT = milliseconds
        maximumRTT = milliseconds
        firstSequence = sequence
        lastSequence = sequence
    }

    init(timeout sequence: Int, timestamp: Date) {
        id = UUID()
        start = timestamp
        end = timestamp
        sentCount = 1
        replyCount = 0
        lossCount = 1
        spikeCount = 0
        rttSum = 0
        minimumRTT = nil
        maximumRTT = nil
        firstSequence = sequence
        lastSequence = sequence
    }

    var midpoint: Date {
        Date(timeIntervalSince1970: (start.timeIntervalSince1970 + end.timeIntervalSince1970) / 2)
    }

    var averageRTT: Double? {
        replyCount == 0 ? nil : rttSum / Double(replyCount)
    }

    func merged(with other: ChartBucket) -> ChartBucket {
        var result = self
        result.end = other.end
        result.sentCount += other.sentCount
        result.replyCount += other.replyCount
        result.lossCount += other.lossCount
        result.spikeCount += other.spikeCount
        result.rttSum += other.rttSum
        result.minimumRTT = Self.minimum(minimumRTT, other.minimumRTT)
        result.maximumRTT = Self.maximum(maximumRTT, other.maximumRTT)
        result.lastSequence = other.lastSequence
        return result
    }

    private static func minimum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (left?, right?): Swift.min(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
    }

    private static func maximum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (left?, right?): Swift.max(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
    }
}

struct LatencyLinePoint: Identifiable, Equatable {
    let id: UUID
    let time: Date
    let milliseconds: Double
    let segment: Int
    let isSpike: Bool
}

enum LatencyLinePointBuilder {
    static func make(from buckets: [ChartBucket]) -> [LatencyLinePoint] {
        var segment = 0
        var points: [LatencyLinePoint] = []
        points.reserveCapacity(buckets.count)

        for bucket in buckets {
            if let averageRTT = bucket.averageRTT {
                points.append(
                    LatencyLinePoint(
                        id: bucket.id,
                        time: bucket.midpoint,
                        milliseconds: averageRTT,
                        segment: segment,
                        isSpike: bucket.spikeCount > 0
                    )
                )
            }
            if bucket.lossCount > 0 {
                segment += 1
            }
        }
        return points
    }
}

struct LatencyChartScale: Equatable {
    let ceiling: Double
    let tickStep: Double

    static func make(from buckets: [ChartBucket], mode: ChartScaleMode) -> LatencyChartScale {
        if mode == .focus {
            return LatencyChartScale(ceiling: 50, tickStep: 10)
        }

        let maximum = buckets.compactMap(\.maximumRTT).max() ?? 0
        let ceiling = maximum > 100
            ? ceil((maximum + 50) / 50) * 50
            : 100
        return LatencyChartScale(ceiling: ceiling, tickStep: 50)
    }

    var axisValues: [Double] {
        var values = Array(stride(from: 0, through: ceiling, by: tickStep))
        if values.last != ceiling {
            values.append(ceiling)
        }
        return values
    }

    func displayValue(_ milliseconds: Double) -> Double {
        clips(milliseconds) ? ceiling * 0.96 : milliseconds
    }

    func clips(_ milliseconds: Double) -> Bool {
        milliseconds > ceiling
    }

}

struct RunningMedian: Equatable {
    private(set) var lower: [Double] = []
    private(set) var upper: [Double] = []

    var value: Double? {
        guard !lower.isEmpty else { return nil }
        if lower.count == upper.count {
            return (lower[0] + upper[0]) / 2
        }
        return lower[0]
    }

    mutating func insert(_ value: Double) {
        if lower.first.map({ value <= $0 }) ?? true {
            heapInsert(value, into: &lower, orderedBy: >)
        } else {
            heapInsert(value, into: &upper, orderedBy: <)
        }

        if lower.count > upper.count + 1 {
            heapInsert(heapRemoveRoot(from: &lower, orderedBy: >), into: &upper, orderedBy: <)
        } else if upper.count > lower.count {
            heapInsert(heapRemoveRoot(from: &upper, orderedBy: <), into: &lower, orderedBy: >)
        }
    }

    private func heapInsert(
        _ value: Double,
        into heap: inout [Double],
        orderedBy: (Double, Double) -> Bool
    ) {
        heap.append(value)
        var index = heap.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard orderedBy(heap[index], heap[parent]) else { break }
            heap.swapAt(index, parent)
            index = parent
        }
    }

    private func heapRemoveRoot(
        from heap: inout [Double],
        orderedBy: (Double, Double) -> Bool
    ) -> Double {
        let root = heap[0]
        let last = heap.removeLast()
        guard !heap.isEmpty else { return root }
        heap[0] = last
        var index = 0
        while true {
            let left = index * 2 + 1
            let right = left + 1
            var candidate = index
            if left < heap.count, orderedBy(heap[left], heap[candidate]) {
                candidate = left
            }
            if right < heap.count, orderedBy(heap[right], heap[candidate]) {
                candidate = right
            }
            guard candidate != index else { break }
            heap.swapAt(index, candidate)
            index = candidate
        }
        return root
    }
}

struct TestSession: Equatable {
    static let maximumChartBuckets = 1_200

    var state: RunState = .idle
    var configuration: TestConfiguration?
    var startedAt: Date?
    var endedAt: Date?
    var buckets: [ChartBucket] = []
    var sentCount = 0
    var receivedCount = 0
    var lostCount = 0
    var currentRTT: Double?
    var minimumRTT: Double?
    var maximumRTT: Double?
    var rttSum = 0.0
    var jitterSum = 0.0
    var jitterPairCount = 0
    var previousRTT: Double?
    var median = RunningMedian()
    var processedSequences: Set<Int> = []
    var lastError: String?

    var averageRTT: Double? {
        receivedCount == 0 ? nil : rttSum / Double(receivedCount)
    }

    var jitter: Double? {
        jitterPairCount == 0 ? nil : jitterSum / Double(jitterPairCount)
    }

    var lossPercentage: Double {
        sentCount == 0 ? 0 : Double(lostCount) / Double(sentCount) * 100
    }

    mutating func begin(configuration: TestConfiguration, at date: Date) {
        self = TestSession(
            state: .running,
            configuration: configuration,
            startedAt: date
        )
    }

    mutating func record(_ event: PingEvent) {
        switch event {
        case let .reply(sequence, milliseconds, timestamp):
            guard processedSequences.insert(sequence).inserted else { return }
            let sampleTimestamp = scheduledTimestamp(for: sequence, fallback: timestamp)
            let baselineMedian = median.value
            let isSpike = baselineMedian.map { milliseconds > 20 && milliseconds > $0 * 2 } ?? false
            sentCount += 1
            receivedCount += 1
            currentRTT = milliseconds
            rttSum += milliseconds
            minimumRTT = minimumRTT.map { min($0, milliseconds) } ?? milliseconds
            maximumRTT = maximumRTT.map { max($0, milliseconds) } ?? milliseconds
            if let previousRTT {
                jitterSum += abs(milliseconds - previousRTT)
                jitterPairCount += 1
            }
            self.previousRTT = milliseconds
            median.insert(milliseconds)
            buckets.append(ChartBucket(reply: sequence, milliseconds: milliseconds, spike: isSpike, timestamp: sampleTimestamp))
            compactBucketsIfNeeded()

        case let .timeout(sequence, timestamp):
            guard processedSequences.insert(sequence).inserted else { return }
            let sampleTimestamp = scheduledTimestamp(for: sequence, fallback: timestamp)
            sentCount += 1
            lostCount += 1
            currentRTT = nil
            buckets.append(ChartBucket(timeout: sequence, timestamp: sampleTimestamp))
            compactBucketsIfNeeded()

        case let .processError(message, _):
            lastError = message
        }
    }

    private func scheduledTimestamp(for sequence: Int, fallback: Date) -> Date {
        guard sequence >= 0, let startedAt, let interval = configuration?.interval else {
            return fallback
        }
        return startedAt.addingTimeInterval(Double(sequence) * interval)
    }

    mutating func finish(at date: Date, error: String? = nil) {
        endedAt = date
        if let error {
            state = .failed(error)
            lastError = error
        } else {
            state = .completed
        }
    }

    mutating func compactBucketsIfNeeded() {
        guard buckets.count > Self.maximumChartBuckets else { return }
        var compacted: [ChartBucket] = []
        compacted.reserveCapacity((buckets.count + 1) / 2)
        var index = 0
        while index < buckets.count {
            if index + 1 < buckets.count {
                compacted.append(buckets[index].merged(with: buckets[index + 1]))
            } else {
                compacted.append(buckets[index])
            }
            index += 2
        }
        buckets = compacted
    }
}
