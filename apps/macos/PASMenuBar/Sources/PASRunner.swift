import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PASRunner: ObservableObject {
    @Published var isRunning = false
    @Published var status = "대기 중"
    @Published var lastOutput = ""

    private var setupWindow: NSWindow?
    private var outputWindow: NSWindow?

    init() {
        try? prepareSupportFiles()
        DispatchQueue.main.async { [weak self] in
            self?.openSetupWindow()
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
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func openExternalURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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

    func loadSettings() -> PASSettings {
        PASSettings(
            slackMode: readConfigValue(section: "slack", key: "mode").isEmpty ? "webhook" : readConfigValue(section: "slack", key: "mode"),
            slackDefaultWebhookURL: readConfigValue(section: "slack", key: "webhook_url"),
            slackBotToken: readConfigValue(section: "slack", key: "bot_token"),
            slackTestWebhookURL: readConfigValue(section: "slack.webhooks", key: "test"),
            slackJiraWebhookURL: readConfigValue(section: "slack.webhooks", key: "jira_daily"),
            slackGitReportWebhookURL: readConfigValue(section: "slack.webhooks", key: "git_report"),
            slackGitStatusWebhookURL: readConfigValue(section: "slack.webhooks", key: "git_status"),
            slackAlertsWebhookURL: readConfigValue(section: "slack.webhooks", key: "alerts"),
            slackDefaultChannelID: readConfigValue(section: "slack.channels", key: "default"),
            slackTestChannelID: readConfigValue(section: "slack.channels", key: "test"),
            slackMorningChannelID: readConfigValue(section: "slack.channels", key: "morning_briefing"),
            slackEveningChannelID: readConfigValue(section: "slack.channels", key: "evening_check"),
            slackJiraChannelID: readConfigValue(section: "slack.channels", key: "jira_daily"),
            slackGitReportChannelID: readConfigValue(section: "slack.channels", key: "git_report"),
            slackGitStatusChannelID: readConfigValue(section: "slack.channels", key: "git_status"),
            slackAlertsChannelID: readConfigValue(section: "slack.channels", key: "alerts"),
            jiraBaseURL: readConfigValue(section: "jira", key: "base_url"),
            jiraEmail: readConfigValue(section: "jira", key: "email"),
            jiraApiToken: readConfigValue(section: "jira", key: "api_token"),
            jiraDefaultProject: readConfigValue(section: "jira", key: "default_project"),
            gitAuthor: readConfigValue(section: "general", key: "git_author"),
            workEndTime: readConfigValue(section: "general", key: "work_end_time"),
            githubToken: readConfigValue(section: "github", key: "token"),
            githubRepositoryIDs: Set(readGitHubRepositories().map { $0.id }),
            openAIKey: readConfigValue(section: "openai", key: "api_key"),
            jiraDailyEnabled: readBoolConfigValue(section: "feature_groups", key: "jira", defaultValue: true),
            gitReportEnabled: readBoolConfigValue(section: "feature_groups", key: "git", defaultValue: true),
            gitStatusEnabled: readBoolConfigValue(section: "feature_groups", key: "git", defaultValue: true),
            jiraDailyScheduleEnabled: readBoolConfigValue(section: "schedules.jira_daily", key: "enabled", defaultValue: false),
            jiraDailyScheduleTime: readConfigValue(section: "schedules.jira_daily", key: "time"),
            jiraDailyCatchUp: readBoolConfigValue(section: "schedules.jira_daily", key: "catch_up_if_missed", defaultValue: true),
            gitReportScheduleEnabled: readBoolConfigValue(section: "schedules.git_report", key: "enabled", defaultValue: false),
            gitReportScheduleTime: readConfigValue(section: "schedules.git_report", key: "time"),
            gitReportCatchUp: readBoolConfigValue(section: "schedules.git_report", key: "catch_up_if_missed", defaultValue: true),
            gitStatusScheduleEnabled: readBoolConfigValue(section: "schedules.git_status", key: "enabled", defaultValue: false),
            gitStatusScheduleTime: readConfigValue(section: "schedules.git_status", key: "time"),
            gitStatusCatchUp: readBoolConfigValue(section: "schedules.git_status", key: "catch_up_if_missed", defaultValue: true)
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

    func loadSlackChannels(settings: PASSettings) -> [SlackChannel] {
        saveSettings(settings)
        let result = execute(["slack", "channels", "--format", "tsv"])
        lastOutput = result.output
        status = result.succeeded ? "Slack 채널 목록을 불러왔습니다" : "Slack 채널 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "Slack 채널 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
            return []
        }
        return result.output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 2 else { return nil }
                return SlackChannel(id: String(parts[0]), name: String(parts[1]), isPrivate: parts.count >= 3 && parts[2] == "true")
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func loadGitHubRepositories(settings: PASSettings) -> [GitHubRepositoryOption] {
        saveSettings(settings)
        let result = execute(["repo", "remote-list", "--format", "tsv"])
        lastOutput = result.output
        status = result.succeeded ? "GitHub repository 목록을 불러왔습니다" : "GitHub repository 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "GitHub repository 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
            return []
        }
        return result.output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 2 else { return nil }
                return GitHubRepositoryOption(
                    owner: String(parts[0]),
                    name: String(parts[1]),
                    isPrivate: parts.count >= 3 && parts[2].lowercased() == "true",
                    defaultBranch: parts.count >= 4 ? String(parts[3]) : "",
                    url: parts.count >= 5 ? String(parts[4]) : ""
                )
            }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
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
        let fileManager = FileManager.default
        let directory = supportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: snapshotsDirectory(), withIntermediateDirectories: true)

        copyExampleIfNeeded(resourcePath: "config.example.toml", to: configURL())
        copyExampleIfNeeded(resourcePath: "assignees.example.json", to: assigneesURL())
        createStateIfNeeded()
    }

    private nonisolated func copyExampleIfNeeded(resourcePath: String, to destination: URL) {
        let fileManager = FileManager.default
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
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
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
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

    private func readBoolConfigValue(section: String, key: String, defaultValue: Bool) -> Bool {
        let value = readConfigValue(section: section, key: key)
        if value.isEmpty {
            return defaultValue
        }
        return value.lowercased() == "true"
    }

    private func readGitHubRepositories() -> [GitHubRepositoryOption] {
        guard let text = try? String(contentsOf: configURL(), encoding: .utf8) else { return [] }
        var repositories: [GitHubRepositoryOption] = []
        var inRepository = false
        var owner = ""
        var name = ""

        func flush() {
            if !owner.isEmpty && !name.isEmpty {
                repositories.append(GitHubRepositoryOption(owner: owner, name: name, isPrivate: false, defaultBranch: "", url: ""))
            }
            owner = ""
            name = ""
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[[github.repositories]]" {
                if inRepository {
                    flush()
                }
                inRepository = true
                continue
            }
            if trimmed.hasPrefix("[") {
                if inRepository {
                    flush()
                    inRepository = false
                }
                continue
            }
            guard inRepository, let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            let value = unquote(String(trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)))
            if key == "owner" {
                owner = value
            } else if key == "name" {
                name = value
            }
        }
        if inRepository {
            flush()
        }
        return repositories
    }

    private func writeConfig(_ settings: PASSettings) throws {
        guard var text = try? String(contentsOf: configURL(), encoding: .utf8) else { return }
        text = replaceConfigValue(text, section: "general", key: "git_author", value: settings.gitAuthor)
        text = replaceConfigValue(text, section: "general", key: "work_end_time", value: settings.workEndTime)
        text = replaceConfigValue(text, section: "jira", key: "base_url", value: settings.jiraBaseURL)
        text = replaceConfigValue(text, section: "jira", key: "email", value: settings.jiraEmail)
        text = replaceConfigValue(text, section: "jira", key: "api_token", value: settings.jiraApiToken)
        text = replaceConfigValue(text, section: "jira", key: "default_project", value: settings.jiraDefaultProject)
        text = replaceConfigValue(text, section: "slack", key: "mode", value: settings.slackMode)
        text = replaceConfigValue(text, section: "slack", key: "webhook_url", value: settings.slackDefaultWebhookURL)
        text = replaceConfigValue(text, section: "slack", key: "bot_token", value: settings.slackBotToken)
        text = replaceConfigValue(text, section: "slack.webhooks", key: "default", value: settings.slackDefaultWebhookURL)
        text = replaceConfigValue(text, section: "slack.webhooks", key: "test", value: settings.slackTestWebhookURL)
        text = replaceConfigValue(text, section: "slack.webhooks", key: "jira_daily", value: settings.slackJiraWebhookURL)
        text = replaceConfigValue(text, section: "slack.webhooks", key: "git_report", value: settings.slackGitReportWebhookURL)
        text = replaceConfigValue(text, section: "slack.webhooks", key: "git_status", value: settings.slackGitStatusWebhookURL)
        text = replaceConfigValue(text, section: "slack.webhooks", key: "alerts", value: settings.slackAlertsWebhookURL)
        text = replaceConfigValue(text, section: "slack.channels", key: "default", value: settings.slackDefaultChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "test", value: settings.slackTestChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "morning_briefing", value: settings.slackMorningChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "evening_check", value: settings.slackEveningChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "jira_daily", value: settings.slackJiraChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "git_report", value: settings.slackGitReportChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "git_status", value: settings.slackGitStatusChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "alerts", value: settings.slackAlertsChannelID)
        text = replaceConfigValue(text, section: "github", key: "token", value: settings.githubToken)
        text = replaceGitHubRepositories(text, repositoryIDs: settings.githubRepositoryIDs)
        text = replaceConfigValue(text, section: "openai", key: "api_key", value: settings.openAIKey)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "jira", value: settings.jiraDailyEnabled)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "git", value: settings.gitReportEnabled || settings.gitStatusEnabled)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "routines", value: true)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "ai", value: true)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "dev_tools", value: true)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "notifications", value: true)
        text = replaceConfigBoolValue(text, section: "schedules.jira_daily", key: "enabled", value: settings.jiraDailyScheduleEnabled)
        text = replaceConfigValue(text, section: "schedules.jira_daily", key: "time", value: settings.jiraDailyScheduleTimeOrDefault)
        text = replaceConfigBoolValue(text, section: "schedules.jira_daily", key: "catch_up_if_missed", value: settings.jiraDailyCatchUp)
        text = replaceConfigBoolValue(text, section: "schedules.git_report", key: "enabled", value: settings.gitReportScheduleEnabled)
        text = replaceConfigValue(text, section: "schedules.git_report", key: "time", value: settings.gitReportScheduleTimeOrDefault)
        text = replaceConfigBoolValue(text, section: "schedules.git_report", key: "catch_up_if_missed", value: settings.gitReportCatchUp)
        text = replaceConfigBoolValue(text, section: "schedules.git_status", key: "enabled", value: settings.gitStatusScheduleEnabled)
        text = replaceConfigValue(text, section: "schedules.git_status", key: "time", value: settings.gitStatusScheduleTimeOrDefault)
        text = replaceConfigBoolValue(text, section: "schedules.git_status", key: "catch_up_if_missed", value: settings.gitStatusCatchUp)
        try text.write(to: configURL(), atomically: true, encoding: .utf8)
    }

    private func replaceConfigValue(_ text: String, section: String, key: String, value: String) -> String {
        replaceConfigLine(text, section: section, key: key, renderedValue: "\"\(escapeToml(value))\"")
    }

    private func replaceConfigBoolValue(_ text: String, section: String, key: String, value: Bool) -> String {
        replaceConfigLine(text, section: section, key: key, renderedValue: value ? "true" : "false")
    }

    private func replaceGitHubRepositories(_ text: String, repositoryIDs: Set<String>) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[[github.repositories]]" {
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix("[") {
                        break
                    }
                    index += 1
                }
                continue
            }
            output.append(lines[index])
            index += 1
        }

        let rendered = repositoryIDs.sorted().compactMap { id -> String? in
            let parts = id.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return """

            [[github.repositories]]
            owner = "\(escapeToml(String(parts[0])))"
            name = "\(escapeToml(String(parts[1])))"
            """
        }
        if !rendered.isEmpty {
            if output.last?.isEmpty == false {
                output.append("")
            }
            output.append(rendered.joined(separator: "\n"))
        }
        return output.joined(separator: "\n")
    }

    private func replaceConfigLine(_ text: String, section: String, key: String, renderedValue: String) -> String {
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
                lines[index] = "\(key) = \(renderedValue)"
                return lines.joined(separator: "\n")
            }
        }
        if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("[\(section)]")
        }
        if let sectionIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) {
            let insertIndex = sectionEndIndex(in: lines, sectionStartIndex: sectionIndex)
            lines.insert("\(key) = \(renderedValue)", at: insertIndex)
        }
        return lines.joined(separator: "\n")
    }

    private func sectionEndIndex(in lines: [String], sectionStartIndex: Int) -> Int {
        var index = sectionStartIndex + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                break
            }
            index += 1
        }
        return index
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
    var slackMode: String
    var slackDefaultWebhookURL: String
    var slackBotToken: String
    var slackTestWebhookURL: String
    var slackJiraWebhookURL: String
    var slackGitReportWebhookURL: String
    var slackGitStatusWebhookURL: String
    var slackAlertsWebhookURL: String
    var slackDefaultChannelID: String
    var slackTestChannelID: String
    var slackMorningChannelID: String
    var slackEveningChannelID: String
    var slackJiraChannelID: String
    var slackGitReportChannelID: String
    var slackGitStatusChannelID: String
    var slackAlertsChannelID: String
    var jiraBaseURL: String
    var jiraEmail: String
    var jiraApiToken: String
    var jiraDefaultProject: String
    var gitAuthor: String
    var workEndTime: String
    var githubToken: String
    var githubRepositoryIDs: Set<String>
    var openAIKey: String
    var jiraDailyEnabled: Bool
    var gitReportEnabled: Bool
    var gitStatusEnabled: Bool
    var jiraDailyScheduleEnabled: Bool
    var jiraDailyScheduleTime: String
    var jiraDailyCatchUp: Bool
    var gitReportScheduleEnabled: Bool
    var gitReportScheduleTime: String
    var gitReportCatchUp: Bool
    var gitStatusScheduleEnabled: Bool
    var gitStatusScheduleTime: String
    var gitStatusCatchUp: Bool

    var testWebhookURL: String {
        slackTestWebhookURL.isEmpty ? slackDefaultWebhookURL : slackTestWebhookURL
    }

    var jiraWebhookURL: String {
        slackJiraWebhookURL.isEmpty ? slackDefaultWebhookURL : slackJiraWebhookURL
    }

    var testChannelID: String {
        slackTestChannelID.isEmpty ? slackDefaultChannelID : slackTestChannelID
    }

    var jiraChannelID: String {
        slackJiraChannelID.isEmpty ? slackDefaultChannelID : slackJiraChannelID
    }

    var usesSlackOAuth: Bool {
        slackMode == "oauth"
    }

    var isReadyForBasicTests: Bool {
        slackJiraReady
            && jiraBaseURL.hasPrefix("https://")
            && jiraEmail.contains("@")
            && !jiraApiToken.isEmpty
            && !jiraDefaultProject.isEmpty
    }

    var isReadyForSlackTest: Bool {
        if usesSlackOAuth {
            return !slackBotToken.isEmpty && !testChannelID.isEmpty
        }
        return testWebhookURL.hasPrefix("https://hooks.slack.com/services/")
    }

    private var slackJiraReady: Bool {
        if usesSlackOAuth {
            return !slackBotToken.isEmpty && !jiraChannelID.isEmpty
        }
        return jiraWebhookURL.hasPrefix("https://hooks.slack.com/services/")
    }

    var jiraDailyScheduleTimeOrDefault: String {
        jiraDailyScheduleTime.isEmpty ? "09:00" : jiraDailyScheduleTime
    }

    var gitReportScheduleTimeOrDefault: String {
        gitReportScheduleTime.isEmpty ? "18:30" : gitReportScheduleTime
    }

    var gitStatusScheduleTimeOrDefault: String {
        gitStatusScheduleTime.isEmpty ? "09:10" : gitStatusScheduleTime
    }
}

struct SlackChannel: Identifiable, Hashable {
    let id: String
    let name: String
    let isPrivate: Bool

    var label: String {
        "#\(name)\(isPrivate ? " (private)" : "")"
    }
}

struct GitHubRepositoryOption: Identifiable, Hashable {
    let owner: String
    let name: String
    let isPrivate: Bool
    let defaultBranch: String
    let url: String

    var id: String {
        "\(owner)/\(name)"
    }

    var label: String {
        "\(id)\(isPrivate ? " (private)" : "")"
    }
}
