import Foundation

private struct TestFailure: Error {
    let message: String
}

@main
enum StandaloneTests {
    private static var completed = 0

    static func main() throws {
        try run("gateway parsing", testGatewayParsing)
        try run("missing gateway", testMissingGateway)
        try run("ping parsing", testPingParsing)
        try run("statistics and loss", testStatisticsAndLoss)
        try run("sequence-aligned sample timing", testSequenceAlignedSampleTiming)
        try run("adaptive buckets", testAdaptiveBuckets)
        try run("loss-aware line segments", testLossAwareLineSegments)
        try run("fixed and expanding latency scale", testLatencyScale)
        try run("chart time viewport", testChartTimeViewport)
        try run("chart tooltip anchoring", testChartTooltipAnchoring)
        try run("chart axis anchoring", testChartAxisAnchoring)
        try run("host validation", testHostValidation)
        print("Passed \(completed) tests")
    }

    private static func run(_ name: String, _ test: () throws -> Void) throws {
        do {
            try test()
            completed += 1
            print("PASS \(name)")
        } catch {
            print("FAIL \(name): \(error)")
            throw error
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
        try expect(actual == expected, "\(message). Expected \(expected), got \(actual)")
    }

    private static func expectClose(_ actual: Double?, _ expected: Double, _ message: String) throws {
        guard let actual else { throw TestFailure(message: "\(message). Value was nil") }
        try expect(abs(actual - expected) < 0.001, "\(message). Expected \(expected), got \(actual)")
    }

    private static func testGatewayParsing() throws {
        let output = """
           route to: default
        destination: default
            gateway: 192.168.1.1
          interface: en0
        """
        try expectEqual(try DefaultGatewayDiscoverer.parseGateway(from: output), "192.168.1.1", "Gateway mismatch")
    }

    private static func testMissingGateway() throws {
        do {
            _ = try DefaultGatewayDiscoverer.parseGateway(from: "route to: default")
            throw TestFailure(message: "Missing gateway did not throw")
        } catch GatewayDiscoveryError.gatewayMissing {
        }
    }

    private static func testPingParsing() throws {
        let parser = PingOutputParser()
        let date = Date(timeIntervalSince1970: 10)
        try expectEqual(
            parser.parse(line: "64 bytes from 192.168.1.1: icmp_seq=16 ttl=64 time=93.011 ms", timestamp: date),
            .reply(sequence: 16, milliseconds: 93.011, timestamp: date),
            "IPv4 reply mismatch"
        )
        try expectEqual(
            parser.parse(line: "64 bytes from fe80::1: icmp_seq=3 hlim=64 time=4.210 ms", timestamp: date),
            .reply(sequence: 3, milliseconds: 4.210, timestamp: date),
            "IPv6 reply mismatch"
        )
        try expectEqual(
            parser.parse(line: "Request timeout for icmp_seq 8", timestamp: date),
            .timeout(sequence: 8, timestamp: date),
            "Timeout mismatch"
        )
        try expectEqual(
            parser.parse(line: "ping: cannot resolve bad.invalid: Unknown host", timestamp: date),
            .processError(message: "ping: cannot resolve bad.invalid: Unknown host", timestamp: date),
            "Process error mismatch"
        )
    }

    private static func testStatisticsAndLoss() throws {
        var session = TestSession()
        session.begin(configuration: TestConfiguration(target: "router", interval: 1, duration: 60), at: Date())
        session.record(.reply(sequence: 0, milliseconds: 5, timestamp: Date()))
        session.record(.reply(sequence: 1, milliseconds: 7, timestamp: Date()))
        session.record(.timeout(sequence: 2, timestamp: Date()))
        session.record(.reply(sequence: 3, milliseconds: 30, timestamp: Date()))
        session.record(.timeout(sequence: 2, timestamp: Date()))

        try expectEqual(session.sentCount, 4, "Sent count mismatch")
        try expectEqual(session.receivedCount, 3, "Received count mismatch")
        try expectEqual(session.lostCount, 1, "Lost count mismatch")
        try expectClose(session.minimumRTT, 5, "Minimum mismatch")
        try expectClose(session.maximumRTT, 30, "Maximum mismatch")
        try expectClose(session.averageRTT, 14, "Average mismatch")
        try expectClose(session.median.value, 7, "Median mismatch")
        try expectClose(session.jitter, 12.5, "Jitter mismatch")
        try expectClose(session.lossPercentage, 25, "Loss percentage mismatch")
        try expectEqual(session.buckets.last?.spikeCount, 1, "Spike count mismatch")
    }

    private static func testSequenceAlignedSampleTiming() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var session = TestSession()
        session.begin(
            configuration: TestConfiguration(target: "router", interval: 1, duration: 60),
            at: start
        )

        session.record(.reply(sequence: 0, milliseconds: 8, timestamp: start))
        session.record(.timeout(sequence: 1, timestamp: start.addingTimeInterval(3)))
        session.record(.timeout(sequence: 2, timestamp: start.addingTimeInterval(4)))
        session.record(.reply(sequence: 3, milliseconds: 9, timestamp: start.addingTimeInterval(4.01)))

        let offsets = session.buckets.map { $0.midpoint.timeIntervalSince(start) }
        try expectEqual(offsets, [0, 1, 2, 3], "Delayed timeout output changed chart spacing")
        try expectEqual(session.sentCount, 4, "Sequence timing changed sent count")
        try expectEqual(session.receivedCount, 2, "Sequence timing changed received count")
        try expectEqual(session.lostCount, 2, "Sequence timing changed lost count")
    }

