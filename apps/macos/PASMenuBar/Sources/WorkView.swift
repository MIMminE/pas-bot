import SwiftUI
import UniformTypeIdentifiers

struct WorkView: View {
    @ObservedObject var runner: PASRunner

    @AppStorage("pas.work.appearance") private var appearance = "system"
    @AppStorage("pas.work.commandCenterExpanded") private var isCommandCenterExpanded = true
    @AppStorage("pas.work.repositoryOrder") private var repositoryOrderRaw = ""
    @AppStorage("pas.work.sidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("pas.work.selectedSection") private var selectedSection = "workspace"

    @State private var repositories: [LocalRepositoryOption] = []
    @State private var isLoading = false
    @State private var selectedPath = ""
    @State private var lastMessage = ""
    @State private var reportDraft = ""
    @State private var reportNotes = ""
    @State private var filter = "all"
    @State private var pendingAction: RepoAction?
    @State private var showDirtyWarning = false
    @State private var notice: WorkNotice?
    @State private var branchOptionsByPath: [String: [BranchOption]] = [:]
    @State private var draggingRepositoryPath: String?
    @State private var workCommitPreviewRows = 4

    private var filteredRepositories: [LocalRepositoryOption] {
        let ordered = orderedRepositories(repositories)
        switch filter {
        case "needsUpdate":
            return ordered.filter { $0.needsUpdate }
        default:
            return ordered
        }
    }

    private var repositoryOrder: [String] {
        repositoryOrderRaw
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.08),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                WorkSidebarView(
                    selectedSection: $selectedSection,
                    isCollapsed: $isSidebarCollapsed,
                    activeProfileID: runner.activeProfileID,
                    profiles: runner.availableProfiles,
                    repositoryCount: repositories.count,
                    reportReady: !reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onProfileChange: { profileID in
                        runner.switchProfile(to: profileID)
                    }
                )

                Divider()

                VStack(spacing: 0) {
                    compactToolbar

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            selectedSectionContent
                        }
                        .padding(20)
                    }
                }
            }
        }
        .preferredColorScheme(preferredScheme)
        .frame(minWidth: 980, minHeight: 760)
        .task {
            await reload()
            await autoRefreshLoop()
        }
        .task {
            await jiraIssueWatchLoop()
        }
        .onChange(of: runner.activeProfileID) { _ in
            reportDraft = ""
            reportNotes = ""
            branchOptionsByPath = [:]
            Task { await reload(notify: true) }
        }
        .sheet(item: $notice) { notice in
            WorkNoticeView(notice: notice)
        }
        .alert("변경 파일이 있습니다", isPresented: $showDirtyWarning, presenting: pendingAction) { _ in
            Button("확인", role: .cancel) {}
        } message: { action in
            Text("\(action.repo.name)에 커밋하지 않은 변경 파일이 있습니다. 업데이트나 rebase 전에 commit 또는 stash를 먼저 처리해 주세요.")
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 8) {
            Spacer()

            Picker("화면", selection: $appearance) {
                Image(systemName: "circle.lefthalf.filled").tag("system")
                Image(systemName: "sun.max").tag("light")
                Image(systemName: "moon").tag("dark")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 112)
            .help("화면 모드")

            Button {
                runner.openSetupWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .help("설정 열기")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case "report":
            reportSection
        case "tools":
            commandCenter
        default:
            VStack(alignment: .leading, spacing: 16) {
                repositoryActions
                repositorySection
            }
        }
    }

    private var commandCenter: some View {
        CollapsibleDashboardPanel(
            title: "업무 실행 보드",
            systemImage: "rectangle.grid.2x2",
            isExpanded: $isCommandCenterExpanded
        ) {
            if runner.isPersonalProfile {
                HStack(alignment: .top, spacing: 12) {
                    personalToolActions
                        .frame(maxWidth: .infinity)
                    aiSection
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    briefingActions
                        .frame(maxWidth: .infinity)
                    toolActions
                        .frame(maxWidth: .infinity)
                    aiSection
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var briefingActions: some View {
        CommandGroup(title: "브리핑", subtitle: "Slack 공유와 미리보기", systemImage: "megaphone") {
            VStack(spacing: 8) {
                DashboardButton(title: "출근 브리핑 공유", systemImage: "sun.max") {
                    Task {
                        await runDashboardCommand(
                            ["routine", "morning", "--send-slack"],
                            title: "출근 브리핑 공유",
                            running: "출근 브리핑을 Slack으로 공유하는 중...",
                            success: "출근 브리핑을 Slack으로 공유했습니다",
                            failure: "출근 브리핑 공유 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "출근 브리핑 미리보기", systemImage: "doc.text") {
                    Task {
                        await runDashboardCommand(
                            ["routine", "morning", "--dry-run"],
                            title: "출근 브리핑 미리보기",
                            running: "출근 브리핑 미리보기를 만드는 중...",
                            success: "출근 브리핑 미리보기 완료",
                            failure: "출근 브리핑 미리보기 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "Jira 브리핑 공유", systemImage: "checklist") {
                    Task {
                        await runDashboardCommand(
                            ["jira", "today", "--send-slack"],
                            title: "Jira 브리핑 공유",
                            running: "Jira 브리핑을 Slack으로 공유하는 중...",
                            success: "Jira 브리핑을 Slack으로 공유했습니다",
                            failure: "Jira 브리핑 공유 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "Jira 브리핑 미리보기", systemImage: "doc.text") {
                    Task {
                        await runDashboardCommand(
                            ["jira", "today", "--dry-run"],
                            title: "Jira 브리핑 미리보기",
                            running: "Jira 브리핑 미리보기를 만드는 중...",
                            success: "Jira 브리핑 미리보기 완료",
                            failure: "Jira 브리핑 미리보기 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "새 Jira 일감 확인", systemImage: "bell.badge") {
                    Task { await checkNewJiraIssues(showEmptyResult: true) }
                }
                .disabled(runner.isRunning)

            }
        }
    }

    private var repositoryActions: some View {
        DashboardPanel(title: "저장소 정비", systemImage: "arrow.triangle.2.circlepath") {
            HStack(spacing: 10) {
                DashboardButton(title: isLoading ? "확인 중" : "상태 동기화", systemImage: "arrow.clockwise") {
                    Task { await reload(notify: true, fetchRemote: true) }
                }
                .disabled(isLoading || runner.isRunning)

                if !runner.isPersonalProfile {
                    DashboardButton(title: "상태 공유", systemImage: "paperplane") {
                        Task {
                            await runDashboardCommand(
                                ["repo", "status", "--send-slack"],
                                title: "저장소 상태 공유",
                                running: "저장소 상태를 Slack으로 공유하는 중...",
                                success: "저장소 상태를 Slack으로 공유했습니다",
                                failure: "저장소 상태 공유 실패"
                            )
                        }
                    }
                    .disabled(runner.isRunning)

                    DashboardButton(title: "출근 정비 실행", systemImage: "sparkles") {
                        Task {
                            await runDashboardCommand(
                                ["repo", "morning-sync", "--send-slack"],
                                title: "출근 정비 실행",
                                running: "출근 저장소 정비를 실행하는 중...",
                                success: "출근 저장소 정비 완료",
                                failure: "출근 정비 실행 실패"
                            )
                        }
                    }
                    .disabled(runner.isRunning)
                }

                Spacer()
            }
        }
    }

    private var personalToolActions: some View {
        CommandGroup(title: "개인 프로젝트", subtitle: "Git 중심 점검", systemImage: "person.crop.circle") {
            VStack(spacing: 8) {
                DashboardButton(title: "오늘 흐름", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                    Task { await showTodayActivity() }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "PR 상태", systemImage: "arrow.triangle.pull") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "pr-status"],
                            title: "PR 상태",
                            running: "열린 PR 상태를 확인하는 중...",
                            success: "PR 상태 확인 완료",
                            failure: "PR 상태 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "CI 실패", systemImage: "xmark.seal") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "ci-alerts"],
                            title: "CI 실패",
                            running: "최근 CI 실패를 확인하는 중...",
                            success: "CI 실패 확인 완료",
                            failure: "CI 실패 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)
            }
        }
    }

    private var toolActions: some View {
        CommandGroup(title: "루틴", subtitle: "점검과 연결 확인", systemImage: "checklist.checked") {
            VStack(spacing: 8) {
                DashboardButton(title: "퇴근 전 점검", systemImage: "checkmark.seal") {
                    Task {
                        await runDashboardCommand(
                            ["routine", "evening", "--dry-run"],
                            title: "퇴근 전 점검",
                            running: "퇴근 전 점검을 만드는 중...",
                            success: "퇴근 전 점검 미리보기 완료",
                            failure: "퇴근 전 점검 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "Jira 키 점검", systemImage: "number.square") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "audit-jira-keys"],
                            title: "Jira 키 점검",
                            running: "Jira 키 누락을 검사하는 중...",
                            success: "Jira 키 점검 완료",
                            failure: "Jira 키 점검 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "연결 목록", systemImage: "link") {
                    Task {
                        let output = await runner.loadIssueRepositoryLinks()
                        lastMessage = output
                        showNotice(title: "일감-저장소 연결", message: output, succeeded: !runner.status.contains("실패"))
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "오늘 흐름", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                    Task { await showTodayActivity() }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "PR 상태", systemImage: "arrow.triangle.pull") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "pr-status"],
                            title: "PR 상태",
                            running: "열린 PR 상태를 확인하는 중...",
                            success: "PR 상태 확인 완료",
                            failure: "PR 상태 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "리뷰 요청", systemImage: "person.2.badge.gearshape") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "review-alerts"],
                            title: "리뷰 요청",
                            running: "리뷰 요청 PR을 확인하는 중...",
                            success: "리뷰 요청 확인 완료",
                            failure: "리뷰 요청 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "CI 실패", systemImage: "xmark.seal") {
                    Task {
                        await runDashboardCommand(
                            ["dev", "ci-alerts"],
                            title: "CI 실패",
                            running: "최근 CI 실패를 확인하는 중...",
                            success: "CI 실패 확인 완료",
                            failure: "CI 실패 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "배포 대기", systemImage: "shippingbox") {
                    Task {
                        await runDashboardCommand(
                            ["jira", "deploy-waiting"],
                            title: "배포 대기 Jira",
                            running: "배포 대기 Jira 일감을 확인하는 중...",
                            success: "배포 대기 Jira 확인 완료",
                            failure: "배포 대기 Jira 확인 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)
            }
        }
    }

    private var repositorySection: some View {
        DashboardPanel(title: "관리 저장소", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("필터", selection: $filter) {
                        Text("전체").tag("all")
                        Text("정비 필요").tag("needsUpdate")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("상태를 확인하는 중")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(filteredRepositories.count)개 표시")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if repositories.isEmpty {
                    EmptyDashboardState(
                        systemImage: "folder.badge.questionmark",
                        title: "관리 대상 저장소가 없습니다",
                        message: "설정에서 GitHub 후보를 불러온 뒤 관리할 저장소를 가져와 주세요."
                    )
                } else if filteredRepositories.isEmpty {
                    EmptyDashboardState(
                        systemImage: "line.3.horizontal.decrease.circle",
                        title: "현재 필터에 해당하는 저장소가 없습니다",
                        message: "다른 필터를 선택하거나 상태를 새로고침해 주세요."
                    )
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12, alignment: .top),
                            GridItem(.flexible(), spacing: 12, alignment: .top),
                        ],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(filteredRepositories) { repo in
                            RepositoryDashboardRow(
                                repo: repo,
                                branches: branchOptionsByPath[repo.path] ?? [],
                                isSelected: selectedPath == repo.path,
                                isRunning: runner.isRunning,
                                onSelect: {
                                    selectedPath = repo.path
                                },
                                onCheckout: { branch in
                                    Task { await checkout(repo, branch: branch) }
                                },
                                onOpenIDE: {
                                    openIDE(repo)
                                },
                                visibleCommitRows: workCommitPreviewRows
                            )
                            .opacity(draggingRepositoryPath == repo.path ? 0.58 : 1)
                            .onDrag {
                                draggingRepositoryPath = repo.path
                                return NSItemProvider(object: repo.path as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: RepositoryDropDelegate(
                                    targetPath: repo.path,
                                    draggingPath: $draggingRepositoryPath,
                                    move: moveRepository
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private var reportSection: some View {
        DashboardPanel(title: "오늘 한 일 초안", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DashboardButton(title: "초안 만들기", systemImage: "doc.badge.gearshape") {
                        Task {
                            reportDraft = await runner.previewDailyReport(notes: reportNotes)
                            lastMessage = reportDraft
                            showNotice(title: "오늘 한 일 초안", message: reportDraft, succeeded: !reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .disabled(runner.isRunning)

                    DashboardButton(title: "ChatGPT 전달용", systemImage: "bubble.left.and.text.bubble.right") {
                        reportDraft = runner.makeChatGPTReportPrompt(draft: reportDraft, notes: reportNotes)
                        lastMessage = reportDraft
                        showNotice(title: "ChatGPT 전달용 프롬프트", message: reportDraft, succeeded: true)
                    }
                    .disabled(runner.isRunning)

                    DashboardButton(title: "보고 규칙", systemImage: "doc.plaintext") {
                        runner.openReportAgentEditor()
                    }
                    .disabled(runner.isRunning)

                    if !runner.isPersonalProfile {
                        DashboardButton(title: "보고서 공유", systemImage: "paperplane.fill") {
                            Task {
                                lastMessage = await runner.sendEditedReport(reportDraft)
                                showNotice(title: "보고서 공유", message: lastMessage, succeeded: !runner.status.contains("실패"))
                            }
                        }
                        .disabled(runner.isRunning || reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Spacer()
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("수동 메모")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $reportNotes)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 130)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.65))
                            )
                    }
                    .frame(maxWidth: 340)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("보고서 초안")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $reportDraft)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 130)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.86))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.8))
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var aiSection: some View {
        CommandGroup(title: "AI 작성", subtitle: "요약과 초안 생성", systemImage: "brain.head.profile") {
            VStack(spacing: 8) {
                DashboardButton(title: "업무 요약", systemImage: "text.badge.checkmark") {
                    Task {
                        await runDashboardCommand(
                            ["ai", "git-summary", "--tone", "brief"],
                            title: "업무 요약",
                            running: "업무 요약을 만드는 중...",
                            success: "업무 요약 완료",
                            failure: "업무 요약 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "보고용 요약", systemImage: "person.text.rectangle") {
                    Task {
                        await runDashboardCommand(
                            ["ai", "git-summary", "--tone", "manager"],
                            title: "보고용 요약",
                            running: "보고용 요약을 만드는 중...",
                            success: "보고용 요약 완료",
                            failure: "보고용 요약 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "PR 작성안", systemImage: "arrow.triangle.pull") {
                    var args = ["ai", "pr-draft", "--tone", "brief"]
                    if !selectedPath.isEmpty {
                        args.append(contentsOf: ["--repo", selectedPath])
                    }
                    Task {
                        await runDashboardCommand(
                            args,
                            title: "PR 작성안",
                            running: "PR 작성안을 만드는 중...",
                            success: "PR 작성안 생성 완료",
                            failure: "PR 작성안 생성 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "장애 정리안", systemImage: "stethoscope") {
                    Task {
                        await runDashboardCommand(
                            ["ai", "incident-draft", "--tone", "detailed"],
                            title: "장애 정리안",
                            running: "장애 정리안을 만드는 중...",
                            success: "장애 정리안 생성 완료",
                            failure: "장애 정리안 생성 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)
            }
        }
    }

    private func reload(notify: Bool = false, fetchRemote: Bool = false) async {
        isLoading = true
        workCommitPreviewRows = runner.loadSettings().workCommitPreviewRowsOrDefault
        if fetchRemote {
            repositories = orderedRepositories(await runner.refreshManagedRepositories(fetchRemote: true))
        } else {
            repositories = orderedRepositories(await runner.loadManagedRepositories())
        }
        syncRepositoryOrder()
        await loadBranchOptions()
        isLoading = false
        if notify {
            showNotice(title: "상태 새로고침", message: "관리 중인 저장소 \(repositories.count)개의 상태를 다시 불러왔습니다.", succeeded: true)
        }
    }

    private func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
            if Task.isCancelled {
                return
            }
            guard !runner.isSetupOpen, !runner.isRunning, !isLoading else {
                continue
            }
            await reload(fetchRemote: true)
        }
    }

    private func jiraIssueWatchLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            if Task.isCancelled {
                return
            }
            guard !runner.isSetupOpen, !runner.isPersonalProfile, !runner.isRunning else {
                continue
            }
            await checkNewJiraIssues(showEmptyResult: false)
        }
    }

    private func showTodayCommits(_ repo: LocalRepositoryOption) async {
        selectedPath = repo.path
        lastMessage = await runner.loadTodayCommits(path: repo.path)
        showNotice(title: "\(repo.name) 오늘 커밋", message: lastMessage, succeeded: !runner.status.contains("실패"))
    }

    private func loadBranchOptions() async {
        var options: [String: [BranchOption]] = [:]
        for repo in repositories {
            options[repo.path] = await runner.loadRepositoryBranches(path: repo.path)
        }
        branchOptionsByPath = options
    }

    private func orderedRepositories(_ values: [LocalRepositoryOption]) -> [LocalRepositoryOption] {
        let indexByPath = Dictionary(uniqueKeysWithValues: repositoryOrder.enumerated().map { ($0.element, $0.offset) })
        return values.sorted {
            let left = indexByPath[$0.path] ?? Int.max
            let right = indexByPath[$1.path] ?? Int.max
            if left != right {
                return left < right
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func syncRepositoryOrder() {
        var paths = repositoryOrder.filter { path in repositories.contains(where: { $0.path == path }) }
        for repo in repositories where !paths.contains(repo.path) {
            paths.append(repo.path)
        }
        repositoryOrderRaw = paths.joined(separator: "\n")
    }

    private func moveRepository(draggingPath: String, targetPath: String) {
        var paths = repositoryOrder
        if paths.isEmpty {
            paths = orderedRepositories(repositories).map(\.path)
        }
        guard
            let sourceIndex = paths.firstIndex(of: draggingPath),
            let targetIndex = paths.firstIndex(of: targetPath),
            sourceIndex != targetIndex
        else {
            return
        }

        let sourcePath = paths.remove(at: sourceIndex)
        paths.insert(sourcePath, at: targetIndex)
        repositoryOrderRaw = paths.joined(separator: "\n")
        repositories = orderedRepositories(repositories)
    }

    private func checkout(_ repo: LocalRepositoryOption, branch: String) async {
        selectedPath = repo.path
        let result = await runner.checkoutRepositoryBranch(path: repo.path, branch: branch)
        showNotice(title: "\(repo.name) 브랜치 변경", message: result.displayText, succeeded: result.succeeded)
        await reload()
    }

    private func openIDE(_ repo: LocalRepositoryOption) {
        selectedPath = repo.path
        let appName = runner.loadSettings().defaultIDEAppName
        runner.openRepositoryInIDE(path: repo.path, appName: appName)
    }

    private func showTodayActivity() async {
        lastMessage = await runner.loadTodayActivity()
        showNotice(title: "오늘 흐름", message: lastMessage, succeeded: !runner.status.contains("실패"))
    }

    private func checkNewJiraIssues(showEmptyResult: Bool) async {
        let result = await runner.checkNewJiraIssues()
        lastMessage = result.displayText
        let hasNewIssues = result.displayText.hasPrefix("새로 등록된 Jira 일감")
        if showEmptyResult || hasNewIssues || !result.succeeded {
            showNotice(title: "새 Jira 일감", message: result.displayText, succeeded: result.succeeded)
        }
    }

    private func run(_ repo: LocalRepositoryOption, mode: String, skipWarning: Bool = false) async {
        if !skipWarning && repo.dirtyCount > 0 && (mode == "pull" || mode == "rebase") {
            pendingAction = RepoAction(repo: repo, mode: mode)
            showDirtyWarning = true
            return
        }
        selectedPath = repo.path
        lastMessage = await runner.runRepositoryUpdate(path: repo.path, mode: mode)
        showNotice(title: "\(repo.name) \(mode)", message: lastMessage, succeeded: !runner.status.contains("실패"))
        await reload()
    }

    private func runDashboardCommand(
        _ arguments: [String],
        title: String,
        running: String,
        success: String,
        failure: String
    ) async {
        let result = await runner.runDashboardCommand(arguments, runningStatus: running, successStatus: success, failureStatus: failure)
        lastMessage = result.displayText
        showNotice(title: title, message: result.displayText, succeeded: result.succeeded)
    }

    private func showNotice(title: String, message: String, succeeded: Bool) {
        notice = WorkNotice(title: title, message: message, succeeded: succeeded)
    }
}

private struct RepositoryDropDelegate: DropDelegate {
    let targetPath: String
    @Binding var draggingPath: String?
    let move: (_ draggingPath: String, _ targetPath: String) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingPath, draggingPath != targetPath else {
            return
        }
        move(draggingPath, targetPath)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingPath = nil
        return true
    }
}
