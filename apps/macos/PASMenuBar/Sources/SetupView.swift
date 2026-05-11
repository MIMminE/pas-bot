import SwiftUI

struct SetupView: View {
    @ObservedObject var runner: PASRunner

    @State private var settings: PASSettings
    @State private var slackChannels: [SlackChannel] = []
    @State private var localRepositories: [LocalRepositoryOption] = []
    @State private var remoteRepositories: [GitHubRemoteRepositoryOption] = []
    @State private var ideApps: [IDEAppOption] = []
    @State private var selectedRemoteRepositoryIDs: Set<String> = []
    @State private var remoteOwner = ""
    @State private var remoteCloneRoot = ""
    @State private var isLoadingSlackChannels = false
    @State private var isLoadingLocalRepositories = false
    @State private var isLoadingRemoteRepositories = false
    @State private var isCloningRemoteRepositories = false
    @State private var isCheckingGitHubAuth = false
    @State private var isSlackExpanded = true
    @State private var isJiraExpanded = true
    @State private var isDeveloperExpanded = true
    @State private var isAutomationExpanded = false
    @State private var isTestExpanded = false

    init(runner: PASRunner) {
        self.runner = runner
        let loadedSettings = runner.loadSettings()
        _settings = State(initialValue: loadedSettings)
        _remoteCloneRoot = State(initialValue: loadedSettings.cloneRoot)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    slackSection
                    jiraSection
                    developerSection
                    automationSection
                    testSection
                }
                .padding(20)
            }

            footer
        }
        .frame(minWidth: 720, minHeight: 660)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PAS 설정")
                    .font(.title2)
                    .bold()

                Text("Jira, Slack, 로컬 Git 작업 보고를 개인 개발 비서 흐름에 맞게 연결합니다.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusPill
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusPill: some View {
        Text(runner.status)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var slackSection: some View {
        SettingsSection(
            title: "Slack 채널 설정",
            summary: "기능별 알림을 보낼 Slack 채널을 연결합니다.",
            systemImage: "number",
            isExpanded: $isSlackExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Slack 앱 Bot Token으로 채널 목록을 불러오고, 기능별 전송 채널을 지정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsSecureField(title: "Bot Token", placeholder: "xoxb-...", text: $settings.slackBotToken)

                GuideBox(
                    title: "Slack 앱 연결 안내",
                    lines: [
                        "Slack App을 만들고 Bot Token Scopes에 chat:write, channels:read를 추가합니다.",
                        "비공개 채널까지 선택하려면 groups:read도 추가한 뒤 앱을 워크스페이스에 설치합니다.",
                        "설치 후 Bot User OAuth Token 값을 여기에 입력하면 채널 목록을 불러올 수 있습니다."
                    ],
                    buttons: [
                        GuideButton(title: "Slack 앱 관리 열기", url: "https://api.slack.com/apps"),
                        GuideButton(title: "chat:write 권한 보기", url: "https://api.slack.com/scopes/chat%3Awrite")
                    ],
                    runner: runner
                )

                HStack {
                    Button(isLoadingSlackChannels ? "불러오는 중..." : "채널 목록 불러오기") {
                        isLoadingSlackChannels = true
                        Task {
                            slackChannels = await runner.loadSlackChannels(settings: settings)
                            isLoadingSlackChannels = false
                        }
                    }
                    .disabled(runner.isRunning || settings.slackBotToken.isEmpty || isLoadingSlackChannels)

                    if isLoadingSlackChannels {
                        ProgressView()
                            .controlSize(.small)
                        Text("Slack에서 채널을 확인하는 중")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Slack App 권한: chat:write, channels:read, groups:read")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                if slackChannels.isEmpty {
                    ChannelIdField(title: "기본", text: $settings.slackDefaultChannelID)
                    ChannelIdField(title: "연결 테스트", text: $settings.slackTestChannelID)
                    ChannelIdField(title: "출근 브리핑", text: $settings.slackMorningChannelID)
                    ChannelIdField(title: "퇴근 체크", text: $settings.slackEveningChannelID)
                    ChannelIdField(title: "Jira 아침 브리핑", text: $settings.slackJiraChannelID)
                    ChannelIdField(title: "Git 오늘 한 일 보고", text: $settings.slackGitReportChannelID)
                    ChannelIdField(title: "Git 상태 점검", text: $settings.slackGitStatusChannelID)
                    ChannelIdField(title: "긴급 알림", text: $settings.slackAlertsChannelID)
                } else {
                    ChannelPicker(title: "기본", channels: slackChannels, selection: $settings.slackDefaultChannelID)
                    ChannelPicker(title: "연결 테스트", channels: slackChannels, selection: $settings.slackTestChannelID)
                    ChannelPicker(title: "출근 브리핑", channels: slackChannels, selection: $settings.slackMorningChannelID)
                    ChannelPicker(title: "퇴근 체크", channels: slackChannels, selection: $settings.slackEveningChannelID)
                    ChannelPicker(title: "Jira 아침 브리핑", channels: slackChannels, selection: $settings.slackJiraChannelID)
                    ChannelPicker(title: "Git 오늘 한 일 보고", channels: slackChannels, selection: $settings.slackGitReportChannelID)
                    ChannelPicker(title: "Git 상태 점검", channels: slackChannels, selection: $settings.slackGitStatusChannelID)
                    ChannelPicker(title: "긴급 알림", channels: slackChannels, selection: $settings.slackAlertsChannelID)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var jiraSection: some View {
        SettingsSection(
            title: "Jira 연결",
            summary: "내게 할당된 일감과 프로젝트 기본값을 읽기 위한 정보를 입력합니다.",
            systemImage: "checklist",
            isExpanded: $isJiraExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsTextField(title: "기본 URL", placeholder: "https://start-today.atlassian.net", text: $settings.jiraBaseURL)
                SettingsTextField(title: "이메일", placeholder: "you@example.com", text: $settings.jiraEmail)
                SettingsSecureField(title: "API Token", placeholder: "Jira API 토큰", text: $settings.jiraApiToken)
                SettingsTextField(title: "기본 프로젝트", placeholder: "LMS", text: $settings.jiraDefaultProject)

                GuideBox(
                    title: "Jira API 토큰 안내",
                    lines: [
                        "Jira Cloud는 계정 이메일과 API 토큰으로 REST API를 호출합니다.",
                        "토큰을 만든 뒤 API Token 입력칸에 붙여넣고, 기본 프로젝트에는 LMS 같은 프로젝트 키를 입력합니다.",
                        "토큰은 다시 볼 수 없으니 저장 후 분실하면 새로 만들어야 합니다."
                    ],
                    buttons: [
                        GuideButton(title: "Atlassian 토큰 만들기", url: "https://id.atlassian.com/manage-profile/security/api-tokens"),
                        GuideButton(title: "공식 안내 보기", url: "https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/")
                    ],
                    runner: runner
                )
            }
            .padding(.vertical, 6)
        }
    }

    private var developerSection: some View {
        SettingsSection(
            title: "개발자 비서 확장",
            summary: "gh CLI로 GitHub repository를 가져오고 AI 보고서 옵션을 설정합니다.",
            systemImage: "terminal",
            isExpanded: $isDeveloperExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsTextField(title: "Git 작성자", placeholder: "git user.name 또는 email", text: $settings.gitAuthor)
                SettingsTextField(title: "퇴근 기준 시간", placeholder: "18:00", text: $settings.workEndTime)
                SettingsSecureField(title: "OpenAI API Key", placeholder: "Git 보고서 AI 요약 사용 시 입력", text: $settings.openAIKey)
                idePicker

                Text("GitHub CLI 로그인 상태로 접근 가능한 repository 후보를 조회하고, 선택한 repository를 내려받아 관리 대상으로 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GuideBox(
                    title: "GitHub CLI 연결 안내",
                    lines: [
                        "GitHub CLI 로그인을 한 번 진행하면 PAS가 같은 로그인 상태로 repository 후보를 조회합니다.",
                        "조직 repository가 보이지 않으면 GitHub 조직 SSO 승인이 필요할 수 있습니다.",
                        "선택한 repository는 지정한 clone 위치에 내려받고, 이미 있으면 fetch로 원격 상태만 갱신합니다."
                    ],
                    buttons: [
                        GuideButton(title: "GitHub CLI 설치 안내", url: "https://cli.github.com/"),
                        GuideButton(title: "gh auth login 안내", url: "https://cli.github.com/manual/gh_auth_login")
                    ],
                    runner: runner
                )

                githubAuthControls

                remoteRepositorySection

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(isLoadingLocalRepositories ? "불러오는 중..." : "관리 repository 새로고침") {
                            isLoadingLocalRepositories = true
                            Task {
                                localRepositories = await runner.loadLocalRepositories(settings: settings)
                                isLoadingLocalRepositories = false
                            }
                        }
                        .disabled(runner.isRunning || isLoadingLocalRepositories)

                        if isLoadingLocalRepositories {
                            ProgressView()
                                .controlSize(.small)
                            Text("등록된 Git repository 상태를 확인하는 중")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("관리 repository \(settings.repoProjectPaths.count)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    if localRepositories.isEmpty {
                        Text("아직 관리 repository가 없습니다. 위에서 GitHub 후보를 조회한 뒤 선택 repo를 가져오면 여기에 표시됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LocalRepositoryProjectPicker(
                            repositories: localRepositories,
                            selectedPaths: $settings.repoProjectPaths,
                            baseBranches: $settings.repoProjectBaseBranches
                        )
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.vertical, 6)
        }
    }

    private var remoteRepositorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GitHub repository 후보")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Text("gh CLI 로그인 사용")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("owner 또는 org 예: MIMminE, start-today-stl", text: $remoteOwner)
                    .textFieldStyle(.roundedBorder)

                TextField("/Users/you/STL", text: $remoteCloneRoot)
                    .textFieldStyle(.roundedBorder)

                Button("위치 선택") {
                    runner.selectCloneDirectory { path in
                        remoteCloneRoot = path
                        settings.cloneRoot = path
                    }
                }

                Button(isLoadingRemoteRepositories ? "조회 중..." : "후보 불러오기") {
                    Task { await loadRemoteRepositories() }
                }
                .disabled(runner.isRunning || isLoadingRemoteRepositories)
            }

            if isLoadingRemoteRepositories || isCloningRemoteRepositories {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(isCloningRemoteRepositories ? "선택한 repository를 내려받고 동기화하는 중" : "GitHub repository 후보를 조회하는 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if remoteRepositories.isEmpty {
                Text("후보를 불러오면 gh CLI로 접근 가능한 repository 목록이 표시됩니다. 선택한 repository는 clone 위치에 내려받고 관리 대상으로 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RemoteRepositoryPicker(
                    repositories: remoteRepositories,
                    selectedIDs: $selectedRemoteRepositoryIDs
                )

                HStack {
                    Button("선택 repo 가져오기/동기화") {
                        Task { await cloneSelectedRemoteRepositories() }
                    }
                    .disabled(
                        runner.isRunning
                            || isCloningRemoteRepositories
                            || selectedRemoteRepositoryIDs.isEmpty
                            || remoteCloneRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Text("선택 \(selectedRemoteRepositoryIDs.count)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var githubAuthControls: some View {
        HStack(spacing: 8) {
            Button(isCheckingGitHubAuth ? "확인 중..." : "gh 로그인 상태 확인") {
                isCheckingGitHubAuth = true
                Task {
                    _ = await runner.checkGitHubAuthStatus()
                    isCheckingGitHubAuth = false
                }
            }
            .disabled(runner.isRunning || isCheckingGitHubAuth)

            Button("터미널에서 gh 로그인 시작") {
                runner.openGitHubLoginInTerminal()
            }
            .disabled(runner.isRunning)

            if isCheckingGitHubAuth {
                ProgressView()
                    .controlSize(.small)
                Text("gh auth status 실행 중")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("로그인 후 후보 불러오기를 누르면 접근 가능한 repository가 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var idePicker: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("기본 IDE")
                    .frame(width: 128, alignment: .leading)

                HStack(spacing: 8) {
                    Picker("기본 IDE", selection: $settings.defaultIDEAppName) {
                        Text("macOS 기본 앱").tag("")
                        if !settings.defaultIDEAppName.isEmpty && !ideApps.contains(where: { $0.name == settings.defaultIDEAppName }) {
                            Text(settings.defaultIDEAppName).tag(settings.defaultIDEAppName)
                        }
                        ForEach(ideApps) { app in
                            Text(app.name).tag(app.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)

                    Button("IDE 후보 새로고침") {
                        ideApps = runner.detectedIDEApps()
                    }

                    if ideApps.isEmpty {
                        Text("감지된 IDE가 없으면 macOS 기본 앱으로 열립니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(ideApps.count)개 감지")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
        }
        .task {
            if ideApps.isEmpty {
                ideApps = runner.detectedIDEApps()
            }
        }
    }

    private var testSection: some View {
        SettingsSection(
            title: "연결 확인",
            summary: "저장한 설정으로 Slack, Jira, 스케줄 상태를 바로 확인합니다.",
            systemImage: "stethoscope",
            isExpanded: $isTestExpanded
        ) {
            HStack(spacing: 10) {
                Button("Slack 테스트 전송") {
                    runner.saveSettings(settings)
                    runner.run(["slack", "test"])
                }
                .disabled(runner.isRunning || !settings.isReadyForSlackTest)

                Menu("채널별 테스트") {
                    Button("연결 테스트 채널") { runSlackTest("test") }
                    Button("Jira 브리핑 채널") { runSlackTest("jira_daily") }
                    Button("Git 보고 채널") { runSlackTest("git_report") }
                    Button("Git 상태 채널") { runSlackTest("git_status") }
                    Button("긴급 알림 채널") { runSlackTest("alerts") }
                }
                .disabled(runner.isRunning)

                Button("Jira 미리보기") {
                    runner.saveSettings(settings)
                    runner.run(["jira", "today", "--dry-run"])
                }
                .disabled(runner.isRunning || !settings.isReadyForBasicTests)

                Button("설정 진단") {
                    runner.saveSettings(settings)
                    runner.run(["status", "doctor"])
                }
                .disabled(runner.isRunning)

                Button("스케줄 상태") {
                    runner.saveSettings(settings)
                    runner.run(["schedule", "status"])
                }
                .disabled(runner.isRunning)

                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private var automationSection: some View {
        SettingsSection(
            title: "자동 실행",
            summary: "기능별 실행 여부와 하루 한 번 실행할 시간을 정합니다.",
            systemImage: "clock.arrow.circlepath",
            isExpanded: $isAutomationExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("기능을 끄면 수동 실행과 자동 실행 대상에서 제외됩니다. 스케줄 등록은 기존 항목을 지우고 현재 설정으로 다시 등록합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScheduleRow(
                    title: "Jira 아침 브리핑",
                    featureEnabled: $settings.jiraDailyEnabled,
                    scheduleEnabled: $settings.jiraDailyScheduleEnabled,
                    time: $settings.jiraDailyScheduleTime,
                    catchUp: $settings.jiraDailyCatchUp,
                    placeholder: "09:00"
                )

                ScheduleRow(
                    title: "Git 오늘 한 일 보고",
                    featureEnabled: $settings.gitReportEnabled,
                    scheduleEnabled: $settings.gitReportScheduleEnabled,
                    time: $settings.gitReportScheduleTime,
                    catchUp: $settings.gitReportCatchUp,
                    placeholder: "18:30"
                )

                ScheduleRow(
                    title: "Git 상태 점검",
                    featureEnabled: $settings.gitStatusEnabled,
                    scheduleEnabled: $settings.gitStatusScheduleEnabled,
                    time: $settings.gitStatusScheduleTime,
                    catchUp: $settings.gitStatusCatchUp,
                    placeholder: "09:10"
                )

                HStack {
                    Button("스케줄러 등록/갱신") {
                        runner.saveSettings(settings)
                        runner.run(["schedule", "install"])
                    }
                    .disabled(runner.isRunning)

                    Button("스케줄러 제거") {
                        runner.run(["schedule", "uninstall"])
                    }
                    .disabled(runner.isRunning)

                    Button("자동 실행 테스트") {
                        runner.saveSettings(settings)
                        runner.run(["automation", "tick", "--dry-run"])
                    }
                    .disabled(runner.isRunning)

                    Spacer()
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var footer: some View {
        HStack {
            Button("설정 폴더 열기") {
                runner.openSupportDirectory()
            }

            Spacer()

            Button("저장") {
                runner.saveSettings(settings)
            }
            .keyboardShortcut(.defaultAction)

            Button("저장 후 닫기") {
                runner.saveSettings(settings)
                runner.closeSetupWindow()
            }
            .disabled(!settings.isReadyForBasicTests)
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func loadRemoteRepositories() async {
        isLoadingRemoteRepositories = true
        settings.cloneRoot = remoteCloneRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        remoteRepositories = await runner.loadRemoteRepositories(owner: remoteOwner)
        selectedRemoteRepositoryIDs.removeAll()
        isLoadingRemoteRepositories = false
    }

    private func cloneSelectedRemoteRepositories() async {
        let targetRoot = remoteCloneRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetRoot.isEmpty else { return }
        let selected = remoteRepositories.filter { selectedRemoteRepositoryIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        isCloningRemoteRepositories = true
        settings.cloneRoot = targetRoot
        for repo in selected {
            let result = await runner.cloneRemoteRepository(repo, targetRoot: targetRoot)
            if result.succeeded {
                let localPath = parseClonedPath(result.displayText)
                if !localPath.isEmpty {
                    settings.repoProjectPaths.insert(localPath)
                    settings.repoProjectBaseBranches[localPath] = repo.defaultBranch
                }
            }
        }
        runner.saveSettings(settings)
        localRepositories = await runner.loadLocalRepositories(settings: settings)
        selectedRemoteRepositoryIDs.removeAll()
        isCloningRemoteRepositories = false
    }

    private func parseClonedPath(_ output: String) -> String {
        output.split(separator: "\n").first?.split(separator: "\t").first.map(String.init) ?? ""
    }

    private func runSlackTest(_ destination: String) {
        runner.saveSettings(settings)
        runner.run(["slack", "test", "--destination", destination])
    }
}
