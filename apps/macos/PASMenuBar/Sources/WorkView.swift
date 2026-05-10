import SwiftUI

struct WorkView: View {
    @ObservedObject var runner: PASRunner

    @State private var repositories: [LocalRepositoryOption] = []
    @State private var isLoading = false
    @State private var selectedPath = ""
    @State private var lastMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    quickActions
                    repositorySection
                    resultSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .task {
            await reload()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PAS 작업 콘솔")
                    .font(.title2)
                    .bold()

                Text("관리 중인 로컬 Git 프로젝트를 점검하고 필요한 업데이트 작업을 실행합니다.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(runner.status)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var quickActions: some View {
        GroupBox("간편 작업") {
            HStack(spacing: 10) {
                Button(isLoading ? "새로고침 중..." : "상태 새로고침") {
                    Task { await reload() }
                }
                .disabled(isLoading || runner.isRunning)

                Button("Git 상태 Slack 전송") {
                    runner.run(["repo", "status", "--send-slack"])
                }
                .disabled(runner.isRunning)

                Button("오늘 작업 보고 미리보기") {
                    runner.run(["repo", "report", "--snapshot", "morning", "--dry-run"])
                }
                .disabled(runner.isRunning)

                Button("오늘 작업 보고 전송") {
                    runner.run(["repo", "report", "--snapshot", "morning", "--send-slack"])
                }
                .disabled(runner.isRunning)

                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private var repositorySection: some View {
        GroupBox("관리 중인 로컬 Git 프로젝트") {
            VStack(alignment: .leading, spacing: 10) {
                if repositories.isEmpty {
                    Text("관리 대상 repository가 없습니다. 설정에서 root를 지정하고 프로젝트를 선택해 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(repositories) { repo in
                        repositoryRow(repo)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func repositoryRow(_ repo: LocalRepositoryOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(repo.name)
                            .font(.headline)
                        Text(repo.branch)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Text(repo.syncLabel)
                        .font(.caption)
                        .foregroundStyle(repo.needsUpdate ? .orange : .secondary)

                    Text(repo.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Button("Fetch") {
                            Task { await run(repo, mode: "fetch") }
                        }
                        .disabled(runner.isRunning)

                        Button("업데이트") {
                            Task { await run(repo, mode: "pull") }
                        }
                        .disabled(runner.isRunning || !repo.canFastForward)

                        Button("Rebase") {
                            Task { await run(repo, mode: "rebase") }
                        }
                        .disabled(runner.isRunning || !repo.needsUpdate)
                    }

                    if repo.dirtyCount > 0 {
                        Text("변경 파일 \(repo.dirtyCount)개")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(10)
        .background(selectedPath == repo.path ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            selectedPath = repo.path
        }
    }

    private var resultSection: some View {
        GroupBox("실행 결과") {
            ScrollView {
                Text(lastMessage.isEmpty ? "아직 실행한 작업이 없습니다." : lastMessage)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .frame(minHeight: 90)
        }
    }

    private func reload() async {
        isLoading = true
        repositories = await runner.loadManagedRepositories()
        isLoading = false
    }

    private func run(_ repo: LocalRepositoryOption, mode: String) async {
        selectedPath = repo.path
        lastMessage = await runner.runRepositoryUpdate(path: repo.path, mode: mode)
        await reload()
    }
}
