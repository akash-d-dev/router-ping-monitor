import Foundation

protocol GatewayDiscovering {
    func defaultGateway() throws -> String
}

enum GatewayDiscoveryError: LocalizedError {
    case commandFailed(String)
    case gatewayMissing

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message): message
        case .gatewayMissing: "No active default router was found."
        }
    }
}

struct DefaultGatewayDiscoverer: GatewayDiscovering {
    func defaultGateway() throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GatewayDiscoveryError.commandFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Self.parseGateway(from: stdout)
    }

    static func parseGateway(from output: String) throws -> String {
        for line in output.split(whereSeparator: \ .isNewline) {
            let parts = line.split(whereSeparator: \ .isWhitespace)
            if parts.count >= 2, parts[0] == "gateway:" {
                return String(parts[1])
            }
        }
        throw GatewayDiscoveryError.gatewayMissing
    }
}

enum HostValidator {
    static func normalized(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 253, value.first != "-" else { return nil }
        guard value.unicodeScalars.allSatisfy({ scalar in
            CharacterSet.alphanumerics.contains(scalar) || ".-_:%".unicodeScalars.contains(scalar)
        }) else { return nil }
        guard !value.contains("..") else { return nil }
        return value
    }
}

struct PingOutputParser {
    func parse(line: String, timestamp: Date = Date()) -> PingEvent? {
        if let sequence = captureInteger(pattern: #"icmp_seq[= ](\d+)"#, in: line),
           let milliseconds = captureDouble(pattern: #"time[=<]([0-9.]+)\s*ms"#, in: line) {
            return .reply(sequence: sequence, milliseconds: milliseconds, timestamp: timestamp)
        }

        if line.localizedCaseInsensitiveContains("timeout"),
           let sequence = captureInteger(pattern: #"icmp_seq[= ](\d+)"#, in: line) {
            return .timeout(sequence: sequence, timestamp: timestamp)
        }

        let lowercased = line.lowercased()
        if lowercased.hasPrefix("ping:") || lowercased.contains("sendto:") {
            return .processError(message: line, timestamp: timestamp)
        }
        return nil
    }

    private func captureInteger(pattern: String, in line: String) -> Int? {
        capture(pattern: pattern, in: line).flatMap(Int.init)
    }

    private func captureDouble(pattern: String, in line: String) -> Double? {
        capture(pattern: pattern, in: line).flatMap(Double.init)
    }

    private func capture(pattern: String, in line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }
}

protocol PingRunning: AnyObject {
    var eventHandler: ((PingEvent) -> Void)? { get set }
    var terminationHandler: ((Int32) -> Void)? { get set }
    var isRunning: Bool { get }
    func start(target: String, interval: TimeInterval) throws
    func stop()
}

final class SystemPingRunner: PingRunning, @unchecked Sendable {
    var eventHandler: ((PingEvent) -> Void)?
    var terminationHandler: ((Int32) -> Void)?

    private let parser = PingOutputParser()
    private let lock = NSLock()
    private var process: Process?
    private var outputBuffer = ""
    private var stoppedIntentionally = false

    var isRunning: Bool {
        lock.withLock { process?.isRunning ?? false }
    }

    func start(target: String, interval: TimeInterval) throws {
        stop()
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-n", "-i", String(format: "%.3f", interval), "-W", "1000", target]
        process.standardOutput = output
        process.standardError = error
        stoppedIntentionally = false
        outputBuffer = ""

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] finishedProcess in
            output.fileHandleForReading.readabilityHandler = nil
            error.fileHandleForReading.readabilityHandler = nil
            self?.flushBuffer()
            self?.handleTermination(status: finishedProcess.terminationStatus)
        }
        lock.withLock { self.process = process }
        try process.run()
    }

    func stop() {
        let runningProcess = lock.withLock { () -> Process? in
            stoppedIntentionally = true
            return process
        }
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        let lines: [String] = lock.withLock {
            outputBuffer.append(chunk)
            var completed: [String] = []
            while let newline = outputBuffer.firstIndex(of: "\n") {
                completed.append(String(outputBuffer[..<newline]))
                outputBuffer.removeSubrange(...newline)
            }
            return completed
        }
        emit(lines)
    }

    private func flushBuffer() {
        let remainder: String = lock.withLock {
            defer { outputBuffer = "" }
            return outputBuffer
        }
        if !remainder.isEmpty {
            emit([remainder])
        }
    }

    private func emit(_ lines: [String]) {
        for line in lines {
            if let event = parser.parse(line: line) {
                eventHandler?(event)
            }
        }
    }

    private func handleTermination(status: Int32) {
        let intentional = lock.withLock { () -> Bool in
            process = nil
            return stoppedIntentionally
        }
        if !intentional {
            terminationHandler?(status)
        }
    }
}