    private static func testAdaptiveBuckets() throws {
        var session = TestSession()
        session.begin(configuration: TestConfiguration(target: "router", interval: 1, duration: nil), at: Date())
        for sequence in 0...1_200 {
            if sequence.isMultiple(of: 10) {
                session.record(.timeout(sequence: sequence, timestamp: Date(timeIntervalSince1970: Double(sequence))))
            } else {
                session.record(.reply(sequence: sequence, milliseconds: Double(sequence % 50 + 1), timestamp: Date(timeIntervalSince1970: Double(sequence))))
            }
        }

        try expect(session.buckets.count <= TestSession.maximumChartBuckets, "Bucket limit exceeded")
        try expectEqual(session.buckets.reduce(0) { $0 + $1.sentCount }, session.sentCount, "Compacted sent count mismatch")
        try expectEqual(session.buckets.reduce(0) { $0 + $1.replyCount }, session.receivedCount, "Compacted reply count mismatch")
        try expectEqual(session.buckets.reduce(0) { $0 + $1.lossCount }, session.lostCount, "Compacted loss count mismatch")
    }

    private static func testLossAwareLineSegments() throws {
        let start = Date(timeIntervalSince1970: 100)
        let buckets = [
            ChartBucket(reply: 0, milliseconds: 5, spike: false, timestamp: start),
            ChartBucket(reply: 1, milliseconds: 8, spike: false, timestamp: start.addingTimeInterval(1)),
            ChartBucket(timeout: 2, timestamp: start.addingTimeInterval(2)),
            ChartBucket(reply: 3, milliseconds: 20, spike: true, timestamp: start.addingTimeInterval(3))
        ]
        let points = LatencyLinePointBuilder.make(from: buckets)

        try expectEqual(points.count, 3, "Line point count mismatch")
        try expectEqual(points.map(\.segment), [0, 0, 1], "Line did not break across loss")
        try expectEqual(points.map(\.milliseconds), [5, 8, 20], "Line latency mismatch")
        try expectEqual(points.last?.isSpike, true, "Line spike mismatch")
    }

    private static func testLatencyScale() throws {
        let start = Date(timeIntervalSince1970: 200)
        var buckets = (0..<39).map {
            ChartBucket(reply: $0, milliseconds: 10, spike: false, timestamp: start.addingTimeInterval(Double($0)))
        }
        buckets.append(ChartBucket(reply: 39, milliseconds: 267, spike: true, timestamp: start.addingTimeInterval(39)))

        let focused = LatencyChartScale.make(from: buckets, mode: .focus)
        let full = LatencyChartScale.make(from: buckets, mode: .full)

        try expectEqual(focused.ceiling, 50, "Focus scale ceiling mismatch")
        try expectEqual(focused.tickStep, 10, "Focus scale tick step mismatch")
        try expectEqual(focused.axisValues, [0, 10, 20, 30, 40, 50], "Focus scale axis values mismatch")
        try expect(focused.clips(267), "Focused scale did not mark the outlier as clipped")
        try expect(focused.displayValue(267) < focused.ceiling, "Clipped outlier exceeded the focused scale")
        try expectEqual(full.ceiling, 350, "Full scale did not add and round its headroom")
        try expectEqual(full.tickStep, 50, "Full scale did not use 50 ms ticks")
        try expectEqual(full.axisValues, [0, 50, 100, 150, 200, 250, 300, 350], "Full scale axis values mismatch")
        try expect(!full.clips(267), "Full scale incorrectly clipped the outlier")
        try expectEqual(full.displayValue(267), 267, "Full scale changed the maximum display value")

        buckets.append(ChartBucket(reply: 40, milliseconds: 620, spike: true, timestamp: start.addingTimeInterval(40)))
        let expandedFull = LatencyChartScale.make(from: buckets, mode: .full)
        try expectEqual(expandedFull.ceiling, 700, "Full scale did not round expanded headroom to 50 ms")
        try expectEqual(expandedFull.tickStep, 50, "Expanded Full scale changed its 50 ms ticks")

        let emptyFull = LatencyChartScale.make(from: [], mode: .full)
        try expectEqual(emptyFull.ceiling, 100, "Empty Full scale did not use its initial 100 ms range")
        try expectEqual(emptyFull.axisValues, [0, 50, 100], "Empty Full axis values mismatch")

        let lowFull = LatencyChartScale.make(
            from: [ChartBucket(reply: 0, milliseconds: 8.7, spike: false, timestamp: start)],
            mode: .full
        )
        try expectEqual(lowFull.ceiling, 100, "Low-latency Full scale dropped below 100 ms")
        try expectEqual(lowFull.axisValues, [0, 50, 100], "Low-latency Full axis values mismatch")

        var ordinaryBuckets = (0..<18).map {
            ChartBucket(reply: $0, milliseconds: 10, spike: false, timestamp: start.addingTimeInterval(Double($0)))
        }
        ordinaryBuckets.append(ChartBucket(reply: 18, milliseconds: 27, spike: true, timestamp: start.addingTimeInterval(18)))
        ordinaryBuckets.append(ChartBucket(reply: 19, milliseconds: 28.2, spike: true, timestamp: start.addingTimeInterval(19)))
        ordinaryBuckets.append(ChartBucket(reply: 20, milliseconds: 100, spike: true, timestamp: start.addingTimeInterval(20)))
        let boundaryFull = LatencyChartScale.make(from: ordinaryBuckets, mode: .full)
        try expectEqual(boundaryFull.ceiling, 100, "A 100 ms value expanded the Full ceiling")

        ordinaryBuckets.append(ChartBucket(reply: 21, milliseconds: 198, spike: true, timestamp: start.addingTimeInterval(21)))
        let roundedSpikeFull = LatencyChartScale.make(from: ordinaryBuckets, mode: .full)
        try expectEqual(roundedSpikeFull.ceiling, 250, "A 198 ms spike did not produce a 250 ms Full ceiling")
        try expectEqual(roundedSpikeFull.axisValues, [0, 50, 100, 150, 200, 250], "Expanded Full axis values mismatch")
    }

