import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PASRunner: NSObject, ObservableObject, NSWindowDelegate {
    @Published var isRunning = false
    @Published var status = "대기 중"
    @Published var lastOutput = ""

    private var setupWindow: NSWindow?
    private var workWindow: NSWindow?
    private var outputWindow: NSWindow?
    private var issueLinkWindow: NSWindow?
    private var reportAgentWindow: NSWindow?

    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
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

    func openReportAgentEditor() {
        try? Self.prepareSupportFiles()
        NSApplication.shared.setActivationPolicy(.regular)
        if let reportAgentWindow {
            reportAgentWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "보고서 작성 규칙"
        window.center()
        window.contentView = NSHostingView(rootView: ReportAgentEditorView(runner: self))
        window.isReleasedWhenClosed = false
        window.delegate = self
        reportAgentWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func openExternalURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private nonisolated func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            return
        }
        Task { @MainActor in
            self.handleDeepLink(url)
        }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "pas" else {
            status = "지원하지 않는 PAS 링크입니다"
            return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if url.host == "branch", url.path == "/create" {
            let issue = Self.queryValue("issue", in: items)
            let repo = Self.queryValue("repo", in: items)
            let summary = Self.queryValue("summary", in: items)
            guard !issue.isEmpty, !repo.isEmpty else {
                status = "브랜치 생성 링크에 필요한 값이 없습니다"
                return
            }
            Task {
                await createBranch(issue: issue, repo: repo, summary: summary)
            }
            return
        }

        if url.host == "jira", url.path == "/link" {
            let issue = Self.queryValue("issue", in: items)
            let summary = Self.queryValue("summary", in: items)
            guard !issue.isEmpty else {
                status = "Jira repo 연결 링크에 issue 값이 없습니다"
                return
            }
            openIssueRepositoryLinkWindow(issue: issue, summary: summary)
            return
        }

        status = "지원하지 않는 PAS 링크입니다"
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
        window.title = "PAS 설정"
        window.center()
        window.contentView = NSHostingView(rootView: SetupView(runner: self))
        window.isReleasedWhenClosed = false
        window.delegate = self
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func openWorkWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let workWindow {
            workWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PAS 작업 콘솔"
        window.center()
        window.contentView = NSHostingView(rootView: WorkView(runner: self))
        window.isReleasedWhenClosed = false
        window.delegate = self
        workWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func openIssueRepositoryLinkWindow(issue: String, summary: String) {
        NSApplication.shared.setActivationPolicy(.regular)
        if let issueLinkWindow {
            issueLinkWindow.title = "\(issue) repository 연결"
            issueLinkWindow.contentView = NSHostingView(rootView: IssueRepositoryLinkView(runner: self, issue: issue, summary: summary))
            issueLinkWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(issue) repository 연결"
        window.center()
        window.contentView = NSHostingView(rootView: IssueRepositoryLinkView(runner: self, issue: issue, summary: summary))
        window.isReleasedWhenClosed = false
        window.delegate = self
        issueLinkWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func closeSetupWindow() {
        setupWindow?.close()
    }

    func closeWorkWindow() {
        workWindow?.close()
    }

    func closeIssueRepositoryLinkWindow() {
        issueLinkWindow?.close()
    }

    func closeReportAgentWindow() {
        reportAgentWindow?.close()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            guard let window = notification.object as? NSWindow else { return }
            if window === self.workWindow {
                self.workWindow = nil
            } else if window === self.setupWindow {
                self.setupWindow = nil
            } else if window === self.outputWindow {
                self.outputWindow = nil
            } else if window === self.issueLinkWindow {
                self.issueLinkWindow = nil
            } else if window === self.reportAgentWindow {
                self.reportAgentWindow = nil
            }
            self.restoreMenuBarModeIfPossible()
        }
    }

    func loadReportAgentRules() -> String {
        do {
            try Self.prepareSupportFiles()
            return try String(contentsOf: Self.reportAgentURL(), encoding: .utf8)
        } catch {
            let message = "보고서 작성 규칙을 불러오지 못했습니다: \(error.localizedDescription)"
            status = message
            return message
        }
    }

    func saveReportAgentRules(_ text: String) -> PASCommandResult {
        do {
            try Self.prepareSupportFiles()
            try text.write(to: Self.reportAgentURL(), atomically: true, encoding: .utf8)
            status = "보고서 작성 규칙을 저장했습니다"
            return PASCommandResult(succeeded: true, output: "보고서 작성 규칙을 저장했습니다.", summary: "저장 완료")
        } catch {
            let message = "보고서 작성 규칙 저장 실패: \(error.localizedDescription)"
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }
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

    func loadRemoteRepositories(owner: String) async -> [GitHubRemoteRepositoryOption] {
        status = "GitHub 원격 repository 후보를 불러오는 중..."
        var arguments = ["repo", "remote-list", "--format", "tsv"]
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOwner.isEmpty {
            arguments.append(contentsOf: ["--owner", trimmedOwner])
        }
        let result = await Self.executeDetached(arguments)
        lastOutput = result.output
        status = result.succeeded ? "GitHub 원격 repository 후보를 불러왔습니다" : "GitHub 원격 repository 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "GitHub repository 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
            return []
        }
        return Self.parseRemoteRepositories(result.output)
    }

    func cloneRemoteRepository(_ repo: GitHubRemoteRepositoryOption, targetRoot: String) async -> PASCommandResult {
        guard !isRunning else {
            return PASCommandResult(succeeded: false, output: "", summary: "이미 실행 중인 작업이 있습니다.")
        }
        isRunning = true
        status = "\(repo.nameWithOwner) clone 중..."
        let source = repo.sshURL.isEmpty ? repo.nameWithOwner : repo.sshURL
        let result = await Self.executeDetached(["repo", "clone", "--repo", source, "--target-root", targetRoot])
        lastOutput = result.output
        status = result.succeeded ? "\(repo.nameWithOwner) clone 완료" : "\(repo.nameWithOwner) clone 실패"
        isRunning = false
        if !result.succeeded {
            openOutputWindow(title: "GitHub repository clone 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded, output: result.output, summary: result.summary)
    }

    func loadManagedRepositories() async -> [LocalRepositoryOption] {
        status = "관리 중인 Git repository 상태를 불러오는 중..."
        let result = await Self.executeDetached(["repo", "list", "--format", "tsv"])
        lastOutput = result.output
        status = result.succeeded ? "관리 중인 Git repository 상태를 불러왔습니다" : "Git repository 상태 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "Git repository 상태 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
            return []
        }
        return Self.parseLocalRepositories(result.output)
    }

    func refreshManagedRepositories(fetchRemote: Bool) async -> [LocalRepositoryOption] {
        if fetchRemote {
            status = "원격 Git 상태를 갱신하는 중..."
            let listResult = await Self.executeDetached(["repo", "list", "--format", "tsv"])
            let repos = Self.parseLocalRepositories(listResult.output)
            for repo in repos {
                _ = await Self.executeDetached(["repo", "update", "--repo", repo.path, "--mode", "fetch"])
            }
        }
        return await loadManagedRepositories()
    }

    func runRepositoryUpdate(path: String, mode: String) async -> String {
        isRunning = true
        status = "Git \(mode) 실행 중..."
        let result = await Self.executeDetached(["repo", "update", "--repo", path, "--mode", mode])
        lastOutput = result.output
        status = result.succeeded ? "Git \(mode) 완료" : "Git \(mode) 실패"
        isRunning = false
        if !result.succeeded {
            openOutputWindow(title: "Git 작업 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return result.output.isEmpty ? result.summary : result.output
    }

    func runDashboardCommand(
        _ arguments: [String],
        runningStatus: String,
        successStatus: String,
        failureStatus: String
    ) async -> PASCommandResult {
        guard !isRunning else {
            return PASCommandResult(succeeded: false, output: "", summary: "이미 실행 중인 작업이 있습니다.")
        }
        isRunning = true
        status = runningStatus
        let result = await Self.executeDetached(arguments)
        lastOutput = result.output
        status = result.succeeded ? successStatus : failureStatus
        isRunning = false
        return PASCommandResult(succeeded: result.succeeded, output: result.output, summary: result.summary)
    }

    func createBranch(issue: String, repo: String, summary: String) async {
        guard !isRunning else { return }
        isRunning = true
        status = "\(issue) 브랜치 생성 중..."
        let result = await Self.executeDetached(["dev", "create-branch", "--repo", repo, "--issue-key", issue, "--summary", summary, "--base-branch", "dev"])
        lastOutput = result.output
        status = result.succeeded ? "\(issue) 브랜치 준비 완료" : "\(issue) 브랜치 생성 실패"
        isRunning = false
        openOutputWindow(
            title: result.succeeded ? "브랜치 생성 결과" : "브랜치 생성 오류",
            output: result.output.isEmpty ? result.summary : result.output
        )
        if result.succeeded {
            openWorkWindow()
        }
    }

    func linkIssueRepository(issue: String, repo: String, summary: String) async -> PASCommandResult {
        guard !isRunning else {
            return PASCommandResult(succeeded: false, output: "", summary: "이미 실행 중인 작업이 있습니다.")
        }
        isRunning = true
        status = "\(issue) repository 연결 중..."
        let result = await Self.executeDetached(["jira", "link-repo", issue, "--repo", repo, "--summary", summary])
        lastOutput = result.output
        status = result.succeeded ? "\(issue) repository 연결 완료" : "\(issue) repository 연결 실패"
        isRunning = false
        if result.succeeded {
            openWorkWindow()
        } else {
            openOutputWindow(title: "Jira repository 연결 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded, output: result.output, summary: result.summary)
    }

    func loadIssueRepositoryLinks() async -> String {
        status = "Jira repository 연결 목록을 불러오는 중..."
        let result = await Self.executeDetached(["jira", "repo-links"])
        lastOutput = result.output
        status = result.succeeded ? "Jira repository 연결 목록을 불러왔습니다" : "Jira repository 연결 목록 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "Jira repository 연결 목록 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return result.output.isEmpty ? result.summary : result.output
    }

    func loadTodayCommits(path: String) async -> String {
        status = "오늘 커밋을 불러오는 중..."
        let result = await Self.executeDetached(["repo", "commits", "--repo", path])
        lastOutput = result.output
        status = result.succeeded ? "오늘 커밋을 불러왔습니다" : "오늘 커밋 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "오늘 커밋 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return result.output.isEmpty ? result.summary : result.output
    }

    func loadTodayActivity() async -> String {
        status = "오늘 개발 흐름을 불러오는 중..."
        let result = await Self.executeDetached(["repo", "activity"])
        lastOutput = result.output
        status = result.succeeded ? "오늘 개발 흐름을 불러왔습니다" : "오늘 개발 흐름 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "오늘 개발 흐름 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return result.output.isEmpty ? result.summary : result.output
    }

    func previewDailyReport(notes: String = "") async -> String {
        status = "오늘 작업 보고서를 만드는 중..."
        var arguments = ["repo", "report", "--snapshot", "morning", "--dry-run", "--report-agent-file", Self.reportAgentURL().path]
        var notesURL: URL?
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notesURL = Self.supportDirectory().appendingPathComponent("report-notes-\(UUID().uuidString).txt")
            do {
                try notes.write(to: notesURL!, atomically: true, encoding: .utf8)
                arguments.append(contentsOf: ["--notes-file", notesURL!.path])
            } catch {
                let message = "수동 메모 임시 파일 저장 실패: \(error.localizedDescription)"
                status = message
                return message
            }
        }
        let result = await Self.executeDetached(arguments)
        if let notesURL {
            try? FileManager.default.removeItem(at: notesURL)
        }
        lastOutput = result.output
        status = result.succeeded ? "오늘 작업 보고서를 만들었습니다" : "오늘 작업 보고서 생성 실패"
        if !result.succeeded {
            openOutputWindow(title: "오늘 작업 보고서 생성 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return Self.stripDryRunPrefix(result.output.isEmpty ? result.summary : result.output)
    }

    func sendEditedReport(_ text: String) async -> String {
        let url = Self.supportDirectory().appendingPathComponent("edited-report-\(UUID().uuidString).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let message = "보고서 임시 파일 저장 실패: \(error.localizedDescription)"
            status = message
            return message
        }

        isRunning = true
        status = "수정한 보고서를 Slack으로 전송하는 중..."
        let result = await Self.executeDetached(["repo", "send-report-text", "--text-file", url.path])
        try? FileManager.default.removeItem(at: url)
        lastOutput = result.output
        status = result.succeeded ? "수정한 보고서를 Slack으로 전송했습니다" : "수정한 보고서 전송 실패"
        isRunning = false
        if !result.succeeded {
            openOutputWindow(title: "보고서 전송 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return result.output.isEmpty ? result.summary : result.output
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

    private nonisolated static func parseRemoteRepositories(_ output: String) -> [GitHubRemoteRepositoryOption] {
        output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 5 else { return nil }
                return GitHubRemoteRepositoryOption(
                    nameWithOwner: String(parts[0]),
                    sshURL: String(parts[1]),
                    webURL: String(parts[2]),
                    visibility: String(parts[3]),
                    defaultBranch: String(parts[4])
                )
            }
            .sorted { $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending }
    }

    private nonisolated static func stripDryRunPrefix(_ value: String) -> String {
        value.replacingOccurrences(of: "[dry-run]\n", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func queryValue(_ name: String, in items: [URLQueryItem]) -> String {
        items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    private func restoreMenuBarModeIfPossible() {
        guard workWindow == nil, setupWindow == nil, outputWindow == nil, issueLinkWindow == nil, reportAgentWindow == nil else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func openOutputWindow(title: String, output: String) {
        NSApplication.shared.setActivationPolicy(.regular)
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
        window.delegate = self
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
        copyExampleIfNeeded(resourcePath: "report-agent.example.md", to: reportAgentURL())
        createReportAgentIfNeeded()
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

    private nonisolated static func reportAgentURL() -> URL {
        supportDirectory().appendingPathComponent("report-agent.md")
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
          "last_runs": {},
          "issue_repositories": {}
        }
        """
        try? payload.write(to: destination, atomically: true, encoding: .utf8)
    }

    private nonisolated static func createReportAgentIfNeeded() {
        let destination = reportAgentURL()
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        let payload = """
        # PAS Report Agent

        - Slack에 바로 보낼 수 있는 한국어 일일 보고서로 작성한다.
        - 오늘 한 일, 주요 변경점, 확인 필요, 내일 이어갈 일을 포함한다.
        - 과장하지 않고 확인된 사실과 추정을 구분한다.
        - 수동 메모는 Git 근거와 함께 우선 반영한다.
        """
        try? payload.write(to: destination, atomically: true, encoding: .utf8)
    }

    private func markSetupCompleted() throws {
        let url = Self.stateURL()
        var payload: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = existing
        }
        payload["version"] = payload["version"] ?? 1
        payload["updated_at"] = ISO8601DateFormatter().string(from: Date())
        payload["setup_completed"] = true
        payload["last_runs"] = payload["last_runs"] ?? [:]
        payload["issue_repositories"] = payload["issue_repositories"] ?? [:]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
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

struct ReportAgentEditorView: View {
    @ObservedObject var runner: PASRunner

    @State private var rules = ""
    @State private var message = ""
    @State private var lastSavedRules = ""

    private var hasChanges: Bool {
        rules != lastSavedRules
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text("보고서 작성 규칙")
                        .font(.title3)
                        .bold()
                    Text("오늘 작업 보고서를 AI가 어떤 형식과 말투로 정리할지 정합니다.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasChanges {
                    Text("저장 안 됨")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Markdown 규칙")
                        .font(.headline)
                    TextEditor(text: $rules)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.75))
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("작성 가이드")
                        .font(.headline)
                    GuideHint(title: "섹션", detail: "오늘 한 일, 주요 변경점, 확인 필요, 내일 이어갈 일처럼 원하는 순서를 적습니다.")
                    GuideHint(title: "말투", detail: "간결/상세/관리자용, 명사형 선호 같은 톤을 지정합니다.")
                    GuideHint(title: "금지사항", detail: "모르는 내용을 단정하지 않기, 민감정보 제외 같은 규칙을 넣습니다.")
                    GuideHint(title: "우선순위", detail: "수동 메모를 커밋보다 우선할지, Git 근거만 사실로 볼지 정합니다.")
                    Spacer()
                }
                .frame(width: 220)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.contains("실패") ? .red : .secondary)
            }

            HStack {
                Button("기본 예시로 되돌리기") {
                    rules = Self.defaultRules
                }

                Spacer()

                Button("닫기") {
                    runner.closeReportAgentWindow()
                }

                Button("저장") {
                    let result = runner.saveReportAgentRules(rules)
                    message = result.displayText
                    if result.succeeded {
                        lastSavedRules = rules
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasChanges)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 620)
        .task {
            let loaded = runner.loadReportAgentRules()
            rules = loaded
            lastSavedRules = loaded
        }
    }

    private static let defaultRules = """
    # PAS Report Agent

    ## 목표

    - Slack에 바로 보낼 수 있는 한국어 일일 업무 보고서를 작성한다.
    - Git 커밋, 브랜치, 동기화 상태를 근거로 삼고, 사용자가 직접 작성한 메모를 함께 반영한다.
    - 확인된 사실과 추정은 구분한다.

    ## 출력 형식

    1. 오늘 한 일
    2. 주요 변경점
    3. 확인 필요
    4. 내일 이어갈 일

    ## 말투

    - 간결하게 쓴다.
    - 과장하지 않는다.
    - `했습니다`보다 명사형 또는 짧은 문장을 선호한다.

    ## 금지사항

    - 커밋 메시지만으로 알 수 없는 내용을 단정하지 않는다.
    - 민감한 토큰, URL, 개인 정보는 넣지 않는다.
    """
}

private struct GuideHint: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .bold()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct IssueRepositoryLinkView: View {
    @ObservedObject var runner: PASRunner
    let issue: String
    let summary: String

    @State private var repositories: [LocalRepositoryOption] = []
    @State private var selectedPath = ""
    @State private var isLoading = false
    @State private var resultMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(issue) repository 연결")
                        .font(.title3)
                        .bold()
                    Text(summary.isEmpty ? "이 Jira 일감을 어느 로컬 repository에서 처리할지 선택합니다." : summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack {
                Button(isLoading ? "불러오는 중..." : "관리 repository 불러오기") {
                    Task { await reload() }
                }
                .disabled(isLoading || runner.isRunning)

                Text("선택한 연결은 state.json에 저장되고 다음 Jira 브리핑에도 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("관리 중인 로컬 repository를 확인하는 중...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else if repositories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("관리 repository가 없습니다")
                        .font(.headline)
                    Text("설정에서 로컬 repository root와 관리 프로젝트를 먼저 선택해 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(repositories) { repo in
                            Button {
                                selectedPath = repo.path
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedPath == repo.path ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedPath == repo.path ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(repo.name)
                                                .font(.headline)
                                            Text(repo.branch)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(nsColor: .textBackgroundColor))
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        Text("\(repo.syncLabel) | \(repo.path)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(selectedPath == repo.path ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !resultMessage.isEmpty {
                Text(resultMessage)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("닫기") {
                    runner.closeIssueRepositoryLinkWindow()
                }
                Button("연결 저장") {
                    Task { await saveLink() }
                }
                .disabled(selectedPath.isEmpty || runner.isRunning)

                Button("연결 저장 후 브랜치 시작") {
                    Task { await saveLinkAndStartBranch() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPath.isEmpty || runner.isRunning)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
        .task {
            await reload()
        }
    }

    private func reload() async {
        isLoading = true
        repositories = await runner.loadManagedRepositories()
        if selectedPath.isEmpty {
            selectedPath = repositories.first?.path ?? ""
        }
        isLoading = false
    }

    private func saveLink() async {
        let result = await runner.linkIssueRepository(issue: issue, repo: selectedPath, summary: summary)
        resultMessage = result.displayText
        if result.succeeded {
            runner.closeIssueRepositoryLinkWindow()
        }
    }

    private func saveLinkAndStartBranch() async {
        let result = await runner.linkIssueRepository(issue: issue, repo: selectedPath, summary: summary)
        resultMessage = result.displayText
        guard result.succeeded else { return }
        runner.closeIssueRepositoryLinkWindow()
        await runner.createBranch(issue: issue, repo: selectedPath, summary: summary)
    }
}

struct PASCommandResult: Sendable {
    let succeeded: Bool
    let output: String
    let summary: String

    var displayText: String {
        let value = output.isEmpty ? summary : output
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "출력 없음" : value
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

struct GitHubRemoteRepositoryOption: Identifiable, Hashable, Sendable {
    let nameWithOwner: String
    let sshURL: String
    let webURL: String
    let visibility: String
    let defaultBranch: String

    var id: String {
        nameWithOwner
    }

    var shortName: String {
        nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner
    }

    var label: String {
        "\(nameWithOwner) [\(visibility)] \(defaultBranch)"
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

    var needsUpdate: Bool {
        (behind ?? 0) > 0
    }

    var canFastForward: Bool {
        (behind ?? 0) > 0 && (ahead ?? 0) == 0
    }

    var needsRebase: Bool {
        (behind ?? 0) > 0 && (ahead ?? 0) > 0
    }
}
