import SwiftUI

struct SetupView: View {
    @ObservedObject var runner: PASRunner

    @State private var settings: PASSettings
    @State private var slackChannels: [SlackChannel] = []
    @State private var localRepositories: [LocalRepositoryOption] = []
    @State private var remoteRepositories: [GitHubRemoteRepositoryOption] = []
    @State private var selectedRemoteRepositoryIDs: Set<String> = []
    @State private var remoteOwner = ""
    @State private var remoteCloneRoot = ""
    @State private var isLoadingSlackChannels = false
    @State private var isLoadingLocalRepositories = false
    @State private var isLoadingRemoteRepositories = false
    @State private var isCloningRemoteRepositories = false

    init(runner: PASRunner) {
        self.runner = runner
        _settings = State(initialValue: runner.loadSettings())
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
        GroupBox("Slack 목적지") {
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
        GroupBox("Jira") {
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
        GroupBox("개발자 비서 확장") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsTextField(title: "Git 작성자", placeholder: "git user.name 또는 email", text: $settings.gitAuthor)
                SettingsTextField(title: "퇴근 기준 시간", placeholder: "18:00", text: $settings.workEndTime)
                SettingsSecureField(title: "OpenAI API Key", placeholder: "Git 보고서 AI 요약 사용 시 입력", text: $settings.openAIKey)

                Text("로컬에 clone 또는 pull 되어 있는 Git repository를 기준으로 상태 점검과 작업 보고를 만듭니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GuideBox(
                    title: "로컬 Git repository 안내",
                    lines: [
                        "회사 조직 토큰 없이도 로컬에 받아둔 repository의 브랜치, 커밋, 변경 상태를 확인합니다.",
                        "STL 같은 상위 폴더를 root로 지정하고 하위 폴더 탐색을 켜면 여러 repository를 한 번에 찾습니다.",
                        "원격 최신 상태를 보려면 각 repository의 기존 git 인증으로 fetch/pull이 가능한 상태면 충분합니다."
                    ],
                    buttons: [
                        GuideButton(title: "Git 문서 보기", url: "https://git-scm.com/doc")
                    ],
                    runner: runner
                )

                HStack {
                    Button("repository root 폴더 추가") {
                        runner.selectRepositoryRoot { path in
                            if !settings.repoRoots.contains(where: { $0.path == path }) {
                                settings.repoRoots.append(LocalRepositoryRoot(path: path, recursive: true))
                            }
                        }
                    }

                    Button("빈 항목 추가") {
                        settings.repoRoots.append(LocalRepositoryRoot(path: "", recursive: true))
                    }

                    Text("등록한 root \(settings.repoRoots.filter { !$0.path.isEmpty }.count)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                if settings.repoRoots.isEmpty {
                    Text("아직 등록한 repository root가 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LocalRepositoryRootEditor(roots: $settings.repoRoots, runner: runner)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(isLoadingLocalRepositories ? "불러오는 중..." : "Git 프로젝트 목록 불러오기") {
                            isLoadingLocalRepositories = true
                            Task {
                                localRepositories = await runner.loadLocalRepositories(settings: settings)
                                if settings.repoProjectPaths.isEmpty {
                                    settings.repoProjectPaths = Set(localRepositories.map(\.path))
                                }
                                isLoadingLocalRepositories = false
                            }
                        }
                        .disabled(runner.isRunning || settings.repoRoots.isEmpty || isLoadingLocalRepositories)

                        if isLoadingLocalRepositories {
                            ProgressView()
                                .controlSize(.small)
                            Text("root 하위 Git 프로젝트를 확인하는 중")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("선택한 프로젝트 \(settings.repoProjectPaths.count)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    if localRepositories.isEmpty {
                        Text("목록을 불러오면 관리할 프로젝트를 선택할 수 있습니다. 선택값이 비어 있으면 root 하위 전체를 관리합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LocalRepositoryProjectPicker(
                            repositories: localRepositories,
                            selectedPaths: $settings.repoProjectPaths
                        )
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                remoteRepositorySection
            }
            .padding(.vertical, 6)
        }
    }

    private var remoteRepositorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GitHub 원격 repository 후보")
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text("gh CLI 로그인 사용")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("로컬에 저장한 토큰 없이 현재 기기의 gh auth 로그인 상태로 접근 가능한 repository를 조회하고, 선택한 root 아래로 clone합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("owner 또는 org 예: MIMminE, start-today-stl", text: $remoteOwner)
                    .textFieldStyle(.roundedBorder)

                Picker("clone 위치", selection: $remoteCloneRoot) {
                    Text("root 선택").tag("")
                    ForEach(settings.repoRoots.filter { !$0.path.isEmpty }) { root in
                        Text(root.path).tag(root.path)
                    }
                }
                .frame(width: 260)

                Button(isLoadingRemoteRepositories ? "조회 중..." : "원격 후보 불러오기") {
                    Task { await loadRemoteRepositories() }
                }
                .disabled(runner.isRunning || isLoadingRemoteRepositories)
            }

            if isLoadingRemoteRepositories || isCloningRemoteRepositories {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(isCloningRemoteRepositories ? "선택한 repository를 clone하는 중" : "GitHub repository 후보를 조회하는 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if remoteRepositories.isEmpty {
                Text("후보를 불러오면 접근 가능한 repository 목록이 표시됩니다. 조직 repo가 보이지 않으면 GitHub 조직 SSO 승인이 필요할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RemoteRepositoryPicker(
                    repositories: remoteRepositories,
                    selectedIDs: $selectedRemoteRepositoryIDs
                )

                HStack {
                    Button("선택 repo 가져오기") {
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

    private var testSection: some View {
        GroupBox("검증") {
            HStack(spacing: 10) {
                Button("Slack 테스트 전송") {
                    runner.saveSettings(settings)
                    runner.run(["slack", "test"])
                }
                .disabled(runner.isRunning || !settings.isReadyForSlackTest)

                Menu("목적지별 테스트") {
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
        GroupBox("자동 실행") {
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
        if remoteCloneRoot.isEmpty, let firstRoot = settings.repoRoots.first(where: { !$0.path.isEmpty }) {
            remoteCloneRoot = firstRoot.path
        }
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
        for repo in selected {
            let result = await runner.cloneRemoteRepository(repo, targetRoot: targetRoot)
            if result.succeeded {
                let localPath = parseClonedPath(result.displayText)
                if !localPath.isEmpty {
                    settings.repoProjectPaths.insert(localPath)
                }
            }
        }
        localRepositories = await runner.loadLocalRepositories(settings: settings)
        settings.repoProjectPaths.formUnion(localRepositories.map(\.path).filter { path in
            selected.contains { path.hasSuffix("/\($0.shortName)") || path.hasSuffix("\\\($0.shortName)") }
        })
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

private struct SettingsTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct SettingsSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct GuideButton: Hashable {
    let title: String
    let url: String
}

private struct GuideBox: View {
    let title: String
    let lines: [String]
    let buttons: [GuideButton]
    let runner: PASRunner
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {

            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text("- \(line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                ForEach(buttons, id: \.self) { item in
                    Button(item.title) {
                        runner.openExternalURL(item.url)
                    }
                }
                Spacer()
            }
            .padding(.top, 6)
        } label: {
            Text(title)
                .font(.subheadline)
                .bold()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ChannelIdField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        SettingsTextField(
            title: title,
            placeholder: "C0123456789",
            text: $text
        )
    }
}

private struct ChannelPicker: View {
    let title: String
    let channels: [SlackChannel]
    @Binding var selection: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                Picker(title, selection: $selection) {
                    Text("기본 채널 사용").tag("")
                    ForEach(channels) { channel in
                        Text(channel.label).tag(channel.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct LocalRepositoryRootEditor: View {
    @Binding var roots: [LocalRepositoryRoot]
    let runner: PASRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("관리할 로컬 repository root")
                    .font(.subheadline)
                    .bold()

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(roots.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("/Users/you/STL", text: $roots[index].path)
                                .textFieldStyle(.roundedBorder)

                            Button("선택") {
                                runner.selectRepositoryRoot { path in
                                    roots[index].path = path
                                }
                            }

                            Button("삭제") {
                                roots.remove(at: index)
                            }
                        }

                        Toggle("하위 폴더에서 repository 찾기", isOn: $roots[index].recursive)
                            .font(.caption)
                    }
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct LocalRepositoryProjectPicker: View {
    let repositories: [LocalRepositoryOption]
    @Binding var selectedPaths: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("관리할 Git 프로젝트")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Button("전체 선택") {
                    selectedPaths = Set(repositories.map(\.path))
                }

                Button("전체 해제") {
                    selectedPaths.removeAll()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(repositories) { repo in
                    Toggle(isOn: Binding(
                        get: { selectedPaths.contains(repo.path) },
                        set: { isSelected in
                            if isSelected {
                                selectedPaths.insert(repo.path)
                            } else {
                                selectedPaths.remove(repo.path)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(repo.name)
                                    .font(.body)
                                Text(repo.branch)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                if repo.dirtyCount > 0 {
                                    Text("변경 \(repo.dirtyCount)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                            }

                            Text("\(repo.syncLabel) | \(repo.path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

private struct RemoteRepositoryPicker: View {
    let repositories: [GitHubRemoteRepositoryOption]
    @Binding var selectedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("가져올 원격 repository")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Button("전체 선택") {
                    selectedIDs = Set(repositories.map(\.id))
                }

                Button("전체 해제") {
                    selectedIDs.removeAll()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(repositories) { repo in
                        Toggle(isOn: Binding(
                            get: { selectedIDs.contains(repo.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedIDs.insert(repo.id)
                                } else {
                                    selectedIDs.remove(repo.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(repo.nameWithOwner)
                                        .font(.body)
                                    Text(repo.visibility)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(nsColor: .textBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    if !repo.defaultBranch.isEmpty {
                                        Text(repo.defaultBranch)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }

                                Text(repo.sshURL.isEmpty ? repo.webURL : repo.sshURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }
}

private struct ScheduleRow: View {
    let title: String
    @Binding var featureEnabled: Bool
    @Binding var scheduleEnabled: Bool
    @Binding var time: String
    @Binding var catchUp: Bool
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: $featureEnabled)
                .font(.headline)

            HStack(spacing: 12) {
                Toggle("자동 전송", isOn: $scheduleEnabled)
                    .disabled(!featureEnabled)

                TextField(placeholder, text: $time)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)
                    .disabled(!featureEnabled || !scheduleEnabled)

                Toggle("놓친 경우 켜진 시점에 1회 전송", isOn: $catchUp)
                    .disabled(!featureEnabled || !scheduleEnabled)

                Spacer()
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
