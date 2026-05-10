import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PASRunner: NSObject, ObservableObject, NSWindowDelegate {
    @Published var isRunning = false
    @Published var status = "대기 중"
    @Published var lastOutput = ""
    @Published var isHandlingDeepLink = false

    private var setupWindow: NSWindow?
    private var workWindow: NSWindow?
    private var outputWindow: NSWindow?
    private var issueLinkWindow: NSWindow?
    private var reportAgentWindow: NSWindow?
    private var shouldOpenSetupOnLaunch = true

    override init() {
        super.init()
        try? Self.prepareSupportFiles()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shouldOpenSetupOnLaunch else { return }
            self.openSetupWindow()
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

    func handleDeepLink(_ url: URL) {
        shouldOpenSetupOnLaunch = false
        isHandlingDeepLink = true
        guard url.scheme == "pas" else {
            status = "지원하지 않는 PAS 링크입니다"
            isHandlingDeepLink = false
            return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if url.host == "branch", url.path == "/create" {
            let issue = Self.queryValue("issue", in: items)
            let repo = Self.queryValue("repo", in: items)
            let summary = Self.queryValue("summary", in: items)
            guard !issue.isEmpty, !repo.isEmpty else {
                status = "브랜치 생성 링크에 필요한 값이 없습니다"
                isHandlingDeepLink = false
                openOutputWindow(title: "PAS 링크 오류", output: "브랜치 생성 링크에 issue 또는 repo 값이 없습니다.\n\n받은 링크: \(url.absoluteString)")
                return
            }
            Task {
                await createBranch(issue: issue, repo: repo, summary: summary)
                isHandlingDeepLink = false
            }
            return
        }

        if url.host == "jira", url.path == "/link" {
            let issue = Self.queryValue("issue", in: items)
            let summary = Self.queryValue("summary", in: items)
            guard !issue.isEmpty else {
                status = "Jira repo 연결 링크에 issue 값이 없습니다"
                isHandlingDeepLink = false
                openOutputWindow(title: "PAS 링크 오류", output: "Jira repository 연결 링크에 issue 값이 없습니다.\n\n받은 링크: \(url.absoluteString)")
                return
            }
            openIssueRepositoryLinkWindow(issue: issue, summary: summary)
            status = "\(issue) repository 연결 선택 대기 중"
            isHandlingDeepLink = false
            return
        }

        status = "지원하지 않는 PAS 링크입니다"
        isHandlingDeepLink = false
        openOutputWindow(title: "PAS 링크 오류", output: "지원하지 않는 PAS 링크입니다.\n\n받은 링크: \(url.absoluteString)")
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
        settingsStore().load()
    }

    func saveSettings(_ settings: PASSettings) {
        do {
            try Self.prepareSupportFiles()
            try settingsStore().save(settings)
            status = "설정을 저장했습니다"
        } catch {
            let message = "설정 저장 실패: \(error.localizedDescription)"
            status = message
            lastOutput = message
            openOutputWindow(title: "PAS 설정 오류", output: message)
        }
    }

    private func settingsStore() -> PASSettingsStore {
        PASSettingsStore(configURL: Self.configURL(), stateURL: Self.stateURL())
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
        status = "관리 Git repository 목록을 불러오는 중..."
        let result = await Self.executeDetached(["repo", "list", "--format", "tsv"])
        lastOutput = result.output
        status = result.succeeded ? "관리 Git repository 목록을 불러왔습니다" : "관리 Git repository 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "관리 Git repository 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
            return []
        }
        return Self.parseLocalRepositories(result.output)
    }

    func loadRemoteRepositories(owner: String) async -> [GitHubRemoteRepositoryOption] {
        status = "GitHub repository 후보를 불러오는 중..."
        var arguments = ["repo", "remote-list", "--format", "tsv"]
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOwner.isEmpty {
            arguments.append(contentsOf: ["--owner", trimmedOwner])
        }
        let result = await Self.executeDetached(arguments)
        lastOutput = result.output
        status = result.succeeded ? "GitHub repository 후보를 불러왔습니다" : "GitHub repository 후보 조회 실패"
        if !result.succeeded {
            openOutputWindow(title: "GitHub repository 후보 조회 오류", output: result.output.isEmpty ? result.summary : result.output)
            return []
        }
        return Self.parseRemoteRepositories(result.output)
    }

    func cloneRemoteRepository(_ repo: GitHubRemoteRepositoryOption, targetRoot: String) async -> PASCommandResult {
        let result = await Self.executeDetached(["repo", "clone", "--repo", repo.cloneSource, "--target-root", targetRoot])
        lastOutput = result.output
        status = result.succeeded ? "\(repo.nameWithOwner) 준비 완료" : "\(repo.nameWithOwner) clone 실패"
        if !result.succeeded {
            openOutputWindow(title: "GitHub repository 가져오기 오류", output: result.output.isEmpty ? result.summary : result.output)
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
        process.environment = processEnvironment()
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

    private nonisolated static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        environment["PATH"] = ([existingPath] + extraPaths)
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        return environment
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
