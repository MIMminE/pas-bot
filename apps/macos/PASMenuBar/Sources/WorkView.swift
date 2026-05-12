import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WorkView: View {
    @ObservedObject var runner: PASRunner
    private static let jiraKeyRegex = try? NSRegularExpression(pattern: #"[A-Z][A-Z0-9]+-\d+"#)

    @AppStorage("pas.work.appearance") private var appearance = "system"
    @AppStorage("pas.work.commandCenterExpanded") private var isCommandCenterExpanded = true
    @AppStorage("pas.work.repositoryOrder") private var repositoryOrderRaw = ""
    @AppStorage("pas.work.sidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("pas.work.selectedSection") private var selectedSection = "dashboard"
    @AppStorage("pas.briefing.yesterdayMemo") private var briefingYesterdayMemo = ""
    @AppStorage("pas.briefing.focusProject") private var briefingFocusProject = ""
    @AppStorage("pas.briefing.memoryLog") private var briefingMemoryLog = ""

    @State private var repositories: [LocalRepositoryOption] = []
    @State private var isLoading = false
    @State private var isInitialDataLoading = false
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
    @State private var jiraMorningItems: [JiraListItem] = []
    @State private var jiraNewItems: [JiraListItem] = []
    @State private var jiraLastUpdatedText = ""
    @State private var hasAutoLoadedJiraMorningItems = false
    @State private var hasPreloadedBriefingData = false
    @State private var jiraTeamFlowItems: [JiraFlowItem] = []
    @State private var teamFlowStatusFilter = "all"
    @State private var isJiraQuickCreatePresented = false
    @State private var quickJiraSummary = ""
    @State private var quickJiraDescription = ""
    @State private var quickJiraIssueType = "Task"
    @State private var quickJiraAssignee = ""
    @State private var quickJiraPriority = ""
    @State private var quickJiraDueDate = ""
    @State private var quickJiraLabels = ""
    @State private var submittedReports: [SubmittedReportRecord] = []
    @State private var selectedReportID = ""
    @State private var workMemos: [WorkMemoRecord] = []
    @State private var codexHealth = CodexHealthStatus.unknown

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

    private var todayTitle: String {
        Date().formatted(.dateTime.month(.abbreviated).day().weekday(.wide))
    }

    private var activeRepositoryCount: Int {
        repositories.filter { $0.isWorkingBranch || $0.dirtyCount > 0 || $0.todayCommitCount > 0 }.count
    }

    private var pendingRepositoryCount: Int {
        repositories.filter(\.needsUpdate).count
    }

    private var recentBriefingMemories: [String] {
        briefingMemoryLog
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(6)
    }

    private var filteredJiraTeamFlowItems: [JiraFlowItem] {
        guard teamFlowStatusFilter != "all" else {
            return jiraTeamFlowItems
        }
        if teamFlowStatusFilter == "done" {
            return jiraTeamFlowItems.filter(\.isDone)
        }
        if teamFlowStatusFilter == "open" {
            return jiraTeamFlowItems.filter { !$0.isDone }
        }
        return jiraTeamFlowItems.filter { $0.status == teamFlowStatusFilter }
    }

    private var selectedReport: SubmittedReportRecord? {
        submittedReports.first { $0.id == selectedReportID } ?? submittedReports.first
    }

    private var currentMonthCalendarDays: [Int] {
        let calendar = Calendar.current
        let now = Date()
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: now),
            let range = calendar.range(of: .day, in: .month, for: now)
        else {
            return []
        }
        let leading = calendar.component(.weekday, from: monthInterval.start) - 1
        return Array(repeating: 0, count: leading) + Array(range)
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
            await initialDataLoad()
            await autoRefreshLoop()
        }
        .task {
            await jiraIssueWatchLoop()
        }
        .task(id: selectedSection) {
            await autoLoadJiraMorningItemsIfNeeded()
        }
        .onChange(of: runner.activeProfileID) { _ in
            reportDraft = ""
            reportNotes = ""
            branchOptionsByPath = [:]
            hasAutoLoadedJiraMorningItems = false
            jiraMorningItems = []
            jiraNewItems = []
            jiraLastUpdatedText = ""
            if selectedSection == "jira" || selectedSection == "briefing" {
                selectedSection = "dashboard"
            }
            hasPreloadedBriefingData = false
            jiraTeamFlowItems = []
            submittedReports = []
            workMemos = []
            isInitialDataLoading = false
            Task {
                await initialDataLoad(notify: true)
            }
        }
        .sheet(item: $notice) { notice in
            WorkNoticeView(notice: notice)
        }
        .sheet(isPresented: $isJiraQuickCreatePresented) {
            JiraQuickCreateSheet(
                summary: $quickJiraSummary,
                description: $quickJiraDescription,
                issueType: $quickJiraIssueType,
                assignee: $quickJiraAssignee,
                priority: $quickJiraPriority,
                dueDate: $quickJiraDueDate,
                labels: $quickJiraLabels,
                isRunning: runner.isRunning,
                onCancel: {
                    isJiraQuickCreatePresented = false
                },
                onCreate: {
                    Task { await createQuickJiraIssue() }
                }
            )
        }
        .alert("변경 파일이 있습니다", isPresented: $showDirtyWarning, presenting: pendingAction) { _ in
            Button("확인", role: .cancel) {}
        } message: { action in
            Text("\(action.repo.name)에 커밋하지 않은 변경 파일이 있습니다. 업데이트나 rebase 전에 commit 또는 stash를 먼저 처리해 주세요.")
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 8) {
            if isInitialDataLoading {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("초기 데이터 로딩")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                .clipShape(Capsule())
            }

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
        case "dashboard", "briefing":
            dashboardSection
        case "report":
            reportSection
        case "records":
            recordsSection
        case "jira":
            dashboardSection
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
                    toolActions
                        .frame(maxWidth: .infinity)
                    aiSection
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardPanel(title: "오늘 대시보드", systemImage: "rectangle.grid.2x2") {
                HStack(spacing: 6) {
                    panelActionChip(title: "브리핑", systemImage: "doc.text") {
                        Task {
                            await runDashboardCommand(
                                ["routine", "morning", "--dry-run"],
                                title: "출근 브리핑",
                                running: "출근 브리핑을 만드는 중...",
                                success: "출근 브리핑 완료",
                                failure: "출근 브리핑 실패"
                            )
                            rememberBriefing("출근 브리핑 미리보기 생성")
                        }
                    }
                    .disabled(runner.isRunning)

                    if !runner.isPersonalProfile {
                        panelActionChip(title: "Slack", systemImage: "paperplane.fill") {
                            Task {
                                await runDashboardCommand(
                                    ["routine", "morning", "--send-slack"],
                                    title: "출근 브리핑 공유",
                                    running: "출근 브리핑을 Slack으로 공유하는 중...",
                                    success: "출근 브리핑을 Slack으로 공유했습니다",
                                    failure: "출근 브리핑 공유 실패"
                                )
                                rememberBriefing("출근 브리핑 Slack 공유")
                            }
                        }
                        .disabled(runner.isRunning)
                    }

                    panelActionChip(title: "퇴근", systemImage: "checkmark.seal") {
                        Task {
                            await runDashboardCommand(
                                ["routine", "evening", "--dry-run"],
                                title: "퇴근 전 점검",
                                running: "퇴근 전 점검을 만드는 중...",
                                success: "퇴근 전 점검 완료",
                                failure: "퇴근 전 점검 실패"
                            )
                            rememberBriefing("퇴근 전 점검 미리보기 생성")
                        }
                    }
                    .disabled(runner.isRunning)
                }
            } content: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(todayTitle)
                                .font(.title2.weight(.semibold))
                            Text(runner.isPersonalProfile ? "개인 프로젝트 대시보드" : "업무 대시보드")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            codexHealthChip
                            briefingChannelBadge(title: "Slack", systemImage: "paperplane.fill", state: runner.isPersonalProfile ? "숨김" : "전송", tint: .green)
                            briefingChannelBadge(title: "앱 알림", systemImage: "bell.badge", state: "예정", tint: .orange)
                            briefingChannelBadge(title: "앱 내부", systemImage: "rectangle.stack", state: "활성", tint: .blue)
                        }
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                        ],
                        spacing: 10
                    ) {
                        briefingMetric(title: "해야 할 일", value: "\(jiraMorningItems.count)", systemImage: "checklist", tint: .blue, isAttention: false)
                        briefingMetric(title: "새 Jira", value: "\(jiraNewItems.count)", systemImage: "bell.badge", tint: .orange, isAttention: jiraNewItems.count > 0)
                        briefingMetric(title: "작업 저장소", value: "\(activeRepositoryCount)", systemImage: "folder.badge.gearshape", tint: .green, isAttention: false)
                        briefingMetric(title: "정비 필요", value: "\(pendingRepositoryCount)", systemImage: "arrow.triangle.2.circlepath", tint: .red, isAttention: pendingRepositoryCount > 0)
                    }

                }
            }

            myJiraDashboardPanel

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 320), spacing: 12, alignment: .top),
                    GridItem(.flexible(minimum: 320), spacing: 12, alignment: .top),
                ],
                alignment: .leading,
                spacing: 12
            ) {
                if !runner.isPersonalProfile {
                    teamFlowPanel
                }
                focusProjectPanel
                yesterdayMemoPanel
                briefingMemoryPanel
                calendarBriefingPanel
                weeklyBriefingPanel
                monthlyBriefingPanel
            }
        }
    }

    private func briefingMetric(title: String, value: String, systemImage: String, tint: Color, isAttention: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint.opacity(isAttention ? 0.95 : 0.72))
                Spacer()
            }
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(isAttention ? 0.12 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isAttention ? tint.opacity(0.34) : Color(nsColor: .separatorColor).opacity(0.35))
        )
    }

    private func briefingChannelBadge(title: String, systemImage: String, state: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
            Text(state)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.09))
        .foregroundStyle(tint.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18))
        )
    }

    private var codexHealthChip: some View {
        Button {
            Task { await loadCodexHealth() }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(codexHealth.isAvailable ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("Codex")
                    .font(.caption.weight(.semibold))
                Text(codexHealth.authMethod)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background((codexHealth.isAvailable ? Color.green : Color.orange).opacity(0.09))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke((codexHealth.isAvailable ? Color.green : Color.orange).opacity(0.20))
            )
        }
        .buttonStyle(.plain)
        .help("Codex 상태: \(codexHealth.version) · \(codexHealth.authMethod)\n\(codexHealth.executablePath)")
    }

    private func compactBriefingButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func panelActionChip(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var myJiraDashboardPanel: some View {
        DashboardPanel(title: "내 Jira 업무", systemImage: "checklist") {
            HStack(spacing: 6) {
                panelActionChip(title: "새로고침", systemImage: "arrow.clockwise") {
                    Task { await loadJiraMorningItems(notifyLocal: false) }
                }
                .disabled(runner.isRunning || runner.isPersonalProfile)

                if !runner.isPersonalProfile {
                    panelActionChip(title: "일감", systemImage: "plus.app") {
                        isJiraQuickCreatePresented = true
                    }
                    .disabled(runner.isRunning)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if runner.isPersonalProfile {
                    EmptyDashboardState(systemImage: "checklist", title: "개인 할 일 연결 전", message: "개인 프로젝트용 이슈 소스를 붙이면 이곳에 표시합니다.")
                } else if jiraMorningItems.isEmpty {
                    EmptyDashboardState(systemImage: "checklist", title: "Jira 일감 없음", message: "앱 실행 시 내게 할당된 Jira 업무를 자동으로 가져옵니다.")
                } else {
                    HStack(spacing: 8) {
                        flowTag("전체 \(jiraMorningItems.count)", tint: .blue)
                        flowTag("높은 우선순위 \(jiraMorningItems.filter { $0.priorityText.contains("High") || $0.priorityText.contains("높") }.count)", tint: .orange)
                        flowTag("마감 있음 \(jiraMorningItems.filter { $0.dueText != "-" }.count)", tint: .red)
                        Spacer()
                    }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(jiraMorningItems.prefix(12)) { item in
                                myJiraWorkCard(item)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 260, maxHeight: 520)
                }

            }
        }
    }

    private func myJiraWorkCard(_ item: JiraListItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                flowTag(item.key, tint: .blue)
                flowTag("태그 \(item.key)", tint: .purple)
                jiraMetaChip(item.statusText, tint: flowTint(for: item.statusText))
                if item.priorityText != "-" {
                    jiraMetaChip(item.priorityText, tint: item.priorityText.contains("High") || item.priorityText.contains("높") ? .orange : .secondary)
                }
                Spacer(minLength: 8)
                if item.dueText != "-" {
                    Label(item.dueText, systemImage: "calendar")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.red.opacity(0.82))
                        .lineLimit(1)
                }
            }

            Text(item.title.isEmpty ? "제목 없음" : item.title)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !item.bodyText.isEmpty {
                Text(item.bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                jiraInfoPill("담당", item.assigneeText)
                jiraInfoPill("등록", item.createdText)
                jiraInfoPill("갱신", item.updatedText)
                Spacer(minLength: 0)
            }

            Divider()
                .opacity(0.58)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    issueActionButton("연결/태그", systemImage: "link.badge.plus") {
                        runner.openIssueRepositoryLinkWindow(issue: item.key, summary: item.title)
                    }
                    issueActionButton("브랜치 시작", systemImage: "arrow.branch") {
                        Task { await startIssueWork(item) }
                    }
                    issueActionButton("추적", systemImage: "point.3.connected.trianglepath.dotted") {
                        Task { await traceIssueWork(item) }
                    }
                    issueActionButton("추천", systemImage: "sparkles") {
                        Task { await recommendIssueRepository(item) }
                    }
                    issueActionButton("Codex", systemImage: "sparkles.rectangle.stack") {
                        Task { await openCodexWorkspace(item) }
                    }
                    if let link = item.link, !link.isEmpty {
                        issueActionButton("Jira", systemImage: "arrow.up.right.square") {
                            runner.openExternalURL(link)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.40))
        )
        .contentShape(Rectangle())
    }

    private func issueActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.70))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(nsColor: .separatorColor).opacity(0.30))
                )
        }
        .buttonStyle(.plain)
        .disabled(runner.isRunning)
    }

    private func jiraMetaChip(_ text: String, tint: Color) -> some View {
        Text(text.isEmpty ? "-" : text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .foregroundStyle(tint.opacity(0.92))
            .clipShape(Capsule())
    }

    private func jiraInfoPill(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .foregroundStyle(.primary.opacity(0.78))
                .lineLimit(1)
        }
        .font(.caption2)
    }

    private var teamFlowPanel: some View {
        DashboardPanel(title: "팀 Jira 흐름", systemImage: "arrow.triangle.branch") {
            panelActionChip(title: "새로고침", systemImage: "arrow.clockwise") {
                Task { await loadJiraTeamFlow() }
            }
            .disabled(runner.isRunning)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if jiraTeamFlowItems.isEmpty {
                    EmptyDashboardState(systemImage: "arrow.triangle.branch", title: "팀 흐름을 불러오는 중입니다", message: "앱 실행 시 최근 7일 기준 Jira 담당/처리 흐름을 자동으로 조회합니다.")
                } else {
                    let grouped = Dictionary(grouping: jiraTeamFlowItems, by: \.status)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            flowFilterButton(title: "전체 \(jiraTeamFlowItems.count)", value: "all", tint: .primary.opacity(0.8))
                            flowFilterButton(title: "완료 \(jiraTeamFlowItems.filter(\.isDone).count)", value: "done", tint: .green)
                            flowFilterButton(title: "진행 \(jiraTeamFlowItems.filter { !$0.isDone }.count)", value: "open", tint: .orange)
                            ForEach(grouped.keys.sorted(), id: \.self) { status in
                                flowFilterButton(title: "\(status) \(grouped[status]?.count ?? 0)", value: status, tint: flowTint(for: status))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredJiraTeamFlowItems.prefix(6)) { item in
                            Button {
                                if !item.link.isEmpty {
                                    runner.openExternalURL(item.link)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    flowTag(item.key, tint: .blue)
                                    Text(item.title.isEmpty ? "제목 없음" : item.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    fixedFlowTag(item.status, tint: flowTint(for: item.status), width: 84)
                                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(item.isDone ? Color.green.opacity(0.72) : Color.secondary)
                                }
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.44))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            }
        }
    }

    private func teamFlowRow(_ item: JiraFlowItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    flowTag(item.key, tint: .blue)
                    flowTag(item.issueType, tint: .secondary)
                    Text(item.project)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(item.title.isEmpty ? "제목 없음" : item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.link.isEmpty ? "Jira 링크 없음" : item.link)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                fixedFlowTag(item.status, tint: flowTint(for: item.status), width: 104)
                Text(item.isDone ? "처리 완료" : "진행 확인")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.isDone ? Color.green.opacity(0.82) : Color.orange.opacity(0.82))
            }
            .frame(width: 116, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                personFlowLine(title: "등록", name: item.reporter, tint: .purple)
                personFlowLine(title: "담당", name: item.assignee, tint: .blue)
            }
            .frame(width: 188, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("등록 \(item.created)")
                Text("갱신 \(item.updated)")
                if item.due != "-" {
                    Text("마감 \(item.due)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 120, alignment: .leading)

            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42))
        )
    }

    private func personFlowLine(title: String, name: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            fixedFlowTag(name, tint: tint, width: 136)
        }
    }

    private func flowTag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .foregroundStyle(tint.opacity(0.9))
            .clipShape(Capsule())
    }

    private func fixedFlowTag(_ text: String, tint: Color, width: CGFloat) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .foregroundStyle(tint.opacity(0.9))
            .clipShape(Capsule())
    }

    private func flowFilterButton(title: String, value: String, tint: Color) -> some View {
        Button {
            teamFlowStatusFilter = value
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(teamFlowStatusFilter == value ? tint.opacity(0.18) : tint.opacity(0.08))
                .foregroundStyle(tint.opacity(0.92))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(teamFlowStatusFilter == value ? tint.opacity(0.44) : Color(nsColor: .separatorColor).opacity(0.26), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func flowTint(for status: String) -> Color {
        let value = status.lowercased()
        if value.contains("done") || value.contains("complete") || value.contains("완료") || value.contains("배포") {
            return .green
        }
        if value.contains("progress") || value.contains("진행") || value.contains("작업") || value.contains("리뷰") {
            return .blue
        }
        if value.contains("backlog") || value.contains("todo") || value.contains("할 일") {
            return .secondary
        }
        return .orange
    }

    private var focusProjectPanel: some View {
        DashboardPanel(title: "주 프로젝트", systemImage: "scope") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("오늘 집중할 프로젝트", text: $briefingFocusProject)
                    .textFieldStyle(.roundedBorder)

                if repositories.isEmpty {
                    EmptyDashboardState(systemImage: "folder", title: "저장소 정보 없음", message: "워크스페이스를 불러오면 주요 프로젝트 후보가 표시됩니다.")
                } else {
                    ForEach(repositories.prefix(4)) { repo in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(repo.needsUpdate ? Color.orange : Color.green)
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(repo.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(repo.branch)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var yesterdayMemoPanel: some View {
        DashboardPanel(title: "어제 메모", systemImage: "note.text") {
            panelActionChip(title: "반영", systemImage: "arrow.down.doc") {
                reportNotes = briefingYesterdayMemo
                rememberBriefing("어제 메모를 보고서 메모로 반영")
                selectedSection = "report"
            }
            .disabled(briefingYesterdayMemo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $briefingYesterdayMemo)
                    .font(.system(.body, design: .default))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.65))
                    )

            }
        }
    }

    private var briefingMemoryPanel: some View {
        DashboardPanel(title: "브리핑 기억", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                if recentBriefingMemories.isEmpty {
                    EmptyDashboardState(systemImage: "clock.arrow.circlepath", title: "아직 저장된 기억이 없습니다", message: "브리핑 보기, 보고서 생성, 메모 반영 같은 흐름을 이곳에 쌓아갑니다.")
                } else {
                    ForEach(recentBriefingMemories, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var calendarBriefingPanel: some View {
        DashboardPanel(title: "달력", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                briefingLine(title: "오늘", value: todayTitle)
                briefingLine(title: "Jira 마감", value: jiraMorningItems.filter { $0.detail.contains("마감:") && !$0.detail.contains("마감: -") }.isEmpty ? "표시할 마감 없음" : "해야 할 일에 표시")
                briefingLine(title: "기억", value: recentBriefingMemories.isEmpty ? "기록 없음" : "\(recentBriefingMemories.count)개")
                Text("다음 단계에서 캘린더 소스와 브리핑 기록을 날짜별 타임라인으로 연결합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weeklyBriefingPanel: some View {
        DashboardPanel(title: "이번 주", systemImage: "calendar") {
            panelActionChip(title: "흐름", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                Task { await showTodayActivity() }
            }
            .disabled(runner.isRunning)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                briefingLine(title: "작업 흐름", value: "\(activeRepositoryCount)개 저장소에서 움직임")
                briefingLine(title: "정비", value: pendingRepositoryCount == 0 ? "정비 필요 없음" : "\(pendingRepositoryCount)개 확인 필요")
                briefingLine(title: "보고", value: reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "초안 없음" : "초안 작성됨")
            }
        }
    }

    private var monthlyBriefingPanel: some View {
        DashboardPanel(title: "이번 달", systemImage: "calendar.badge.clock") {
            HStack(spacing: 6) {
                panelActionChip(title: "초안", systemImage: "doc.badge.gearshape") {
                    selectedSection = "report"
                    if reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task {
                            reportDraft = await runner.previewDailyReport(notes: briefingYesterdayMemo)
                            lastMessage = reportDraft
                            showNotice(title: "오늘 한 일 초안", message: reportDraft, succeeded: !reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            rememberBriefing("오늘 한 일 초안 생성")
                        }
                    }
                }
                .disabled(runner.isRunning)

                if !runner.isPersonalProfile {
                    panelActionChip(title: "공유", systemImage: "paperplane.fill") {
                        Task {
                            lastMessage = await runner.sendEditedReport(reportDraft)
                            showNotice(title: "보고서 공유", message: lastMessage, succeeded: !runner.status.contains("실패"))
                            rememberBriefing("보고서 Slack 공유")
                        }
                    }
                    .disabled(runner.isRunning || reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                briefingLine(title: "월간 회고", value: "초안 생성 준비")
                briefingLine(title: "주요 기록", value: "오늘 한 일 보고서와 메모 기반")
                briefingLine(title: "알림 채널", value: runner.isPersonalProfile ? "앱 내부 중심" : "Slack + 앱 내부")
            }
        }
    }

    private func briefingLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }

    private var jiraSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardPanel(title: "Jira 일감", systemImage: "checklist") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        DashboardButton(title: "아침 일감 새로고침", systemImage: "arrow.clockwise") {
                            Task { await loadJiraMorningItems(notifyLocal: true) }
                        }
                        .disabled(runner.isRunning)

                        DashboardButton(title: "새 일감 확인", systemImage: "bell.badge") {
                            Task { await checkNewJiraIssues(showEmptyResult: true) }
                        }
                        .disabled(runner.isRunning)

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Label("Slack 전송 없이 앱 안에서 일감을 확인합니다.", systemImage: "rectangle.stack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !jiraLastUpdatedText.isEmpty {
                            Text(jiraLastUpdatedText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            jiraListPanel(
                title: "내 아침 일감",
                systemImage: "sun.max",
                items: jiraMorningItems,
                emptyTitle: "아직 불러온 Jira 일감이 없습니다",
                emptyMessage: runner.isRunning ? "Jira 일감을 자동으로 불러오는 중입니다." : "Jira 메뉴에 들어오면 내게 할당된 미처리 일감이 자동으로 표시됩니다."
            )

            jiraListPanel(
                title: "새로 등록된 일감",
                systemImage: "bell.badge",
                items: jiraNewItems,
                emptyTitle: "새로 감지된 Jira 일감이 없습니다",
                emptyMessage: "업무 프로필에서는 5분마다 새 일감을 확인하고, 발견되면 이 목록과 macOS 알림에 함께 표시합니다."
            )
        }
    }

    private func jiraListPanel(
        title: String,
        systemImage: String,
        items: [JiraListItem],
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        DashboardPanel(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    EmptyDashboardState(systemImage: systemImage, title: emptyTitle, message: emptyMessage)
                } else {
                    ForEach(items) { item in
                        JiraIssueRow(item: item) {
                            if let link = item.link, !link.isEmpty {
                                runner.openExternalURL(link)
                            }
                        }
                    }
                }
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
                                onOpenCodex: {
                                    runner.openRepoCodexTaskWindow(repo: repo)
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
            HStack(spacing: 6) {
                panelActionChip(title: "초안", systemImage: "doc.badge.gearshape") {
                    Task {
                        reportDraft = await runner.previewDailyReport(notes: reportNotes)
                        lastMessage = reportDraft
                        showNotice(title: "오늘 한 일 초안", message: reportDraft, succeeded: !reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .disabled(runner.isRunning)

                panelActionChip(title: "ChatGPT", systemImage: "bubble.left.and.text.bubble.right") {
                    reportDraft = runner.makeChatGPTReportPrompt(draft: reportDraft, notes: reportNotes)
                    lastMessage = reportDraft
                    showNotice(title: "ChatGPT 전달용 프롬프트", message: reportDraft, succeeded: true)
                }
                .disabled(runner.isRunning)

                panelActionChip(title: "Codex", systemImage: "sparkles") {
                    Task { await refineReportWithCodex() }
                }
                .disabled(runner.isRunning)

                panelActionChip(title: "규칙", systemImage: "doc.plaintext") {
                    runner.openReportAgentEditor()
                }
                .disabled(runner.isRunning)

                if !runner.isPersonalProfile {
                    panelActionChip(title: "공유", systemImage: "paperplane.fill") {
                        Task {
                            lastMessage = await runner.sendEditedReport(reportDraft)
                            showNotice(title: "보고서 공유", message: lastMessage, succeeded: !runner.status.contains("실패"))
                        }
                    }
                    .disabled(runner.isRunning || reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                panelActionChip(title: "제출", systemImage: "tray.and.arrow.up.fill") {
                    Task { await submitReport() }
                }
                .disabled(runner.isRunning || reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
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

    private var recordsSection: some View {
        DashboardPanel(title: "업무 기록", systemImage: "calendar") {
            panelActionChip(title: "새로고침", systemImage: "arrow.clockwise") {
                    Task { await loadRecords() }
            }
            .disabled(runner.isRunning)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text("제출된 보고서와 Jira 처리 흐름을 날짜별로 확인합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 14) {
                    reportCalendarGrid
                        .frame(width: 300)

                    VStack(alignment: .leading, spacing: 12) {
                        selectedReportDetail
                        workMemoList
                        Divider()
                            .opacity(0.55)
                        teamFlowPanel
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .task {
                if submittedReports.isEmpty && workMemos.isEmpty {
                    await loadRecords()
                }
            }
        }
    }

    private var reportCalendarGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date().formatted(.dateTime.year().month(.wide)))
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(currentMonthCalendarDays, id: \.self) { day in
                    let reports = reports(on: day)
                    Button {
                        if let first = reports.first {
                            selectedReportID = first.id
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(day == 0 ? "" : "\(day)")
                                .font(.caption.weight(.semibold))
                            if !reports.isEmpty {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                            } else {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 38)
                        .frame(maxWidth: .infinity)
                        .background(calendarDayBackground(day: day, reports: reports))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(day == 0 || reports.isEmpty)
                    .help(reports.first?.title ?? "")
                }
            }

            if submittedReports.isEmpty {
                EmptyDashboardState(systemImage: "tray", title: "제출된 보고서 없음", message: "보고서 탭에서 제출하면 이곳에 날짜별로 쌓입니다.")
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(submittedReports.prefix(8)) { report in
                        Button {
                            selectedReportID = report.id
                        } label: {
                            HStack(spacing: 8) {
                                Text(report.date)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(report.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                if report.slackSent {
                                    Image(systemName: "paperplane.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.green)
                                }
                            }
                            .padding(8)
                            .background(selectedReportID == report.id ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.62))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42))
        )
    }

    private var selectedReportDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let report = selectedReport {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(report.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(report.date) · \(report.slackSent ? "앱 + Slack 제출" : "앱 기록")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        reportDraft = report.text
                        reportNotes = report.notes
                        selectedSection = "report"
                    } label: {
                        Label("다시 열기", systemImage: "arrow.uturn.left")
                    }
                    .buttonStyle(.bordered)
                }

                ScrollView {
                    Text(report.text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 180, maxHeight: 320)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.76))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                EmptyDashboardState(systemImage: "doc.text.magnifyingglass", title: "선택된 보고서 없음", message: "왼쪽 달력이나 목록에서 제출 기록을 선택하세요.")
            }
        }
    }

    private var workMemoList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("작업 메모", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                Button {
                    runner.openQuickMemoWindow()
                } label: {
                    Label("메모", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if workMemos.isEmpty {
                EmptyDashboardState(systemImage: "note.text", title: "저장된 작업 메모 없음", message: "메뉴바의 빠른 작업 메모에서 초안 메모를 남길 수 있습니다.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(workMemos.prefix(8)) { memo in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    flowTag(memo.targetID, tint: memo.targetType == "jira" ? .blue : .secondary)
                                    Text(memo.targetTitle)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(memo.date)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(memo.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.56))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 220)
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

    private func initialDataLoad(notify: Bool = false) async {
        guard !isInitialDataLoading else {
            return
        }
        isInitialDataLoading = true
        await reload(notify: notify)
        async let briefing: Void = preloadBriefingData()
        async let records: Void = loadRecords(skipJiraFlow: true)
        async let memoTargets: [MemoTargetOption] = runner.loadMemoTargets()
        async let codex: Void = loadCodexHealth()
        _ = await (briefing, records, memoTargets, codex)
        isInitialDataLoading = false
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
        let paths = repositories.map(\.path)
        let loaded = await withTaskGroup(of: (String, [BranchOption]).self) { group in
            for path in paths {
                group.addTask {
                    (path, await runner.loadRepositoryBranches(path: path))
                }
            }

            var values: [String: [BranchOption]] = [:]
            for await (path, branches) in group {
                values[path] = branches
            }
            return values
        }
        branchOptionsByPath = loaded
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

    private func startIssueWork(_ item: JiraListItem) async {
        let result = await runner.startIssueWork(issue: item.key, summary: item.title)
        lastMessage = result.displayText
        showNotice(title: "\(item.key) 작업 시작", message: result.displayText, succeeded: result.succeeded)
        if result.succeeded {
            rememberBriefing("\(item.key) repository 연결 및 브랜치 시작")
            await reload()
        }
    }

    private func recommendIssueRepository(_ item: JiraListItem) async {
        let result = await runner.recommendIssueRepository(issue: item.key, summary: item.title)
        lastMessage = result.displayText
        showNotice(title: "\(item.key) repository 추천", message: result.displayText, succeeded: result.succeeded)
    }

    private func traceIssueWork(_ item: JiraListItem) async {
        let result = await runner.traceIssueWork(issue: item.key)
        lastMessage = result.displayText
        showNotice(title: "\(item.key) 작업 추적", message: result.displayText, succeeded: result.succeeded)
    }

    private func openCodexWorkspace(_ item: JiraListItem) async {
        let result = await runner.openCodexWorkspaceForIssue(
            issue: item.key,
            summary: item.title,
            detail: item.detail,
            repositories: repositories
        )
        lastMessage = result.displayText
        showNotice(title: "\(item.key) Codex", message: result.displayText, succeeded: result.succeeded)
    }

    private func submitReport() async {
        let result = await runner.submitReport(reportDraft, notes: reportNotes, sendSlack: !runner.isPersonalProfile)
        lastMessage = result.displayText
        showNotice(title: "보고서 제출", message: result.displayText, succeeded: result.succeeded)
        if result.succeeded {
            rememberBriefing("보고서 제출")
            await loadRecords()
            selectedSection = "records"
        }
    }

    private func loadRecords(skipJiraFlow: Bool = false) async {
        submittedReports = await runner.loadSubmittedReports()
        workMemos = await runner.loadWorkMemos()
        if selectedReportID.isEmpty || !submittedReports.contains(where: { $0.id == selectedReportID }) {
            selectedReportID = submittedReports.first?.id ?? ""
        }
        if !runner.isPersonalProfile && !skipJiraFlow {
            await loadJiraTeamFlow(showFailureNotice: false)
        }
    }

    private func loadCodexHealth() async {
        codexHealth = await runner.loadCodexHealth()
    }

    private func reports(on day: Int) -> [SubmittedReportRecord] {
        guard day > 0 else {
            return []
        }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        let month = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        let date = "\(month)-\(String(format: "%02d", day))"
        return submittedReports.filter { $0.date == date }
    }

    private func calendarDayBackground(day: Int, reports: [SubmittedReportRecord]) -> Color {
        guard day > 0 else {
            return Color.clear
        }
        if reports.contains(where: { $0.id == selectedReportID }) {
            return Color.accentColor.opacity(0.18)
        }
        if !reports.isEmpty {
            return Color.accentColor.opacity(0.08)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.55)
    }

    private func refineReportWithCodex() async {
        var draft = reportDraft
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = await runner.previewDailyReport(notes: reportNotes)
            reportDraft = draft
        }
        let result = await runner.refineReportWithCodex(draft: draft, notes: reportNotes)
        lastMessage = result.displayText
        if result.succeeded {
            reportDraft = result.displayText
            rememberBriefing("Codex 보고서 다듬기")
        }
        showNotice(title: "Codex 보고서", message: result.displayText, succeeded: result.succeeded)
    }

    private func createQuickJiraIssue() async {
        let result = await runner.createJiraIssue(
            summary: quickJiraSummary,
            description: quickJiraDescription,
            issueType: quickJiraIssueType,
            assignee: quickJiraAssignee,
            priority: quickJiraPriority,
            dueDate: quickJiraDueDate,
            labels: quickJiraLabels
        )
        lastMessage = result.displayText
        showNotice(title: "Jira 일감 생성", message: result.displayText, succeeded: result.succeeded)
        if result.succeeded {
            isJiraQuickCreatePresented = false
            quickJiraSummary = ""
            quickJiraDescription = ""
            quickJiraIssueType = "Task"
            quickJiraAssignee = ""
            quickJiraPriority = ""
            quickJiraDueDate = ""
            quickJiraLabels = ""
            await loadJiraMorningItems(notifyLocal: false)
        }
    }

    private func preloadBriefingData() async {
        guard !runner.isPersonalProfile, !hasPreloadedBriefingData else {
            return
        }
        hasPreloadedBriefingData = true
        await loadJiraMorningItems(notifyLocal: false, showFailureNotice: false)
        await loadJiraTeamFlow(showFailureNotice: false)
    }

    private func autoLoadJiraMorningItemsIfNeeded() async {
        guard selectedSection == "jira", !runner.isPersonalProfile, !hasAutoLoadedJiraMorningItems, !runner.isRunning else {
            return
        }
        hasAutoLoadedJiraMorningItems = true
        await loadJiraMorningItems(notifyLocal: false, showFailureNotice: false)
    }

    private func loadJiraMorningItems(notifyLocal: Bool) async {
        await loadJiraMorningItems(notifyLocal: notifyLocal, showFailureNotice: true)
    }

    private func loadJiraMorningItems(notifyLocal: Bool, showFailureNotice: Bool) async {
        let result = await runner.runDashboardCommand(
            ["jira", "today"],
            runningStatus: "Jira 아침 일감을 불러오는 중...",
            successStatus: "Jira 아침 일감 불러오기 완료",
            failureStatus: "Jira 아침 일감 불러오기 실패"
        )
        lastMessage = result.displayText
        if result.succeeded {
            jiraMorningItems = parseJiraItems(from: result.displayText)
            jiraLastUpdatedText = "마지막 갱신 \(Date().formatted(date: .omitted, time: .shortened))"
        } else if showFailureNotice {
            showNotice(title: "Jira 아침 일감", message: result.displayText, succeeded: false)
        }
        if notifyLocal && result.succeeded {
            runner.sendLocalNotification(title: "Jira 아침 일감", body: jiraNotificationBody(items: jiraMorningItems, fallback: result.displayText))
        }
    }

    private func checkNewJiraIssues(showEmptyResult: Bool) async {
        let result = await runner.checkNewJiraIssues()
        lastMessage = result.displayText
        let hasNewIssues = result.displayText.hasPrefix("새로 등록된 Jira 일감")
        if hasNewIssues && result.succeeded {
            let parsedItems = parseJiraItems(from: result.displayText)
            jiraNewItems = mergeJiraItems(parsedItems, into: jiraNewItems)
            jiraLastUpdatedText = "마지막 갱신 \(Date().formatted(date: .omitted, time: .shortened))"
            runner.sendLocalNotification(title: "새 Jira 일감", body: jiraNotificationBody(items: parsedItems, fallback: result.displayText))
        }
        if !result.succeeded || (showEmptyResult && !hasNewIssues) {
            showNotice(title: "새 Jira 일감", message: result.displayText, succeeded: result.succeeded)
        }
    }

    private func loadJiraTeamFlow() async {
        await loadJiraTeamFlow(showFailureNotice: true)
    }

    private func loadJiraTeamFlow(showFailureNotice: Bool) async {
        let result = await runner.runDashboardCommand(
            ["jira", "flow", "--format", "tsv", "--days", "7"],
            runningStatus: "팀 Jira 흐름을 불러오는 중...",
            successStatus: "팀 Jira 흐름 불러오기 완료",
            failureStatus: "팀 Jira 흐름 불러오기 실패"
        )
        lastMessage = result.displayText
        if result.succeeded {
            jiraTeamFlowItems = parseJiraFlowItems(from: result.displayText)
            rememberBriefing("팀 Jira 흐름 새로고침")
        } else if showFailureNotice {
            showNotice(title: "팀 Jira 흐름", message: result.displayText, succeeded: false)
        }
    }

    private func parseJiraItems(from text: String) -> [JiraListItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [JiraListItem] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key = jiraKey(in: line), isPrimaryJiraLine(line) else {
                index += 1
                continue
            }

            var link: String?
            var details: [String] = []
            var nextIndex = index + 1
            while nextIndex < lines.count {
                let next = lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if next.isEmpty {
                    if details.isEmpty {
                        nextIndex += 1
                        continue
                    }
                    break
                }
                if jiraKey(in: next) != nil && isPrimaryJiraLine(next) {
                    break
                }
                if next.hasPrefix("링크:") {
                    link = next.replacingOccurrences(of: "링크:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if details.count < 3 {
                    details.append(next)
                }
                nextIndex += 1
            }

            items.append(
                JiraListItem(
                    key: key,
                    title: jiraTitle(from: line, key: key),
                    detail: details.joined(separator: "\n"),
                    link: link
                )
            )
            index = nextIndex
        }

        var seen: Set<String> = []
        return items.filter { item in
            let identity = "\(item.key)-\(item.title)"
            if seen.contains(identity) {
                return false
            }
            seen.insert(identity)
            return true
        }
    }

    private func isPrimaryJiraLine(_ line: String) -> Bool {
        if line.hasPrefix("[dry-run]") || line.hasPrefix("링크:") || line.contains("/browse/") {
            return false
        }
        if line.hasPrefix("관련 로컬 브랜치") || line.hasPrefix("연결 repository") || line.hasPrefix("하위 일감") {
            return false
        }
        if line.hasPrefix("- ") && !line.hasPrefix("- [") {
            return false
        }
        return true
    }

    private func jiraKey(in line: String) -> String? {
        guard let regex = Self.jiraKeyRegex else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range), let swiftRange = Range(match.range, in: line) else {
            return nil
        }
        return String(line[swiftRange])
    }

    private func jiraTitle(from line: String, key: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("- ") {
            value.removeFirst(2)
        }
        if value.hasPrefix("[\(key)]") {
            value.removeFirst(key.count + 2)
        } else if value.hasPrefix(key) {
            value.removeFirst(key.count)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " -|[]").union(.whitespacesAndNewlines))
    }

    private func mergeJiraItems(_ newItems: [JiraListItem], into currentItems: [JiraListItem]) -> [JiraListItem] {
        var output = newItems
        let newKeys = Set(newItems.map(\.key))
        output.append(contentsOf: currentItems.filter { !newKeys.contains($0.key) })
        return Array(output.prefix(40))
    }

    private func jiraNotificationBody(items: [JiraListItem], fallback: String) -> String {
        guard !items.isEmpty else {
            return fallback
        }
        let preview = items.prefix(3).map { "\($0.key) \($0.title)" }.joined(separator: "\n")
        if items.count > 3 {
            return "\(preview)\n외 \(items.count - 3)개"
        }
        return preview
    }

    private func parseJiraFlowItems(from text: String) -> [JiraFlowItem] {
        text.components(separatedBy: .newlines).compactMap { line in
            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 9 else {
                return nil
            }
            return JiraFlowItem(
                key: columns[0],
                title: columns[1],
                status: columns[2],
                reporter: columns[3],
                assignee: columns[4],
                created: columns[5],
                updated: columns[6],
                due: columns[7],
                issueType: columns.count > 9 ? columns[8] : "-",
                project: columns.count > 9 ? columns[9] : "-",
                link: columns.count > 10 ? columns[10] : columns[8]
            )
        }
    }

    private func rememberBriefing(_ text: String) {
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        var lines = briefingMemoryLog
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        lines.append("\(stamp) · \(text)")
        briefingMemoryLog = lines.suffix(80).joined(separator: "\n")
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
