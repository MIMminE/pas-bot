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
        try? Self.prepareSupportFiles()
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
            let result = Self.execute(arguments)
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
        let directory = Self.supportDirectory()
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

    func selectRepositoryRoot(onSelect: @escaping (String) -> Void) {
        selectDirectory { url in
            onSelect(url.path)
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
            slackMode: "oauth",
            slackBotToken: readConfigValue(section: "slack", key: "bot_token"),
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
            repoRoots: readRepositoryRoots(),
            repoProjectPaths: Set(readRepositoryProjects()),
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
            try Self.prepareSupportFiles()
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

    func loadSlackChannels(settings: PASSettings) async -> [SlackChannel] {
        saveSettings(settings)
        status = "Slack 채널 목록을 불러오는 중..."
        let result = await Self.executeDetached(["slack", "channels", "--format", "tsv"])
        lastOutput = result.output
        status = result.succeeded ? "Slack 채널 목록을 불러왔습니다" : "Slack 채널 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "Slack 채널 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
            return []
        }
        return Self.parseSlackChannels(result.output)
    }

    func loadLocalRepositories(settings: PASSettings) async -> [LocalRepositoryOption] {
        saveSettings(settings)
        status = "로컬 Git repository 목록을 불러오는 중..."
        let result = await Self.executeDetached(["repo", "list", "--all", "--format", "tsv"])
        lastOutput = result.output
        status = result.succeeded ? "로컬 Git repository 목록을 불러왔습니다" : "로컬 Git repository 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "로컬 Git repository 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
            return []
        }
        return Self.parseLocalRepositories(result.output)
    }

    private nonisolated static func parseSlackChannels(_ output: String) -> [SlackChannel] {
        output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 2 else { return nil }
                return SlackChannel(id: String(parts[0]), name: String(parts[1]), isPrivate: parts.count >= 3 && parts[2] == "true")
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func parseLocalRepositories(_ output: String) -> [LocalRepositoryOption] {
        output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 6 else { return nil }
                return LocalRepositoryOption(
                    path: String(parts[0]),
                    name: String(parts[1]),
                    branch: String(parts[2]),
                    ahead: Int(String(parts[3])),
                    behind: Int(String(parts[4])),
                    dirtyCount: Int(String(parts[5])) ?? 0
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func executeDetached(_ arguments: [String]) async -> (succeeded: Bool, output: String, summary: String) {
        await Task.detached(priority: .userInitiated) {
            Self.execute(arguments)
        }.value
    }

    private nonisolated static func execute(_ arguments: [String]) -> (succeeded: Bool, output: String, summary: String) {
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

    private nonisolated static func prepareSupportFiles() throws {
        let fileManager = FileManager.default
        let directory = supportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: snapshotsDirectory(), withIntermediateDirectories: true)

        copyExampleIfNeeded(resourcePath: "config.example.toml", to: configURL())
        copyExampleIfNeeded(resourcePath: "assignees.example.json", to: assigneesURL())
        createStateIfNeeded()
    }

    private nonisolated static func copyExampleIfNeeded(resourcePath: String, to destination: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        guard let source = Bundle.main.resourceURL?.appendingPathComponent(resourcePath) else { return }
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.copyItem(at: source, to: destination)
    }

    private nonisolated static func pasExecutable() -> (url: URL, prefixArguments: [String]) {
        if let bundled = Bundle.main.url(forResource: "pas", withExtension: nil, subdirectory: "bin") {
            return (bundled, [])
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["pas"])
    }

    private nonisolated static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PAS", isDirectory: true)
    }

    private nonisolated static func configURL() -> URL {
        supportDirectory().appendingPathComponent("config.toml")
    }

    private nonisolated static func assigneesURL() -> URL {
        supportDirectory().appendingPathComponent("assignees.json")
    }

    private nonisolated static func logsDirectory() -> URL {
        supportDirectory().appendingPathComponent("logs", isDirectory: true)
    }

    private nonisolated static func snapshotsDirectory() -> URL {
        supportDirectory().appendingPathComponent("snapshots", isDirectory: true)
    }

    private nonisolated static func stateURL() -> URL {
        supportDirectory().appendingPathComponent("state.json")
    }

    private nonisolated static func createStateIfNeeded() {
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
        try payload.write(to: Self.stateURL(), atomically: true, encoding: .utf8)
    }

    private func readConfigValue(section: String, key: String) -> String {
        guard let text = try? String(contentsOf: Self.configURL(), encoding: .utf8) else { return "" }
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

    private func readRepositoryRoots() -> [LocalRepositoryRoot] {
        guard let text = try? String(contentsOf: Self.configURL(), encoding: .utf8) else { return [] }
        var roots: [LocalRepositoryRoot] = []
        var inRoot = false
        var path = ""
        var recursive = true

        func flush() {
            if !path.isEmpty {
                roots.append(LocalRepositoryRoot(path: path, recursive: recursive))
            }
            path = ""
            recursive = true
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[[repositories.roots]]" {
                if inRoot {
                    flush()
                }
                inRoot = true
                continue
            }
            if trimmed.hasPrefix("[") {
                if inRoot {
                    flush()
                    inRoot = false
                }
                continue
            }
            guard inRoot, let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            let value = unquote(String(trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)))
            if key == "path" {
                path = value
            } else if key == "recursive" {
                recursive = value.lowercased() != "false"
            }
        }
        if inRoot {
            flush()
        }
        return roots
    }

    private func readRepositoryProjects() -> [String] {
        guard let text = try? String(contentsOf: Self.configURL(), encoding: .utf8) else { return [] }
        var projects: [String] = []
        var inProject = false
        var path = ""

        func flush() {
            if !path.isEmpty {
                projects.append(path)
            }
            path = ""
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[[repositories.projects]]" {
                if inProject {
                    flush()
                }
                inProject = true
                continue
            }
            if trimmed.hasPrefix("[") {
                if inProject {
                    flush()
                    inProject = false
                }
                continue
            }
            guard inProject, let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            let value = unquote(String(trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)))
            if key == "path" {
                path = value
            }
        }
        if inProject {
            flush()
        }
        return projects
    }

    private func writeConfig(_ settings: PASSettings) throws {
        guard var text = try? String(contentsOf: Self.configURL(), encoding: .utf8) else { return }
        text = replaceConfigValue(text, section: "general", key: "git_author", value: settings.gitAuthor)
        text = replaceConfigValue(text, section: "general", key: "work_end_time", value: settings.workEndTime)
        text = replaceConfigValue(text, section: "jira", key: "base_url", value: settings.jiraBaseURL)
        text = replaceConfigValue(text, section: "jira", key: "email", value: settings.jiraEmail)
        text = replaceConfigValue(text, section: "jira", key: "api_token", value: settings.jiraApiToken)
        text = replaceConfigValue(text, section: "jira", key: "default_project", value: settings.jiraDefaultProject)
        text = replaceConfigValue(text, section: "slack", key: "mode", value: "oauth")
        text = removeConfigValue(text, section: "slack", key: "webhook_url")
        text = replaceConfigValue(text, section: "slack", key: "bot_token", value: settings.slackBotToken)
        text = removeConfigSection(text, section: "slack.webhooks")
        text = replaceConfigValue(text, section: "slack.channels", key: "default", value: settings.slackDefaultChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "test", value: settings.slackTestChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "morning_briefing", value: settings.slackMorningChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "evening_check", value: settings.slackEveningChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "jira_daily", value: settings.slackJiraChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "git_report", value: settings.slackGitReportChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "git_status", value: settings.slackGitStatusChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "alerts", value: settings.slackAlertsChannelID)
        text = removeConfigSection(text, section: "github")
        text = removeArraySection(text, section: "github.repositories")
        text = replaceRepositoryRoots(text, roots: settings.repoRoots)
        text = replaceRepositoryProjects(text, projectPaths: settings.repoProjectPaths)
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
        try text.write(to: Self.configURL(), atomically: true, encoding: .utf8)
    }

    private func replaceConfigValue(_ text: String, section: String, key: String, value: String) -> String {
        replaceConfigLine(text, section: section, key: key, renderedValue: "\"\(escapeToml(value))\"")
    }

    private func replaceConfigBoolValue(_ text: String, section: String, key: String, value: Bool) -> String {
        replaceConfigLine(text, section: section, key: key, renderedValue: value ? "true" : "false")
    }

    private func removeConfigValue(_ text: String, section: String, key: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var currentSection = ""
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                return false
            }
            guard currentSection == section, let separator = trimmed.firstIndex(of: "=") else { return false }
            let name = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            return name == key
        }
        return lines.joined(separator: "\n")
    }

    private func removeConfigSection(_ text: String, section: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var isRemoving = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                isRemoving = trimmed == "[\(section)]"
                if isRemoving {
                    continue
                }
            }
            if !isRemoving {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    private func removeArraySection(_ text: String, section: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var isRemoving = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]") {
                isRemoving = trimmed == "[[\(section)]]"
                if isRemoving {
                    continue
                }
            } else if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                isRemoving = false
            }
            if !isRemoving {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    private func replaceRepositoryRoots(_ text: String, roots: [LocalRepositoryRoot]) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[[repositories.roots]]" {
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

        let rendered = roots.compactMap { root -> String? in
            let path = root.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return """

            [[repositories.roots]]
            path = "\(escapeToml(path))"
            recursive = \(root.recursive ? "true" : "false")
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

    private func replaceRepositoryProjects(_ text: String, projectPaths: Set<String>) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[[repositories.projects]]" {
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

        let rendered = projectPaths.sorted().compactMap { rawPath -> String? in
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return """

            [[repositories.projects]]
            path = "\(escapeToml(path))"
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

    private func selectDirectory(onSelect: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
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
    var slackBotToken: String
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
    var repoRoots: [LocalRepositoryRoot]
    var repoProjectPaths: Set<String>
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
        !slackBotToken.isEmpty && !testChannelID.isEmpty
    }

    private var slackJiraReady: Bool {
        !slackBotToken.isEmpty && !jiraChannelID.isEmpty
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

struct SlackChannel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isPrivate: Bool

    var label: String {
        "#\(name)\(isPrivate ? " (private)" : "")"
    }
}

struct LocalRepositoryRoot: Identifiable, Hashable, Sendable {
    var path: String
    var recursive: Bool

    var id: String {
        path
    }
}

struct LocalRepositoryOption: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let branch: String
    let ahead: Int?
    let behind: Int?
    let dirtyCount: Int

    var id: String {
        path
    }

    var syncLabel: String {
        if let ahead, let behind {
            if ahead > 0 && behind > 0 {
                return "rebase/merge 확인: ahead \(ahead), behind \(behind)"
            }
            if behind > 0 {
                return "rebase/pull 필요: behind \(behind)"
            }
            if ahead > 0 {
                return "push 필요: ahead \(ahead)"
            }
            return "동기화됨"
        }
        return "upstream 없음"
    }
}