    private static func testChartTimeViewport() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let early = ChartTimeViewport.make(
            startedAt: start,
            lastSampleAt: start.addingTimeInterval(2),
            zoomLevel: .minute1
        )
        try expectClose(early.domain.upperBound.timeIntervalSince(start), 60, "Early chart did not reserve a one-minute window")
        try expectEqual(early.liveScrollPosition, start, "Early chart did not begin at the left edge")

        let long = ChartTimeViewport.make(
            startedAt: start,
            lastSampleAt: start.addingTimeInterval(180),
            zoomLevel: .minute1
        )
        try expectClose(long.visibleDuration, 60, "Long chart visible duration mismatch")
        try expectClose(long.liveScrollPosition.timeIntervalSince(start), 121, "Long chart did not follow the latest sample")

        let all = ChartTimeViewport.make(
            startedAt: start,
            lastSampleAt: start.addingTimeInterval(180),
            zoomLevel: .all
        )
        try expectClose(all.visibleDuration, 181, "All zoom did not include the complete run")
        try expectEqual(all.liveScrollPosition, start, "All zoom did not start from the beginning")
        try expectEqual(ChartZoomLevel.minute1.zoomedIn(), .seconds30, "Zoom in mismatch")
        try expectEqual(ChartZoomLevel.minute1.zoomedOut(), .minutes2, "Zoom out mismatch")
    }

    private static func testChartTooltipAnchoring() throws {
        try expectEqual(
            ChartTooltipAnchor.make(horizontalFraction: 0.9, isHigh: false),
            .aboveLeft,
            "Right-edge tooltip did not extend left"
        )
        try expectEqual(
            ChartTooltipAnchor.make(horizontalFraction: 0.1, isHigh: false),
            .aboveRight,
            "Left-edge tooltip did not extend right"
        )
        try expectEqual(
            ChartTooltipAnchor.make(horizontalFraction: 0.5, isHigh: true),
            .below,
            "High middle tooltip did not move below its point"
        )
    }

    private static func testChartAxisAnchoring() throws {
        try expectEqual(ChartHorizontalAnchor.make(horizontalFraction: 0), .leading, "Left-edge axis label did not extend inward")
        try expectEqual(ChartHorizontalAnchor.make(horizontalFraction: 0.5), .center, "Middle axis label was not centered")
        try expectEqual(ChartHorizontalAnchor.make(horizontalFraction: 1), .trailing, "Right-edge axis label did not extend inward")
    }

    private static func testHostValidation() throws {
        try expectEqual(HostValidator.normalized(" 192.168.1.1 "), "192.168.1.1", "IPv4 validation mismatch")
        try expectEqual(HostValidator.normalized("router.local"), "router.local", "Hostname validation mismatch")
        try expectEqual(HostValidator.normalized("fe80::1%en0"), "fe80::1%en0", "IPv6 validation mismatch")
        try expect(HostValidator.normalized("-n") == nil, "Option-like host was accepted")
        try expect(HostValidator.normalized("router; shutdown") == nil, "Unsafe host was accepted")
    }
}
