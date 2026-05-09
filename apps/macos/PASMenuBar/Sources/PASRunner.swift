import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PASRunner: ObservableObject {
    @Published var isRunning = false
    @Published var status = "Idle"
    @Published var lastOutput = ""

    private let fileManager = FileManager.default
    private var setupWindow: NSWindow?

    init() {
        try? prepareSupportFiles()
        if !setupCompleted() {
            DispatchQueue.main.async { [weak self] in
                self?.openSetupWindow()
            }
        }
    }

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

    func openSetupWindow() {
        if let setupWindow {
            setupWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PAS Setup"
        window.center()
        window.contentView = NSHostingView(rootView: SetupView(runner: self))
        window.isReleasedWhenClosed = false
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func closeSetupWindow() {
        setupWindow?.close()
    }

    func setupCompleted() -> Bool {
        guard let data = try? Data(contentsOf: stateURL()),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return object["setup_completed"] as? Bool == true
    }

    func loadSettings() -> PASSettings {
        PASSettings(
            slackWebhookURL: readEnvValue("SLACK_WEBHOOK_URL"),
            jiraBaseURL: readConfigValue(section: "jira", key: "base_url"),
            jiraEmail: readConfigValue(section: "jira", key: "email"),
            jiraApiToken: readEnvValue("JIRA_API_TOKEN"),
            jiraDefaultProject: readConfigValue(section: "jira", key: "default_project")
        )
    }

    func saveSettings(_ settings: PASSettings) {
        do {
            try prepareSupportFiles()
            try writeEnv(settings)
            try writeConfig(settings)
            try markSetupCompleted()
            status = "Settings saved"
        } catch {
            status = "Failed to save settings: \(error.localizedDescription)"
        }
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
          "setup_completed": false,
          "last_runs": {}
        }
        """
        try? payload.write(to: destination, atomically: true, encoding: .utf8)
    }

    private func markSetupCompleted() throws {
        let payload = """
        {
          "version": 1,
          "updated_at": "\(ISO8601DateFormatter().string(from: Date()))",
          "setup_completed": true,
          "last_runs": {}
        }
        """
        try payload.write(to: stateURL(), atomically: true, encoding: .utf8)
    }

    private func readEnvValue(_ key: String) -> String {
        guard let text = try? String(contentsOf: envURL(), encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            if name == key {
                return String(trimmed[trimmed.index(after: separator)...])
            }
        }
        return ""
    }

    private func readConfigValue(section: String, key: String) -> String {
        guard let text = try? String(contentsOf: configURL(), encoding: .utf8) else { return "" }
        var currentSection = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }
            guard currentSection == section, let separator = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            if name == key {
                return unquote(String(trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)))
            }
        }
        return ""
    }

    private func writeEnv(_ settings: PASSettings) throws {
        let text = """
        JIRA_BASE_URL=\(settings.jiraBaseURL)
        JIRA_EMAIL=\(settings.jiraEmail)
        JIRA_API_TOKEN=\(settings.jiraApiToken)
        JIRA_DEFAULT_PROJECT=\(settings.jiraDefaultProject)
        SLACK_WEBHOOK_URL=\(settings.slackWebhookURL)
        OPENAI_API_KEY=\(readEnvValue("OPENAI_API_KEY"))
        """
        try text.write(to: envURL(), atomically: true, encoding: .utf8)
    }

    private func writeConfig(_ settings: PASSettings) throws {
        guard var text = try? String(contentsOf: configURL(), encoding: .utf8) else { return }
        text = replaceConfigValue(text, section: "jira", key: "base_url", value: settings.jiraBaseURL)
        text = replaceConfigValue(text, section: "jira", key: "email", value: settings.jiraEmail)
        text = replaceConfigValue(text, section: "jira", key: "default_project", value: settings.jiraDefaultProject)
        try text.write(to: configURL(), atomically: true, encoding: .utf8)
    }

    private func replaceConfigValue(_ text: String, section: String, key: String, value: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var currentSection = ""
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }
            guard currentSection == section, let separator = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            if name == key {
                lines[index] = "\(key) = \"\(escapeToml(value))\""
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    private func unquote(_ value: String) -> String {
        if value.count >= 2 && value.first == "\"" && value.last == "\"" {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private func escapeToml(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct PASSettings {
    var slackWebhookURL: String
    var jiraBaseURL: String
    var jiraEmail: String
    var jiraApiToken: String
    var jiraDefaultProject: String

    var isReadyForBasicTests: Bool {
        slackWebhookURL.hasPrefix("https://hooks.slack.com/services/")
            && jiraBaseURL.hasPrefix("https://")
            && jiraEmail.contains("@")
            && !jiraApiToken.isEmpty
            && !jiraDefaultProject.isEmpty
    }
}
