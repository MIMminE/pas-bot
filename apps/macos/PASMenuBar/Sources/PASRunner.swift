import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class PASRunner: NSObject, ObservableObject, NSWindowDelegate {
    @Published var isRunning = false
    @Published var status = "대기 중"
    @Published var lastOutput = ""
    @Published var isHandlingDeepLink = false
    @Published var activeProfileID = PASProfile.work.id
    @Published var activeProfileIDs: Set<String> = [PASProfile.work.id]
    @Published var isSetupOpen = false
    @Published private(set) var memoTargets: [MemoTargetOption] = [.general]

    private var setupWindow: NSWindow?
    private var workWindow: NSWindow?
    private var outputWindow: NSWindow?
    private var issueLinkWindow: NSWindow?
    private var reportAgentWindow: NSWindow?
    private var quickMemoWindow: NSWindow?
    private var repoCodexTaskWindow: NSWindow?
    private var shouldOpenDashboardOnLaunch = true
    private var memoTargetsLoaded = false
    private var codexHealthCache: (loadedAt: Date, value: CodexHealthStatus)?

    override init() {
        super.init()
        activeProfileIDs = Self.enabledProfileIDs()
        activeProfileID = Self.currentProfileID()
        try? Self.prepareSupportFiles()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shouldOpenDashboardOnLaunch else { return }
            self.openWorkWindow()
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
        let directory = Self.activeSupportDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func switchProfile(to profileID: String) {
        guard PASProfile.profile(for: profileID) != nil, activeProfileIDs.contains(profileID) else {
            status = "비활성 프로필입니다"
            return
        }
        UserDefaults.standard.set(profileID, forKey: Self.activeProfileDefaultsKey)
        activeProfileID = profileID
        do {
            try Self.prepareSupportFiles()
            status = "\(activeProfile.title) 프로필로 전환했습니다"
        } catch {
            status = "프로필 전환 준비 실패: \(error.localizedDescription)"
        }
    }

    var activeProfile: PASProfile {
        PASProfile.profile(for: activeProfileID) ?? .work
    }

    var availableProfiles: [PASProfile] {
        PASProfile.all.filter { activeProfileIDs.contains($0.id) }
    }

    func isProfileEnabled(_ profileID: String) -> Bool {
        activeProfileIDs.contains(profileID)
    }

    func setProfileEnabled(_ profileID: String, enabled: Bool) {
        guard PASProfile.profile(for: profileID) != nil else { return }
        if profileID == PASProfile.work.id && !enabled {
            status = "업무 프로필은 비활성화할 수 없습니다"
            return
        }

        var ids = activeProfileIDs
        if enabled {
            ids.insert(profileID)
        } else {
            ids.remove(profileID)
        }
        ids.insert(PASProfile.work.id)
        activeProfileIDs = ids
        Self.saveEnabledProfileIDs(ids)

        if !ids.contains(activeProfileID) {
            switchProfile(to: PASProfile.work.id)
        } else {
            status = "\(PASProfile.profile(for: profileID)?.title ?? profileID) 프로필을 \(enabled ? "활성화" : "비활성화")했습니다"
        }
    }

    var isPersonalProfile: Bool {
        activeProfile.kind == .personal
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

    func openQuickMemoWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let quickMemoWindow {
            quickMemoWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "빠른 작업 메모"
        window.center()
        window.contentView = NSHostingView(rootView: QuickMemoView(runner: self))
        window.isReleasedWhenClosed = false
        window.delegate = self
        quickMemoWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func openRepoCodexTaskWindow(repo: LocalRepositoryOption) {
        NSApplication.shared.setActivationPolicy(.regular)
        if let repoCodexTaskWindow {
            repoCodexTaskWindow.title = "\(repo.name) Codex 작업"
            repoCodexTaskWindow.contentView = NSHostingView(rootView: RepoCodexTaskView(runner: self, repo: repo))
            repoCodexTaskWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(repo.name) Codex 작업"
        window.center()
        window.contentView = NSHostingView(rootView: RepoCodexTaskView(runner: self, repo: repo))
        window.isReleasedWhenClosed = false
        window.delegate = self
        repoCodexTaskWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func closeRepoCodexTaskWindow() {
        repoCodexTaskWindow?.close()
        repoCodexTaskWindow = nil
        restoreMenuBarModeIfPossible()
    }

    func detectedIDEApps() -> [IDEAppOption] {
        let candidates = [
            "Cursor",
            "Visual Studio Code",
            "IntelliJ IDEA",
            "IntelliJ IDEA CE",
            "PyCharm",
            "WebStorm",
            "Android Studio",
            "Xcode",
            "Sublime Text",
            "Zed",
        ]
        let options = candidates.compactMap { name -> IDEAppOption? in
            guard let url = Self.findApplication(named: name) else { return nil }
            return IDEAppOption(name: name, path: url.path)
        }
        return options.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func openRepositoryInIDE(path: String, appName: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            status = "열 repository 경로가 없습니다"
            return
        }

        let url = URL(fileURLWithPath: trimmedPath)
        if appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            NSWorkspace.shared.open(url)
            status = "\(url.lastPathComponent) 열기 요청"
            return
        }

        let result = Self.executeRaw(["open", "-a", appName, trimmedPath])
        lastOutput = result.output
        status = result.succeeded ? "\(url.lastPathComponent)을 \(appName)로 여는 중" : "\(appName) 실행 실패"
        if !result.succeeded {
            openOutputWindow(title: "IDE 실행 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
    }

    func handleDeepLink(_ url: URL) {
        shouldOpenDashboardOnLaunch = false
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

    func selectCloneDirectory(onSelect: @escaping (String) -> Void) {
        selectDirectory { url in
            onSelect(url.path)
        }
    }

    func openSetupWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let setupWindow {
            if let parent = setupWindow.sheetParent {
                parent.makeKeyAndOrderFront(nil)
            } else {
                setupWindow.makeKeyAndOrderFront(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PAS 설정"
        window.center()
        window.contentView = NSHostingView(rootView: SetupView(runner: self))
        window.isReleasedWhenClosed = false
        window.delegate = self
        setupWindow = window
        isSetupOpen = true
        if let workWindow {
            workWindow.beginSheet(window)
            workWindow.makeKeyAndOrderFront(nil)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
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
        guard let setupWindow else { return }
        if let parent = setupWindow.sheetParent {
            parent.endSheet(setupWindow)
            self.setupWindow = nil
            self.isSetupOpen = false
        } else {
            setupWindow.close()
        }
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

    func closeQuickMemoWindow() {
        quickMemoWindow?.close()
        quickMemoWindow = nil
        restoreMenuBarModeIfPossible()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            guard let window = notification.object as? NSWindow else { return }
            if window === self.workWindow {
                self.workWindow = nil
            } else if window === self.setupWindow {
                self.setupWindow = nil
                self.isSetupOpen = false
            } else if window === self.outputWindow {
                self.outputWindow = nil
            } else if window === self.issueLinkWindow {
                self.issueLinkWindow = nil
            } else if window === self.reportAgentWindow {
                self.reportAgentWindow = nil
            } else if window === self.quickMemoWindow {
                self.quickMemoWindow = nil
            } else if window === self.repoCodexTaskWindow {
                self.repoCodexTaskWindow = nil
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

    func checkGitHubAuthStatus() async -> PASCommandResult {
        status = "GitHub CLI 로그인 상태를 확인하는 중..."
        let result = await Self.executeDetachedRaw(["gh", "auth", "status"])
        lastOutput = result.output
        status = result.succeeded ? "GitHub CLI 로그인 상태 정상" : "GitHub CLI 로그인이 필요합니다"
        openOutputWindow(
            title: result.succeeded ? "GitHub CLI 로그인 상태" : "GitHub CLI 로그인 필요",
            output: result.output.isEmpty ? result.summary : result.output
        )
        return PASCommandResult(succeeded: result.succeeded, output: result.output, summary: result.summary)
    }

    func openGitHubLoginInTerminal() {
        do {
            try Self.prepareSupportFiles()
            let scriptURL = Self.activeSupportDirectory().appendingPathComponent("gh-auth-login.command")
            let script = """
            #!/bin/zsh
            clear
            echo "PAS GitHub CLI 로그인"
            echo ""
            if ! command -v gh >/dev/null 2>&1; then
              echo "GitHub CLI(gh)를 찾지 못했습니다."
              echo "먼저 https://cli.github.com/ 에서 gh를 설치해 주세요."
              echo ""
              echo "Enter를 누르면 닫힙니다."
              read -r
              exit 1
            fi
            echo "브라우저 또는 터미널 안내에 따라 GitHub 로그인을 완료해 주세요."
            echo ""
            gh auth login
            echo ""
            echo "현재 로그인 상태:"
            gh auth status
            echo ""
            echo "완료 후 Enter를 누르면 닫힙니다."
            read -r
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            NSWorkspace.shared.open(scriptURL)
            status = "GitHub CLI 로그인 터미널을 열었습니다"
        } catch {
            let message = "GitHub CLI 로그인 터미널 열기 실패: \(error.localizedDescription)"
            status = message
            openOutputWindow(title: "GitHub CLI 로그인 오류", output: message)
        }
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
            await withTaskGroup(of: Void.self) { group in
                for repo in repos {
                    group.addTask {
                        _ = await Self.executeDetached(["repo", "update", "--repo", repo.path, "--mode", "fetch"])
                    }
                }
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

    func loadRepositoryBranches(path: String) async -> [BranchOption] {
        let result = await Self.executeDetached(["repo", "branches", "--repo", path, "--format", "tsv"])
        if !result.succeeded {
            return []
        }
        return Self.parseBranchOptions(result.output)
    }

    func checkoutRepositoryBranch(path: String, branch: String) async -> PASCommandResult {
        guard !isRunning else {
            return PASCommandResult(succeeded: false, output: "", summary: "이미 실행 중인 작업이 있습니다.")
        }
        isRunning = true
        status = "\(branch) 체크아웃 중..."
        let result = await Self.executeDetached(["repo", "checkout", "--repo", path, "--branch", branch])
        lastOutput = result.output
        status = result.succeeded ? "\(branch) 체크아웃 완료" : "\(branch) 체크아웃 실패"
        isRunning = false
        if !result.succeeded {
            openOutputWindow(title: "브랜치 체크아웃 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded, output: result.output, summary: result.summary)
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
        let result = await Self.executeDetached(["dev", "create-branch", "--repo", repo, "--issue-key", issue, "--summary", summary])
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

    func startIssueWork(issue: String, summary: String) async -> PASCommandResult {
        guard !isRunning else {
            return PASCommandResult(succeeded: false, output: "", summary: "이미 실행 중인 작업이 있습니다.")
        }
        isRunning = true
        status = "\(issue) 작업 브랜치 준비 중..."
        let result = await Self.executeDetached(["dev", "start-issue", issue, "--summary", summary])
        lastOutput = result.output
        status = result.succeeded ? "\(issue) 작업 준비 완료" : "\(issue) 작업 준비 실패"
        isRunning = false
        if !result.succeeded {
            openOutputWindow(title: "Jira 작업 시작 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded, output: result.output, summary: result.summary)
    }

    func recommendIssueRepository(issue: String, summary: String) async -> PASCommandResult {
        let result = await runDashboardCommand(
            ["dev", "recommend-repo", issue, "--summary", summary],
            runningStatus: "\(issue) repository 추천 중...",
            successStatus: "\(issue) repository 추천 완료",
            failureStatus: "\(issue) repository 추천 실패"
        )
        if !result.succeeded {
            openOutputWindow(title: "Repository 추천 오류", output: result.displayText)
        }
        return result
    }

    func traceIssueWork(issue: String) async -> PASCommandResult {
        let result = await runDashboardCommand(
            ["dev", "trace-issue", issue],
            runningStatus: "\(issue) 작업 연결 추적 중...",
            successStatus: "\(issue) 작업 연결 추적 완료",
            failureStatus: "\(issue) 작업 연결 추적 실패"
        )
        if !result.succeeded {
            openOutputWindow(title: "Jira 작업 추적 오류", output: result.displayText)
        }
        return result
    }

    func createJiraIssue(
        summary: String,
        description: String,
        issueType: String,
        assignee: String,
        priority: String,
        dueDate: String,
        labels: String
    ) async -> PASCommandResult {
        var arguments = [
            "jira",
            "create",
            "--summary",
            summary,
            "--description",
            description,
            "--type",
            issueType,
        ]
        if !assignee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--assignee", assignee])
        }
        if !priority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--priority", priority])
        }
        if !dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--due-date", dueDate])
        }
        if !labels.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--labels", labels])
        }
        let result = await runDashboardCommand(
            arguments,
            runningStatus: "Jira 일감을 생성하는 중...",
            successStatus: "Jira 일감 생성 완료",
            failureStatus: "Jira 일감 생성 실패"
        )
        if !result.succeeded {
            openOutputWindow(title: "Jira 일감 생성 오류", output: result.displayText)
        }
        return result
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

    func checkNewJiraIssues() async -> PASCommandResult {
        status = "새 Jira 일감을 확인하는 중..."
        let result = await Self.executeDetached(["jira", "watch-new"])
        lastOutput = result.output
        status = result.succeeded ? "새 Jira 일감 확인 완료" : "새 Jira 일감 확인 실패"
        if !result.succeeded {
            openOutputWindow(title: "새 Jira 일감 확인 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded, output: result.output, summary: result.summary)
    }

    func sendLocalNotification(title: String, body: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            status = "로컬 알림은 앱 번들 실행에서만 동작합니다"
            return
        }

        let trimmedBody = body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: " ")
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = trimmedBody.isEmpty ? "새 알림이 있습니다." : String(trimmedBody.prefix(700))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "pas-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().add(request)
        }
    }

    func previewDailyReport(notes: String = "") async -> String {
        status = "오늘 한 일 초안을 만드는 중..."
        var arguments = ["repo", "daily-draft"]
        return await createReport(arguments: &arguments, notes: notes, runningTitle: "오늘 한 일 초안", failureTitle: "오늘 한 일 초안 생성 오류")
    }

    private func createReport(arguments: inout [String], notes: String, runningTitle: String, failureTitle: String) async -> String {
        var notesURL: URL?
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let temporaryNotesURL = Self.activeSupportDirectory().appendingPathComponent("report-notes-\(UUID().uuidString).txt")
            do {
                try notes.write(to: temporaryNotesURL, atomically: true, encoding: .utf8)
                notesURL = temporaryNotesURL
                arguments.append(contentsOf: ["--notes-file", temporaryNotesURL.path])
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
        status = result.succeeded ? "\(runningTitle)을 만들었습니다" : "\(runningTitle) 생성 실패"
        if !result.succeeded {
            openOutputWindow(title: failureTitle, output: result.output.isEmpty ? result.summary : result.output)
        }
        return result.output.isEmpty ? result.summary : result.output
    }

    func makeChatGPTReportPrompt(draft: String, notes: String = "") -> String {
        let rules = (try? String(contentsOf: Self.reportAgentURL(), encoding: .utf8)) ?? ""
        let noteSection = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "- 없음" : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftSection = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "- 먼저 초안 만들기를 실행해 Git 근거를 채워 주세요." : draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        아래 Git 근거와 수동 메모를 바탕으로 한국어 일일 업무 보고서를 작성해줘.

        조건:
        - 확인된 사실과 추정을 구분해줘.
        - 커밋 메시지만으로 알 수 없는 내용은 단정하지 마.
        - Slack에 바로 보낼 수 있게 간결하게 작성해줘.
        - 섹션은 오늘 한 일, 주요 변경점, 확인 필요, 내일 이어갈 일 순서로 정리해줘.

        [보고서 작성 규칙]
        \(rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "- 기본 형식: 오늘 한 일, 주요 변경점, 확인 필요, 내일 이어갈 일" : rules.trimmingCharacters(in: .whitespacesAndNewlines))

        [수동 메모]
        \(noteSection)

        [Git 근거 초안]
        \(draftSection)
        """
    }

    func refineReportWithCodex(draft: String, notes: String = "") async -> PASCommandResult {
        let codexURL = Self.codexExecutableURL()
        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            let message = "Codex CLI를 찾지 못했습니다: \(codexURL.path)"
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }

        let outputURL = Self.activeSupportDirectory().appendingPathComponent("codex-report-\(UUID().uuidString).md")
        let prompt = makeCodexReportPrompt(draft: draft, notes: notes)
        isRunning = true
        status = "Codex로 보고서를 다듬는 중..."
        let result = await Self.executeDetachedRaw(
            [
                "exec",
                "-C",
                Self.projectRootURL().path,
                "-o",
                outputURL.path,
                "-",
            ],
            executableURL: codexURL,
            standardInput: prompt
        )
        let refined = (try? String(contentsOf: outputURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try? FileManager.default.removeItem(at: outputURL)

        let output = refined.isEmpty ? result.output : refined
        lastOutput = output
        status = result.succeeded ? "Codex 보고서 다듬기 완료" : "Codex 보고서 다듬기 실패"
        isRunning = false
        if !result.succeeded {
            openOutputWindow(title: "Codex 보고서 다듬기 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, output: output, summary: result.summary)
    }

    private func makeCodexReportPrompt(draft: String, notes: String = "") -> String {
        let rules = (try? String(contentsOf: Self.reportAgentURL(), encoding: .utf8)) ?? ""
        let noteSection = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "- 없음" : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftSection = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "- 입력 초안 없음" : draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        너는 PAS 앱 안에서 개발자의 하루를 같이 정리해주는 보고서 도우미다.
        아래 근거만 사용해서 한국어 일일 업무 보고서를 차분하고 자연스럽게 작성해줘.

        요구사항:
        - 확인된 사실과 추정은 섞지 말고, 커밋/PR 제목만으로 모르는 내용은 단정하지 말아줘.
        - Slack이나 메신저에 바로 붙여넣을 수 있게 너무 장황하지 않게 써줘.
        - 섹션은 "오늘 한 일", "주요 변경점", "확인 필요", "내일 이어갈 일" 순서로 작성해줘.
        - Jira 키, repository 이름, PR/커밋 근거가 있으면 자연스럽게 보존해라.
        - 출력은 보고서 본문만 작성하고, 설명이나 메타 코멘트는 붙이지 말아줘.

        [보고서 작성 규칙]
        \(rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "- 기본 형식: 오늘 한 일, 주요 변경점, 확인 필요, 내일 이어갈 일" : rules.trimmingCharacters(in: .whitespacesAndNewlines))

        [수동 메모]
        \(noteSection)

        [PAS 수집 초안]
        \(draftSection)
        """
    }

    func refineMemoWithCodex(text: String, targetTitle: String) async -> PASCommandResult {
        await askCodexAboutMemo(text: text, targetTitle: targetTitle, question: "메모를 짧고 실무적으로 다듬어줘. 사실을 새로 만들지 말고, 다듬은 메모 본문만 알려줘.")
    }

    func askCodexAboutMemo(text: String, targetTitle: String, question: String) async -> PASCommandResult {
        let codexURL = Self.codexExecutableURL()
        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            let message = "Codex CLI를 찾지 못했습니다: \(codexURL.path)"
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }

        let outputURL = Self.activeSupportDirectory().appendingPathComponent("codex-memo-\(UUID().uuidString).md")
        let prompt = """
        너는 PAS 빠른 작업 메모를 같이 정리해주는 동료 같은 도우미다.
        사용자의 메모 초안을 바탕으로 질문에 답해줘.
        사실을 새로 만들지 말고, 메모의 의도와 불확실성은 보존해줘.
        답변은 바로 메모에 붙여도 어색하지 않게 짧고 실무적으로 작성해줘.

        [작업]
        \(targetTitle.isEmpty ? "일반 메모" : targetTitle)

        [요청]
        \(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "이 메모를 다듬어줘." : question)

        [메모 초안]
        \(text)
        """
        isRunning = true
        status = "Codex와 메모를 정리하는 중..."
        let result = await Self.executeDetachedRaw(
            ["exec", "-C", Self.projectRootURL().path, "-o", outputURL.path, "-"],
            executableURL: codexURL,
            standardInput: prompt
        )
        let refined = (try? String(contentsOf: outputURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try? FileManager.default.removeItem(at: outputURL)
        let output = refined.isEmpty ? result.output : refined
        lastOutput = output
        status = result.succeeded ? "Codex 메모 응답 완료" : "Codex 메모 응답 실패"
        isRunning = false
        if !result.succeeded {
            openOutputWindow(title: "Codex 메모 응답 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, output: output, summary: result.summary)
    }

    func sendEditedReport(_ text: String) async -> String {
        let url = Self.activeSupportDirectory().appendingPathComponent("edited-report-\(UUID().uuidString).txt")
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

    func submitReport(_ text: String, notes: String = "", sendSlack: Bool) async -> PASCommandResult {
        let reportURL = Self.activeSupportDirectory().appendingPathComponent("submitted-report-\(UUID().uuidString).md")
        let notesURL = Self.activeSupportDirectory().appendingPathComponent("submitted-report-notes-\(UUID().uuidString).txt")
        do {
            try text.write(to: reportURL, atomically: true, encoding: .utf8)
            try notes.write(to: notesURL, atomically: true, encoding: .utf8)
        } catch {
            let message = "보고서 제출 임시 파일 저장 실패: \(error.localizedDescription)"
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }

        var arguments = ["repo", "submit-report", "--text-file", reportURL.path, "--notes-file", notesURL.path]
        if sendSlack {
            arguments.append("--send-slack")
        }
        isRunning = true
        status = sendSlack ? "보고서를 앱 기록과 Slack에 제출하는 중..." : "보고서를 앱 기록에 제출하는 중..."
        let result = await Self.executeDetached(arguments)
        try? FileManager.default.removeItem(at: reportURL)
        try? FileManager.default.removeItem(at: notesURL)
        lastOutput = result.output
        status = result.succeeded ? "보고서 제출 완료" : "보고서 제출 실패"
        isRunning = false
        if !result.succeeded {
            openOutputWindow(title: "보고서 제출 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded, output: result.output, summary: result.summary)
    }

    func loadSubmittedReports() async -> [SubmittedReportRecord] {
        let result = await Self.executeDetached(["repo", "report-history", "--format", "json"])
        lastOutput = result.output
        if !result.succeeded {
            status = "보고서 기록 조회 실패"
            return []
        }
        status = "보고서 기록을 불러왔습니다"
        guard let data = result.output.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([SubmittedReportRecord].self, from: data)) ?? []
    }

    func saveWorkMemo(target: MemoTargetOption, text: String) async -> PASCommandResult {
        let memoURL = Self.activeSupportDirectory().appendingPathComponent("work-memo-\(UUID().uuidString).md")
        do {
            try text.write(to: memoURL, atomically: true, encoding: .utf8)
        } catch {
            let message = "작업 메모 임시 파일 저장 실패: \(error.localizedDescription)"
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }
        isRunning = true
        status = "작업 메모 저장 중..."
        let result = await Self.executeDetached([
            "memo",
            "add",
            "--target-type",
            target.type,
            "--target-id",
            target.targetID,
            "--target-title",
            target.title,
            "--text-file",
            memoURL.path,
        ])
        try? FileManager.default.removeItem(at: memoURL)
        lastOutput = result.output
        status = result.succeeded ? "작업 메모 저장 완료" : "작업 메모 저장 실패"
        isRunning = false
        if !result.succeeded {
            openOutputWindow(title: "작업 메모 저장 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded, output: result.output, summary: result.summary)
    }

    func loadWorkMemos() async -> [WorkMemoRecord] {
        let result = await Self.executeDetached(["memo", "list", "--format", "json"])
        lastOutput = result.output
        if !result.succeeded {
            status = "작업 메모 조회 실패"
            return []
        }
        guard let data = result.output.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([WorkMemoRecord].self, from: data)) ?? []
    }

    func loadMemoTargets(forceRefresh: Bool = false) async -> [MemoTargetOption] {
        if memoTargetsLoaded && !forceRefresh {
            return memoTargets
        }
        async let reposTask = loadManagedRepositories()
        async let jiraTask = Self.executeDetached(["jira", "today"])

        var targets = [MemoTargetOption.general]
        let repos = await reposTask
        targets.append(contentsOf: repos.prefix(12).map {
            MemoTargetOption(type: "repo", targetID: $0.name, title: $0.name, subtitle: $0.branch)
        })

        let jiraResult = await jiraTask
        if jiraResult.succeeded {
            targets.append(contentsOf: Self.parseJiraMemoTargets(jiraResult.output))
        }
        memoTargets = targets
        memoTargetsLoaded = true
        status = "메모 대상을 불러왔습니다"
        return targets
    }

    func openCodexWorkspaceForIssue(issue: String, summary: String, detail: String, repositories: [LocalRepositoryOption]) async -> PASCommandResult {
        let codexURL = Self.codexExecutableURL()
        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            let message = "Codex CLI를 찾지 못했습니다: \(codexURL.path)"
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }
        let repoPaths = repositories.map { URL(fileURLWithPath: $0.path).standardizedFileURL }
        guard let workspaceRoot = Self.commonWorkspaceRoot(for: repoPaths) else {
            let message = "Codex로 열 작업 루트를 결정하지 못했습니다."
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }

        let contextDirectory = workspaceRoot.appendingPathComponent(".pas-codex", isDirectory: true)
        let contextURL = contextDirectory.appendingPathComponent("\(issue)-context.md")
        let repoList = repositories
            .map { "- \($0.name): \($0.path) | branch \($0.branch)" }
            .joined(separator: "\n")
        let memoList = (await loadWorkMemos())
            .filter { $0.targetID == issue || $0.targetTitle.localizedCaseInsensitiveContains(issue) }
            .prefix(8)
            .map { "- [\($0.date)] \($0.text)" }
            .joined(separator: "\n")
        let context = """
        # \(issue) Codex 작업 컨텍스트

        ## Jira
        - Key: \(issue)
        - Summary: \(summary.isEmpty ? "-" : summary)

        ## Detail
        \(detail.isEmpty ? "-" : detail)

        ## Managed Repositories
        \(repoList.isEmpty ? "- 관리 저장소 없음" : repoList)

        ## Work Memos
        \(memoList.isEmpty ? "- 연결된 메모 없음" : memoList)

        ## Suggested Guardrails
        - 이 작업은 위 관리 repository 범위 안에서만 검토한다.
        - 변경 전 현재 브랜치와 미커밋 변경을 확인한다.
        - 커밋/브랜치 메시지에는 Jira 키 \(issue)를 유지한다.
        """

        do {
            try FileManager.default.createDirectory(at: contextDirectory, withIntermediateDirectories: true)
            try context.write(to: contextURL, atomically: true, encoding: .utf8)
        } catch {
            let message = "Codex 컨텍스트 파일 생성 실패: \(error.localizedDescription)"
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }

        status = "Codex 작업 루트를 여는 중..."
        let result = await Self.executeDetachedRaw(["app", workspaceRoot.path], executableURL: codexURL)
        let output = """
        Codex 작업 루트를 열었습니다.
        - workspace: \(workspaceRoot.path)
        - context: \(contextURL.path)

        Codex에서 위 context 파일을 참고해 \(issue) 작업을 이어가면 됩니다.

        \(result.output)
        """
        lastOutput = output
        status = result.succeeded ? "Codex 작업 루트 열기 완료" : "Codex 작업 루트 열기 실패"
        if !result.succeeded {
            openOutputWindow(title: "Codex 작업 루트 열기 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded, output: output, summary: result.summary)
    }

    func openCodexForRepositoryTask(repo: LocalRepositoryOption, instruction: String, convention: String, taskKind: String) async -> PASCommandResult {
        let codexURL = Self.codexExecutableURL()
        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            let message = "Codex CLI를 찾지 못했습니다: \(codexURL.path)"
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }

        let repoURL = URL(fileURLWithPath: repo.path, isDirectory: true).standardizedFileURL
        let contextDirectory = repoURL.appendingPathComponent(".pas-codex", isDirectory: true)
        let contextURL = contextDirectory.appendingPathComponent("repo-task-\(Date().timeIntervalSince1970).md")
        let context = """
        # \(repo.name) Codex 작업 지시

        ## Repository
        - path: \(repo.path)
        - current branch: \(repo.branch)
        - base: \(repo.baseLabel)
        - sync: \(repo.syncLabel)
        - dirty files: \(repo.dirtyCount)

        ## 작업 유형
        \(taskKind)

        ## 지시
        \(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "- 사용자가 추가 지시를 작성하지 않았습니다." : instruction)

        ## 컨벤션/주의사항
        \(convention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "- repository의 기존 컨벤션과 AGENTS.md가 있다면 우선 따릅니다." : convention)

        ## 기본 가드레일
        - 작업 전 `git status`와 현재 브랜치를 확인합니다.
        - 사용자가 명시하지 않은 파일은 불필요하게 수정하지 않습니다.
        - 커밋/PR 생성 전 변경 단위와 메시지를 한번 점검합니다.
        - 위험한 명령이나 원격 반영은 사용자 승인 흐름을 따릅니다.
        """

        do {
            try FileManager.default.createDirectory(at: contextDirectory, withIntermediateDirectories: true)
            try context.write(to: contextURL, atomically: true, encoding: .utf8)
        } catch {
            let message = "Codex repository 작업 컨텍스트 생성 실패: \(error.localizedDescription)"
            status = message
            return PASCommandResult(succeeded: false, output: message, summary: message)
        }

        status = "\(repo.name) Codex 작업을 여는 중..."
        let result = await Self.executeDetachedRaw(["app", repoURL.path], executableURL: codexURL)
        let output = """
        Codex repository 작업을 열었습니다.
        - repository: \(repo.path)
        - context: \(contextURL.path)

        Codex에서 위 context 파일을 참고해 작업을 지시하세요.

        \(result.output)
        """
        lastOutput = output
        status = result.succeeded ? "\(repo.name) Codex 열기 완료" : "\(repo.name) Codex 열기 실패"
        if !result.succeeded {
            openOutputWindow(title: "Codex repository 작업 오류", output: result.output.isEmpty ? result.summary : result.output)
        }
        return PASCommandResult(succeeded: result.succeeded, output: output, summary: result.summary)
    }

    func loadCodexHealth() async -> CodexHealthStatus {
        if let cache = codexHealthCache, Date().timeIntervalSince(cache.loadedAt) < 60 {
            return cache.value
        }

        let codexURL = Self.codexExecutableURL()
        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            let value = CodexHealthStatus(
                isAvailable: false,
                version: "미설치",
                authMethod: "확인 불가",
                executablePath: codexURL.path,
                detail: "Codex CLI 실행 파일을 찾지 못했습니다."
            )
            codexHealthCache = (Date(), value)
            return value
        }

        async let versionTask = Self.executeDetachedRaw(["--version"], executableURL: codexURL)
        async let loginTask = Self.executeDetachedRaw(["login", "status"], executableURL: codexURL)
        let (versionResult, loginResult) = await (versionTask, loginTask)
        let version = Self.cleanCodexOutput(versionResult.output).first ?? "버전 확인 실패"
        let loginLines = Self.cleanCodexOutput(loginResult.output)
        let loginText = loginLines.joined(separator: " ")
        let authMethod: String
        if loginText.localizedCaseInsensitiveContains("ChatGPT") {
            authMethod = "ChatGPT 로그인"
        } else if loginText.localizedCaseInsensitiveContains("API") {
            authMethod = "API Key"
        } else if loginResult.succeeded {
            authMethod = loginText.isEmpty ? "로그인됨" : loginText
        } else {
            authMethod = "로그인 필요"
        }
        let value = CodexHealthStatus(
            isAvailable: versionResult.succeeded && loginResult.succeeded,
            version: version,
            authMethod: authMethod,
            executablePath: codexURL.path,
            detail: loginText.isEmpty ? loginResult.summary : loginText
        )
        codexHealthCache = (Date(), value)
        return value
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
                    dirtyCount: Int(String(parts[5])) ?? 0,
                    baseBranch: parts.count > 6 ? String(parts[6]) : "",
                    baseRef: parts.count > 7 ? String(parts[7]) : "",
                    baseBehind: parts.count > 8 ? Int(String(parts[8])) : nil,
                    baseAhead: parts.count > 9 ? Int(String(parts[9])) : nil,
                    isWorkingBranch: parts.count > 10 ? String(parts[10]) == "1" : false,
                    baseRebaseAlert: parts.count > 11 ? String(parts[11]) : "",
                    todayCommitCount: parts.count > 12 ? Int(String(parts[12])) ?? 0 : 0,
                    todayCommitLatest: parts.count > 13 ? String(parts[13]) : "",
                    baseCommitSummary: parts.count > 14 ? String(parts[14]) : "",
                    autoSyncMessage: parts.count > 15 ? String(parts[15]) : "",
                    pullRequestSummary: parts.count > 16 ? String(parts[16]) : "",
                    releaseSummary: parts.count > 17 ? String(parts[17]) : ""
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func parseBranchOptions(_ output: String) -> [BranchOption] {
        output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 3 else { return nil }
                return BranchOption(
                    name: String(parts[0]),
                    current: String(parts[1]) == "1",
                    remote: String(parts[2]) == "1"
                )
            }
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

    private nonisolated static func findApplication(named name: String) -> URL? {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
        ]
        for root in roots {
            let direct = root.appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
        }
        let workspaceURL = URL(fileURLWithPath: "/Applications").appendingPathComponent("JetBrains Toolbox").appendingPathComponent("\(name).app")
        if FileManager.default.fileExists(atPath: workspaceURL.path) {
            return workspaceURL
        }
        return nil
    }

    private nonisolated static func executeDetached(_ arguments: [String]) async -> (succeeded: Bool, output: String, summary: String) {
        await Task.detached(priority: .userInitiated) {
            Self.execute(arguments)
        }.value
    }

    private nonisolated static func executeDetachedRaw(
        _ command: [String],
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        standardInput: String? = nil
    ) async -> (succeeded: Bool, output: String, summary: String) {
        await Task.detached(priority: .userInitiated) {
            Self.executeRaw(command, executableURL: executableURL, standardInput: standardInput)
        }.value
    }

    private nonisolated static func execute(_ arguments: [String]) -> (succeeded: Bool, output: String, summary: String) {
        let executable = pasExecutable()
        return executeRaw(executable.prefixArguments + [
            "--config",
            configURL().path
        ] + arguments, executableURL: executable.url)
    }

    private nonisolated static func executeRaw(
        _ arguments: [String],
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        standardInput: String? = nil
    ) -> (succeeded: Bool, output: String, summary: String) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = processEnvironment()
        process.standardOutput = stdout
        process.standardError = stderr
        if standardInput != nil {
            process.standardInput = stdin
        }

        do {
            try prepareSupportFiles()
            try process.run()
            if let standardInput {
                stdin.fileHandleForWriting.write(Data(standardInput.utf8))
                try? stdin.fileHandleForWriting.close()
            }
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

    private nonisolated static func codexExecutableURL() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["CODEX_BIN"], !explicit.isEmpty {
            return URL(fileURLWithPath: explicit)
        }
        return URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
    }

    private nonisolated static func commonWorkspaceRoot(for urls: [URL]) -> URL? {
        let paths = urls.map { $0.deletingLastPathComponent().standardizedFileURL.pathComponents }
        guard var common = paths.first, !common.isEmpty else {
            return nil
        }
        for path in paths.dropFirst() {
            var index = 0
            while index < min(common.count, path.count), common[index] == path[index] {
                index += 1
            }
            common = Array(common.prefix(index))
        }
        guard !common.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
    }

    private nonisolated static func cleanCodexOutput(_ output: String) -> [String] {
        output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("WARNING:") }
    }

    private nonisolated static func parseJiraMemoTargets(_ output: String) -> [MemoTargetOption] {
        let pattern = #"[A-Z][A-Z0-9]+-\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var seen = Set<String>()
        return output
            .split(separator: "\n")
            .compactMap { rawLine -> MemoTargetOption? in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      let swiftRange = Range(match.range, in: line) else {
                    return nil
                }
                let key = String(line[swiftRange])
                guard !seen.contains(key) else {
                    return nil
                }
                seen.insert(key)
                let title = line
                    .replacingOccurrences(of: "- ", with: "")
                    .replacingOccurrences(of: "[\(key)]", with: "")
                    .replacingOccurrences(of: key, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -|[]").union(.whitespacesAndNewlines))
                return MemoTargetOption(type: "jira", targetID: key, title: title.isEmpty ? key : title, subtitle: key)
            }
    }

    private nonisolated static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        let extraPaths = [
            projectRootURL().appendingPathComponent(".venv/bin").path,
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
        environment["PAS_APP_DATA_DIR"] = activeSupportDirectory().path
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
        guard workWindow == nil,
              setupWindow == nil,
              outputWindow == nil,
              issueLinkWindow == nil,
              reportAgentWindow == nil,
              quickMemoWindow == nil,
              repoCodexTaskWindow == nil else { return }
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
        let directory = activeSupportDirectory()
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
        if let explicit = ProcessInfo.processInfo.environment["PAS_BIN"], !explicit.isEmpty {
            return (URL(fileURLWithPath: explicit), [])
        }
        if let bundled = Bundle.main.url(forResource: "pas", withExtension: nil, subdirectory: "bin") {
            return (bundled, [])
        }
        let developmentPas = projectRootURL().appendingPathComponent(".venv/bin/pas")
        if FileManager.default.isExecutableFile(atPath: developmentPas.path) {
            return (developmentPas, [])
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["pas"])
    }

    private nonisolated static func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private nonisolated static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PAS", isDirectory: true)
    }

    private nonisolated static let activeProfileDefaultsKey = "pas.activeProfile"
    private nonisolated static let enabledProfilesDefaultsKey = "pas.enabledProfiles"

    private nonisolated static func currentProfileID() -> String {
        let value = UserDefaults.standard.string(forKey: activeProfileDefaultsKey) ?? PASProfile.work.id
        let enabled = enabledProfileIDs()
        guard let profile = PASProfile.profile(for: value), enabled.contains(profile.id) else {
            return PASProfile.work.id
        }
        return profile.id
    }

    private nonisolated static func enabledProfileIDs() -> Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: enabledProfilesDefaultsKey) ?? [PASProfile.work.id]
        var ids = Set(values.filter { PASProfile.profile(for: $0) != nil })
        ids.insert(PASProfile.work.id)
        return ids
    }

    private nonisolated static func saveEnabledProfileIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: enabledProfilesDefaultsKey)
    }

    private nonisolated static func activeSupportDirectory() -> URL {
        let root = supportDirectory()
        switch currentProfileID() {
        case PASProfile.personal.id:
            return root
                .appendingPathComponent("profiles", isDirectory: true)
                .appendingPathComponent(PASProfile.personal.id, isDirectory: true)
        default:
            return root
        }
    }

    private nonisolated static func configURL() -> URL {
        activeSupportDirectory().appendingPathComponent("config.toml")
    }

    private nonisolated static func assigneesURL() -> URL {
        activeSupportDirectory().appendingPathComponent("assignees.json")
    }

    private nonisolated static func reportAgentURL() -> URL {
        activeSupportDirectory().appendingPathComponent("report-agent.md")
    }

    private nonisolated static func logsDirectory() -> URL {
        activeSupportDirectory().appendingPathComponent("logs", isDirectory: true)
    }

    private nonisolated static func snapshotsDirectory() -> URL {
        activeSupportDirectory().appendingPathComponent("snapshots", isDirectory: true)
    }

    private nonisolated static func stateURL() -> URL {
        activeSupportDirectory().appendingPathComponent("state.json")
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
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
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

struct SubmittedReportRecord: Identifiable, Codable, Hashable {
    let id: String
    let date: String
    let submittedAt: String
    let title: String
    let text: String
    let notes: String
    let slackSent: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case submittedAt = "submitted_at"
        case title
        case text
        case notes
        case slackSent = "slack_sent"
    }
}

struct MemoTargetOption: Identifiable, Hashable {
    let type: String
    let targetID: String
    let title: String
    let subtitle: String

    var id: String {
        "\(type):\(targetID)"
    }

    static let general = MemoTargetOption(type: "general", targetID: "general", title: "일반 메모", subtitle: "작업 미지정")
}

struct WorkMemoRecord: Identifiable, Codable, Hashable {
    let id: String
    let date: String
    let createdAt: String
    let targetType: String
    let targetID: String
    let targetTitle: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case createdAt = "created_at"
        case targetType = "target_type"
        case targetID = "target_id"
        case targetTitle = "target_title"
        case text
    }
}

struct CodexHealthStatus: Hashable {
    let isAvailable: Bool
    let version: String
    let authMethod: String
    let executablePath: String
    let detail: String

    static let unknown = CodexHealthStatus(
        isAvailable: false,
        version: "확인 전",
        authMethod: "확인 전",
        executablePath: "/Applications/Codex.app/Contents/Resources/codex",
        detail: "아직 확인하지 않았습니다."
    )
}
