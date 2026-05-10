import SwiftUI

struct WorkView: View {
    @ObservedObject var runner: PASRunner

    @AppStorage("pas.work.appearance") private var appearance = "system"

    @State private var repositories: [LocalRepositoryOption] = []
    @State private var isLoading = false
    @State private var selectedPath = ""
    @State private var lastMessage = ""
    @State private var reportDraft = ""
    @State private var filter = "all"
    @State private var pendingAction: RepoAction?
    @State private var showDirtyWarning = false

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
                        quickActions
                        repositorySection

                        HStack(alignment: .top, spacing: 16) {
                            reportSection
                                .frame(maxWidth: .infinity)
                            aiSection
                                .frame(width: 260)
                        }

                        resultSection
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(preferredScheme)
        .frame(minWidth: 980, minHeight: 760)
        .task {
            await reload()
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

                Text("관리 repo 상태, 출근 정비, 보고서 작성, AI 초안을 한 화면에서 처리합니다.")
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
            MetricTile(title: "관리 repo", value: "\(repositories.count)", systemImage: "folder.badge.gearshape", tint: .blue)
            MetricTile(title: "업데이트 필요", value: "\(needsUpdateCount)", systemImage: "arrow.down.circle.fill", tint: needsUpdateCount > 0 ? .orange : .green)
            MetricTile(title: "변경 있음", value: "\(dirtyCount)", systemImage: "exclamationmark.triangle.fill", tint: dirtyCount > 0 ? .orange : .green)
            MetricTile(title: "push 필요", value: "\(pushCount)", systemImage: "arrow.up.circle.fill", tint: pushCount > 0 ? .purple : .green)
        }
    }

    private var quickActions: some View {
        DashboardPanel(title: "빠른 실행", systemImage: "wand.and.stars") {
            HStack(spacing: 10) {
                DashboardButton(title: isLoading ? "불러오는 중" : "새로고침", systemImage: "arrow.clockwise") {
                    Task { await reload() }
                }
                .disabled(isLoading || runner.isRunning)

                DashboardButton(title: "Git 상태 전송", systemImage: "paperplane") {
                    runner.run(["repo", "status", "--send-slack"])
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "출근 Git 정비", systemImage: "sparkles") {
                    runner.run(["repo", "morning-sync", "--send-slack"])
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "퇴근 체크", systemImage: "checkmark.seal") {
                    runner.run(["routine", "evening", "--dry-run"])
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "Jira 누락 검사", systemImage: "number.square") {
                    runner.run(["dev", "audit-jira-keys"])
                }
                .disabled(runner.isRunning)

                Spacer()
            }
        }
    }

    private var repositorySection: some View {
        DashboardPanel(title: "로컬 Git repository", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("필터", selection: $filter) {
                        Text("전체").tag("all")
                        Text("rebase/pull 필요").tag("needsUpdate")
                        Text("변경 있음").tag("dirty")
                        Text("push 필요").tag("push")
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
                        title: "관리 대상 repository가 없습니다",
                        message: "설정에서 로컬 root를 지정하고 관리할 프로젝트를 선택해 주세요."
                    )
                } else if filteredRepositories.isEmpty {
                    EmptyDashboardState(
                        systemImage: "line.3.horizontal.decrease.circle",
                        title: "현재 필터에 해당하는 repo가 없습니다",
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
                    DashboardButton(title: "미리보기 생성", systemImage: "doc.badge.gearshape") {
                        Task {
                            reportDraft = await runner.previewDailyReport()
                            lastMessage = reportDraft
                        }
                    }
                    .disabled(runner.isRunning)

                    DashboardButton(title: "Slack 전송", systemImage: "paperplane.fill") {
                        Task {
                            lastMessage = await runner.sendEditedReport(reportDraft)
                        }
                    }
                    .disabled(runner.isRunning || reportDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
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
        DashboardPanel(title: "AI 초안", systemImage: "brain.head.profile") {
            VStack(spacing: 10) {
                DashboardButton(title: "오늘 일 요약", systemImage: "text.badge.checkmark") {
                    runner.run(["ai", "git-summary", "--tone", "brief"])
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "관리자용 보고", systemImage: "person.text.rectangle") {
                    runner.run(["ai", "git-summary", "--tone", "manager"])
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "PR 초안", systemImage: "arrow.triangle.pull") {
                    var args = ["ai", "pr-draft", "--tone", "brief"]
                    if !selectedPath.isEmpty {
                        args.append(contentsOf: ["--repo", selectedPath])
                    }
                    runner.run(args)
                }
                .disabled(runner.isRunning)

                DashboardButton(title: "장애 원인 초안", systemImage: "stethoscope") {
                    runner.run(["ai", "incident-draft", "--tone", "detailed"])
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

    private func reload() async {
        isLoading = true
        repositories = await runner.loadManagedRepositories()
        isLoading = false
    }

    private func showTodayCommits(_ repo: LocalRepositoryOption) async {
        selectedPath = repo.path
        lastMessage = await runner.loadTodayCommits(path: repo.path)
    }

    private func run(_ repo: LocalRepositoryOption, mode: String, skipWarning: Bool = false) async {
        if !skipWarning && repo.dirtyCount > 0 && (mode == "pull" || mode == "rebase") {
            pendingAction = RepoAction(repo: repo, mode: mode)
            showDirtyWarning = true
            return
        }
        selectedPath = repo.path
        lastMessage = await runner.runRepositoryUpdate(path: repo.path, mode: mode)
        await reload()
    }
}

private struct StatusPill: View {
    let text: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 7) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
            }
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.16))
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        )
    }
}

