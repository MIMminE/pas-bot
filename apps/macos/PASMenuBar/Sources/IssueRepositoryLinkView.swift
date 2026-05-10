import SwiftUI

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
                    Text(summary.isEmpty ? "이 Jira 일감을 어느 관리 repository에서 처리할지 선택합니다." : summary)
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
                    Text("관리 중인 Git repository를 확인하는 중...")
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
                    Text("설정에서 GitHub 후보를 불러온 뒤 관리 repository를 먼저 등록해 주세요.")
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

                Button("브랜치 시작 후 IDE 열기") {
                    Task { await saveLinkStartBranchAndOpenIDE() }
                }
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

    private func saveLinkStartBranchAndOpenIDE() async {
        let result = await runner.linkIssueRepository(issue: issue, repo: selectedPath, summary: summary)
        resultMessage = result.displayText
        guard result.succeeded else { return }
        runner.closeIssueRepositoryLinkWindow()
        await runner.createBranch(issue: issue, repo: selectedPath, summary: summary)
        runner.openRepositoryInIDE(path: selectedPath, appName: runner.loadSettings().defaultIDEAppName)
    }
}


