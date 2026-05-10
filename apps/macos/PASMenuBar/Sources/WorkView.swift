import SwiftUI

struct WorkView: View {
    @ObservedObject var runner: PASRunner

    @AppStorage("pas.work.appearance") private var appearance = "system"

    @State private var repositories: [LocalRepositoryOption] = []
    @State private var isLoading = false
    @State private var selectedPath = ""
    @State private var lastMessage = ""
    @State private var reportDraft = ""
    @State private var reportNotes = ""
    @State private var filter = "all"
    @State private var selectedTab = "repositories"
    @State private var pendingAction: RepoAction?
    @State private var showDirtyWarning = false
    @State private var notice: WorkNotice?

    private var filteredRepositories: [LocalRepositoryOption] {
        switch filter {
        case "needsUpdate":
            return repositories.filter { $0.needsUpdate }
        case "dirty":
            return repositories.filter { $0.dirtyCount > 0 }
        case "push":
            return repositories.filter { ($0.ahead ?? 0) > 0 }
        default:
            return repositories
        }
    }

    private var needsUpdateCount: Int {
        repositories.filter { $0.needsUpdate }.count
    }

    private var dirtyCount: Int {
        repositories.filter { $0.dirtyCount > 0 }.count
    }

    private var pushCount: Int {
        repositories.filter { ($0.ahead ?? 0) > 0 }.count
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

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        metricStrip
                        dashboardTabs
                        selectedDashboardContent
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(preferredScheme)
        .frame(minWidth: 980, minHeight: 760)
        .task {
            await reload()
            await autoRefreshLoop()
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

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text("PAS 작업 대시보드")
                    .font(.system(size: 25, weight: .bold))

                Text("관리 저장소 정비, 보고서 작성, 보조 도구를 흐름별로 나눠 처리합니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("화면", selection: $appearance) {
                Label("시스템", systemImage: "circle.lefthalf.filled").tag("system")
                Label("라이트", systemImage: "sun.max").tag("light")
                Label("다크", systemImage: "moon").tag("dark")
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            StatusPill(text: runner.status, isRunning: runner.isRunning)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.regularMaterial)
    }

    private var metricStrip: some View {
        HStack(spacing: 12) {
            MetricTile(title: "관리 저장소", value: "\(repositories.count)", systemImage: "folder.badge.gearshape", tint: .blue)
            MetricTile(title: "정비 필요", value: "\(needsUpdateCount)", systemImage: "arrow.down.circle.fill", tint: needsUpdateCount > 0 ? .orange : .green)
            MetricTile(title: "변경 있음", value: "\(dirtyCount)", systemImage: "exclamationmark.triangle.fill", tint: dirtyCount > 0 ? .orange : .green)
            MetricTile(title: "올릴 커밋", value: "\(pushCount)", systemImage: "arrow.up.circle.fill", tint: pushCount > 0 ? .purple : .green)
        }
    }

    private var dashboardTabs: some View {
        Picker("작업 영역", selection: $selectedTab) {
            Label("저장소", systemImage: "folder.badge.gearshape").tag("repositories")
            Label("보고서", systemImage: "doc.text").tag("report")
            Label("도구/AI", systemImage: "wand.and.stars").tag("tools")
            Label("결과", systemImage: "terminal").tag("result")
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var selectedDashboardContent: some View {
        switch selectedTab {
        case "report":
            reportSection
        case "tools":
            VStack(alignment: .leading, spacing: 16) {
                toolActions
                aiSection
            }
        case "result":
            resultSection
        default:
            VStack(alignment: .leading, spacing: 16) {
                repositoryActions
                repositorySection
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
                            failure: "출근 저장소 정비 실패"
                        )
                    }
                }
                .disabled(runner.isRunning)

                Spacer()
            }
        }
    }

    private var toolActions: some View {
        DashboardPanel(title: "루틴 도구", systemImage: "checklist.checked") {
            HStack(spacing: 10) {
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

                Spacer()
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
                        Text("변경 있음").tag("dirty")
                        Text("올릴 커밋").tag("push")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)

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
                    VStack(spacing: 10) {
                        ForEach(filteredRepositories) { repo in
                            RepositoryDashboardRow(
                                repo: repo,
                                isSelected: selectedPath == repo.path,
                                isRunning: runner.isRunning,
                                onSelect: {
                                    selectedPath = repo.path
                                },
                                onCommits: {
                                    Task { await showTodayCommits(repo) }
                                },
                                onFetch: {
                                    Task { await run(repo, mode: "fetch") }
                                },
                                onPull: {
                                    Task { await run(repo, mode: "pull") }
                                },
                                onRebase: {
                                    Task { await run(repo, mode: "rebase") }
                                },
                                onPush: {
                                    Task { await run(repo, mode: "push") }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var reportSection: some View {
        DashboardPanel(title: "오늘 작업 보고서", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DashboardButton(title: "초안 만들기", systemImage: "doc.badge.gearshape") {
                        Task {
                            reportDraft = await runner.previewDailyReport(notes: reportNotes)
                            lastMessage = reportDraft
                            showNotice(title: "보고서 미리보기", message: reportDraft, succeeded: !reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .disabled(runner.isRunning)

                    DashboardButton(title: "보고 규칙", systemImage: "doc.plaintext") {
                        runner.openReportAgentEditor()
                    }
                    .disabled(runner.isRunning)

                    DashboardButton(title: "보고서 공유", systemImage: "paperplane.fill") {
                        Task {
                            lastMessage = await runner.sendEditedReport(reportDraft)
                            showNotice(title: "보고서 공유", message: lastMessage, succeeded: !runner.status.contains("실패"))
                        }
                    }
                    .disabled(runner.isRunning || reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("수동 메모")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $reportNotes)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.65))
                        )
                }

                TextEditor(text: $reportDraft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 170)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.8))
                    )
            }
        }
    }

    private var aiSection: some View {
        DashboardPanel(title: "AI 작성 보조", systemImage: "brain.head.profile") {
            HStack(spacing: 10) {
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

    private var resultSection: some View {
        DashboardPanel(title: "실행 결과", systemImage: "terminal") {
            ScrollView {
                Text(lastMessage.isEmpty ? "아직 실행한 작업이 없습니다." : lastMessage)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 110)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.84))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8))
            )
        }
    }

    private func reload(notify: Bool = false, fetchRemote: Bool = false) async {
        isLoading = true
        if fetchRemote {
            repositories = await runner.refreshManagedRepositories(fetchRemote: true)
        } else {
            repositories = await runner.loadManagedRepositories()
        }
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
            guard !runner.isRunning, !isLoading else {
                continue
            }
            await reload(fetchRemote: true)
        }
    }

    private func showTodayCommits(_ repo: LocalRepositoryOption) async {
        selectedPath = repo.path
        lastMessage = await runner.loadTodayCommits(path: repo.path)
        showNotice(title: "\(repo.name) 오늘 커밋", message: lastMessage, succeeded: !runner.status.contains("실패"))
    }

    private func showTodayActivity() async {
        lastMessage = await runner.loadTodayActivity()
        showNotice(title: "오늘 흐름", message: lastMessage, succeeded: !runner.status.contains("실패"))
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
