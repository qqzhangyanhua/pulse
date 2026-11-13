import Darwin
import Foundation

/// Streams `/usr/bin/nettop` while the network page is visible.
/// Fixed path and argument array. No shell. The caller stops it on leave and on quit.
final class NettopReader: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var input: Pipe?
    private var output: FileHandle?
    private var error: FileHandle?
    private var framer = NettopSampleFramer()
    private var pending = Data()
    private var previous: [Int32: ProcessNetworkByteCounts]?
    private var previousAt: Date?
    private var onRates: (([Int32: ProcessNetworkRate]) -> Void)?

    func start(onRates: @escaping ([Int32: ProcessNetworkRate]) -> Void) {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: NettopCommand.executablePath)
        process.arguments = NettopCommand.arguments
        let input = Pipe()
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            return
        }
        let stdout = output.fileHandleForReading
        let stderr = errorPipe.fileHandleForReading
        lock.lock()
        self.process = process
        self.input = input
        self.output = stdout
        self.error = stderr
        self.onRates = onRates
        self.framer = NettopSampleFramer()
        self.pending = Data()
        self.previous = nil
        self.previousAt = nil
        lock.unlock()
        stderr.readabilityHandler = { handle in
            _ = handle.availableData
        }
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
    }

    /// SIGTERM, then SIGKILL if the child is still running. Safe to call twice.
    func stop() {
        let running: Process?
        let stdout: FileHandle?
        let stderr: FileHandle?
        lock.lock()
        running = process
        stdout = output
        stderr = error
        process = nil
        input = nil
        output = nil
        error = nil
        onRates = nil
        framer = NettopSampleFramer()
        pending = Data()
        previous = nil
        previousAt = nil
        lock.unlock()
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        guard let running else { return }
        if running.isRunning {
            running.terminate()
        }
        if running.isRunning {
            kill(running.processIdentifier, SIGKILL)
        }
        running.waitUntilExit()
    }

    private func consume(_ data: Data) {
        lock.lock()
        pending.append(data)
        var samples: [String] = []
        while let newline = pending.firstIndex(of: 10) {
            let chunk = pending.prefix(upTo: newline)
            pending.removeSubrange(pending.startIndex...newline)
            var line = String(decoding: chunk, as: UTF8.self)
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            if let sample = framer.append(line) {
                samples.append(sample)
            }
        }
        lock.unlock()
        for sample in samples {
            publish(sample)
        }
    }

    private func publish(_ text: String) {
        guard case .counts(let counts) = NettopDecoder.decode(text) else { return }
        let now = Date()
        lock.lock()
        let rates: [Int32: ProcessNetworkRate]?
        if let previous, let previousAt {
            rates = ProcessNetworkRateMath.perSecond(
                previous: previous,
                current: counts,
                elapsedSeconds: now.timeIntervalSince(previousAt)
            )
        } else {
            rates = nil
        }
        previous = counts
        previousAt = now
        let callback = onRates
        lock.unlock()
        if let rates, let callback {
            callback(rates)
        }
    }
}
