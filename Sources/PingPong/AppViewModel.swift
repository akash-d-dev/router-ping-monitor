import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var session = TestSession()
    @Published private(set) var detectedGateway: String?
    @Published private(set) var gatewayError: String?
    @Published var manualTarget = ""
    @Published var durationChoice: DurationChoice = .oneMinute
    @Published var customDurationValue = 10.0
    @Published var customDurationUnit: CustomDurationUnit = .seconds
    @Published private(set) var validationMessage: String?
    @Published private(set) var now = Date()

    private let gatewayDiscoverer: GatewayDiscovering
    private let pingRunnerFactory: () -> PingRunning
    private var pingRunner: PingRunning?
    private var timer: Timer?
    private var expectedEndDate: Date?
    private var stopping = false

    init(
        gatewayDiscoverer: GatewayDiscovering = DefaultGatewayDiscoverer(),
        pingRunnerFactory: @escaping () -> PingRunning = { SystemPingRunner() }
    ) {
        self.gatewayDiscoverer = gatewayDiscoverer
        self.pingRunnerFactory = pingRunnerFactory
        refreshGateway()
    }

    var activeTarget: String? {
        let entered = manualTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        return entered.isEmpty ? detectedGateway : HostValidator.normalized(entered)
    }

    var elapsed: TimeInterval {
        guard let startedAt = session.startedAt else { return 0 }
        return max(0, (session.endedAt ?? now).timeIntervalSince(startedAt))
    }

    var remaining: TimeInterval? {
        expectedEndDate.map { max(0, $0.timeIntervalSince(now)) }
    }

    var canStart: Bool {
        !session.state.isRunning && activeTarget != nil && customDurationIsValid
    }

    var customDurationIsValid: Bool {
        durationChoice != .custom || (customDurationValue >= 1 && customDurationValue * customDurationUnit.multiplier <= 86_400)
    }

    func refreshGateway() {
        guard !session.state.isRunning else { return }
        do {
            detectedGateway = try gatewayDiscoverer.defaultGateway()
            gatewayError = nil
        } catch {
            detectedGateway = nil
            gatewayError = error.localizedDescription
        }
    }

    func start() {
        guard !session.state.isRunning else { return }
        validationMessage = nil
        guard let target = activeTarget else {
            validationMessage = manualTarget.isEmpty ? "Enter a target because no router was detected." : "Enter a valid hostname or IP address."
            return
        }
        guard customDurationIsValid else {
            validationMessage = "Custom duration must be between 1 second and 24 hours."
            return
        }

        let duration: TimeInterval?
        if durationChoice == .custom {
            duration = customDurationValue * customDurationUnit.multiplier
        } else {
            duration = durationChoice.duration
        }

        let startDate = Date()
        let configuration = TestConfiguration(target: target, interval: 1, duration: duration)
        session.begin(configuration: configuration, at: startDate)
        now = startDate
        expectedEndDate = duration.map { startDate.addingTimeInterval($0) }
        stopping = false

        let runner = pingRunnerFactory()
        runner.eventHandler = { [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        runner.terminationHandler = { [weak self] status in
            Task { @MainActor in self?.runnerTerminated(status: status) }
        }
        pingRunner = runner

        do {
            try runner.start(target: target, interval: configuration.interval)
            startTimer()
        } catch {
            pingRunner = nil
            session.finish(at: Date(), error: error.localizedDescription)
        }
    }

    func stop() {
        finishCurrentTest(error: nil)
    }

    func stopForAppTermination() {
        guard session.state.isRunning else { return }
        stopping = true
        timer?.invalidate()
        timer = nil
        pingRunner?.stop()
        pingRunner = nil
    }

    private func receive(_ event: PingEvent) {
        guard session.state.isRunning else { return }
        session.record(event)
    }

    private func runnerTerminated(status: Int32) {
        guard session.state.isRunning, !stopping else { return }
        finishCurrentTest(error: "Ping stopped unexpectedly with status \(status).")
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                if let expectedEndDate = self.expectedEndDate, self.now >= expectedEndDate {
                    self.finishCurrentTest(error: nil)
                }
            }
        }
    }

    private func finishCurrentTest(error: String?) {
        guard session.state.isRunning else { return }
        stopping = true
        timer?.invalidate()
        timer = nil
        pingRunner?.stop()
        pingRunner = nil
        now = Date()
        session.finish(at: now, error: error)
    }
}
