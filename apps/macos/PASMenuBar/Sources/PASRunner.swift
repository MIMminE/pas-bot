import AppKit
import Combine
import Foundation

@MainActor
final class PASRunner: ObservableObject {
    @Published var isRunning = false
    @Published var status = "Idle"
    @Published var lastOutput = ""

    private let fileManager = FileManager.default

    func run(_ arguments: [String]) {
        guard !isRunning else { return }
        isRunning = true
        status = "Running..."

        Task.detached { [weak self] in
            guard let self else { return }
            let result = self.execute(arguments)
            await MainActor.run {
                self.lastOutput = result.output
                self.status = result.succeeded ? "Success" : "Failed: \(result.summary)"
                self.isRunning = false
            }
        }
    }

    func openSupportDirectory() {
        let directory = supportDirectory()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func copyLastOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastOutput, forType: .string)
        status = "Last output copied"
    }

    private nonisolated func execute(_ arguments: [String]) -> (succeeded: Bool, output: String, summary: String) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        let executable = pasExecutable()
        process.executableURL = executable.url
        process.arguments = executable.prefixArguments + [
            "--config",
            configURL().path,
            "--env",
            envURL().path
        ] + arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try prepareSupportFiles()
            try process.run()
            process.waitUntilExit()
        } catch {
            let message = error.localizedDescription
            return (false, message, message)
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
        let summary = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus == 0, combined, summary.isEmpty ? "No output" : summary)
    }

    private nonisolated func prepareSupportFiles() throws {
        let directory = supportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: snapshotsDirectory(), withIntermediateDirectories: true)

        copyExampleIfNeeded(resourcePath: "config.example.toml", to: configURL())
        copyExampleIfNeeded(resourcePath: ".env.example", to: envURL())
        createStateIfNeeded()
    }

    private nonisolated func copyExampleIfNeeded(resourcePath: String, to destination: URL) {
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        guard let source = Bundle.main.resourceURL?.appendingPathComponent(resourcePath) else { return }
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.copyItem(at: source, to: destination)
    }

    private nonisolated func pasExecutable() -> (url: URL, prefixArguments: [String]) {
        if let bundled = Bundle.main.url(forResource: "pas", withExtension: nil, subdirectory: "bin") {
            return (bundled, [])
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["pas"])
    }

    private nonisolated func supportDirectory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PAS", isDirectory: true)
    }

    private nonisolated func configURL() -> URL {
        supportDirectory().appendingPathComponent("config.toml")
    }

    private nonisolated func envURL() -> URL {
        supportDirectory().appendingPathComponent(".env")
    }

    private nonisolated func logsDirectory() -> URL {
        supportDirectory().appendingPathComponent("logs", isDirectory: true)
    }

    private nonisolated func snapshotsDirectory() -> URL {
        supportDirectory().appendingPathComponent("snapshots", isDirectory: true)
    }

    private nonisolated func stateURL() -> URL {
        supportDirectory().appendingPathComponent("state.json")
    }

    private nonisolated func createStateIfNeeded() {
        let destination = stateURL()
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        let payload = """
        {
          "version": 1,
          "created_at": "\(ISO8601DateFormatter().string(from: Date()))",
          "last_runs": {}
        }
        """
        try? payload.write(to: destination, atomically: true, encoding: .utf8)
    }
}
