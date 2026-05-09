import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PASRunner: ObservableObject {
    @Published var isRunning = false
    @Published var status = "대기 중"
    @Published var lastOutput = ""

    private let fileManager = FileManager.default
    private var setupWindow: NSWindow?
    private var outputWindow: NSWindow?

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
        status = "실행 중..."

        Task.detached { [weak self] in
            guard let self else { return }
            let result = self.execute(arguments)
            await MainActor.run {
                self.lastOutput = result.output
                self.status = result.succeeded ? "성공" : "실패: \(result.summary)"
                self.isRunning = false
                if self.shouldShowOutput(arguments: arguments, succeeded: result.succeeded) {
                    self.openOutputWindow(
                        title: result.succeeded ? "PAS 실행 결과" : "PAS 오류 상세",
                        output: result.output.isEmpty ? result.summary : result.output
                    )
                }
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
        status = "마지막 실행 결과를 복사했습니다"
    }

    func openLastOutputWindow() {
        openOutputWindow(title: "마지막 실행 결과", output: lastOutput)
    }

    func importConfigFile() {
        selectFile(allowedExtensions: ["toml"]) { [weak self] url in
            self?.run(["settings", "import", "--config-file", url.path])
        }
    }

    func importAssigneesFile() {
        selectFile(allowedExtensions: ["json"]) { [weak self] url in
            self?.run(["settings", "import", "--assignees-file", url.path])
        }
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
        window.title = "PAS 초기 설정"
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
            slackWebhookURL: readConfigValue(section: "slack", key: "webhook_url"),
            jiraBaseURL: readConfigValue(section: "jira", key: "base_url"),
            jiraEmail: readConfigValue(section: "jira", key: "email"),
            jiraApiToken: readConfigValue(section: "jira", key: "api_token"),
            jiraDefaultProject: readConfigValue(section: "jira", key: "default_project")
        )
    }

    func saveSettings(_ settings: PASSettings) {
        do {
            try prepareSupportFiles()
            try writeConfig(settings)
            try markSetupCompleted()
            status = "설정을 저장했습니다"
        } catch {
            let message = "설정 저장 실패: \(error.localizedDescription)"
            status = message
            lastOutput = message
            openOutputWindow(title: "PAS 설정 오류", output: message)
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
            configURL().path
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
        return (process.terminationStatus == 0, combined, summary.isEmpty ? "출력 없음" : summary)
    }

    private func shouldShowOutput(arguments: [String], succeeded: Bool) -> Bool {
        if !succeeded {
            return true
        }
        if arguments.contains("--dry-run") {
            return true
        }
        return arguments.first == "status" || arguments.first == "settings"
    }

    private func openOutputWindow(title: String, output: String) {
        if let outputWindow {
            outputWindow.title = title
            outputWindow.contentView = NSHostingView(rootView: OutputView(output: output))
            outputWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentView = NSHostingView(rootView: OutputView(output: output))
        window.isReleasedWhenClosed = false
        outputWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private nonisolated func prepareSupportFiles() throws {
        let directory = supportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: snapshotsDirectory(), withIntermediateDirectories: true)

        copyExampleIfNeeded(resourcePath: "config.example.toml", to: configURL())
        copyExampleIfNeeded(resourcePath: "assignees.example.json", to: assigneesURL())
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

    private nonisolated func assigneesURL() -> URL {
        supportDirectory().appendingPathComponent("assignees.json")
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

    private func writeConfig(_ settings: PASSettings) throws {
        guard var text = try? String(contentsOf: configURL(), encoding: .utf8) else { return }
        text = replaceConfigValue(text, section: "jira", key: "base_url", value: settings.jiraBaseURL)
        text = replaceConfigValue(text, section: "jira", key: "email", value: settings.jiraEmail)
        text = replaceConfigValue(text, section: "jira", key: "api_token", value: settings.jiraApiToken)
        text = replaceConfigValue(text, section: "jira", key: "default_project", value: settings.jiraDefaultProject)
        text = replaceConfigValue(text, section: "slack", key: "webhook_url", value: settings.slackWebhookURL)
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

    private func selectFile(allowedExtensions: [String], onSelect: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = allowedExtensions
        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url)
        }
    }
}

struct OutputView: View {
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("실행 결과")
                .font(.headline)

            ScrollView {
                Text(output.isEmpty ? "출력 없음" : output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color(nsColor: .separatorColor))
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 420)
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