private struct DashboardPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            content
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        )
    }
}

private struct DashboardButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

private struct RepositoryDashboardRow: View {
    let repo: LocalRepositoryOption
    let isSelected: Bool
    let isRunning: Bool
    let onSelect: () -> Void
    let onCommits: () -> Void
    let onFetch: () -> Void
    let onPull: () -> Void
    let onRebase: () -> Void
    let onPush: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(statusColor.opacity(0.16))
                    Image(systemName: statusImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(repo.name)
                            .font(.headline)
                        Text(repo.branch)
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    Text(repo.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        RepoStatusBadge(text: repo.syncLabel, color: statusColor)
                        if repo.dirtyCount > 0 {
                            RepoStatusBadge(text: "변경 \(repo.dirtyCount)", color: .orange)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    RepoIconButton(title: "커밋", systemImage: "list.bullet.rectangle", action: onCommits)
                        .disabled(isRunning)
                    RepoIconButton(title: "Fetch", systemImage: "arrow.triangle.2.circlepath", action: onFetch)
                        .disabled(isRunning)
                    RepoIconButton(title: "Pull", systemImage: "arrow.down", action: onPull)
                        .disabled(isRunning || !repo.canFastForward || repo.dirtyCount > 0)
                    RepoIconButton(title: "Rebase", systemImage: "arrow.triangle.branch", action: onRebase)
                        .disabled(isRunning || !repo.needsUpdate || repo.dirtyCount > 0)
                    RepoIconButton(title: "Push", systemImage: "arrow.up", action: onPush)
                        .disabled(isRunning || (repo.ahead ?? 0) == 0)
                }
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.13) : Color(nsColor: .textBackgroundColor).opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.75) : Color(nsColor: .separatorColor).opacity(0.45))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var statusColor: Color {
        if repo.dirtyCount > 0 {
            return .orange
        }
        if repo.needsRebase {
            return .red
        }
        if repo.needsUpdate {
            return .orange
        }
        if (repo.ahead ?? 0) > 0 {
            return .purple
        }
        return .green
    }

    private var statusImage: String {
        if repo.dirtyCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if repo.needsRebase {
            return "arrow.triangle.merge"
        }
        if repo.needsUpdate {
            return "arrow.down.circle.fill"
        }
        if (repo.ahead ?? 0) > 0 {
            return "arrow.up.circle.fill"
        }
        return "checkmark.circle.fill"
    }
}

private struct RepoIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.caption2)
            }
            .frame(width: 54, height: 42)
        }
        .buttonStyle(.bordered)
        .help(title)
    }
}

private struct RepoStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct EmptyDashboardState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RepoAction: Identifiable {
    let id = UUID()
    let repo: LocalRepositoryOption
    let mode: String
}
