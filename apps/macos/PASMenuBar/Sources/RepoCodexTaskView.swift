import SwiftUI

struct RepoCodexTaskView: View {
    @ObservedObject var runner: PASRunner
    let repo: LocalRepositoryOption

    @State private var selectedTask = RepoCodexTaskKind.commitSplit
    @State private var targetBranch = ""
    @State private var convention = Self.defaultConvention
    @State private var instruction = ""
    @State private var resultMessage = ""
    @State private var isOpeningCodex = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("작업", selection: $selectedTask) {
                ForEach(RepoCodexTaskKind.allCases) { task in
                    Text(task.title).tag(task)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isOpeningCodex || runner.isRunning)

            VStack(alignment: .leading, spacing: 10) {
                repoSummary

                if selectedTask == .pullRequest {
                    TextField("PR 대상 브랜치 예: \(repo.baseBranch.isEmpty ? "main 또는 dev" : repo.baseBranch)", text: $targetBranch)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("추가 지시")
                        .font(.caption.weight(.semibold))
                    TextEditor(text: $instruction)
                        .font(.body)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.62))
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("컨벤션")
                        .font(.caption.weight(.semibold))
                    TextEditor(text: $convention)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.62))
                        )
                }
            }

            if !resultMessage.isEmpty {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(resultMessage.contains("실패") ? .red : .secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            HStack {
                Button("기본값") {
                    instruction = selectedTask.defaultInstruction(repo: repo, targetBranch: effectiveTargetBranch)
                    convention = Self.defaultConvention
                }
                .disabled(isOpeningCodex || runner.isRunning)

                Spacer()

                Button("닫기") {
                    runner.closeRepoCodexTaskWindow()
                }

                Button {
                    Task { await openCodex() }
                } label: {
                    if isOpeningCodex {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Codex 열기", systemImage: "sparkles")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isOpeningCodex || runner.isRunning)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 540)
        .onAppear {
            if targetBranch.isEmpty {
                targetBranch = repo.baseBranch
            }
            if instruction.isEmpty {
                instruction = selectedTask.defaultInstruction(repo: repo, targetBranch: effectiveTargetBranch)
            }
        }
        .onChange(of: selectedTask) { task in
            instruction = task.defaultInstruction(repo: repo, targetBranch: effectiveTargetBranch)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(repo.name) Codex 작업")
                    .font(.title3.weight(.semibold))
                Text("이 저장소 기준으로 작업 지시서를 만들고 Codex를 엽니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var repoSummary: some View {
        HStack(spacing: 8) {
            RepoTaskChip(title: "브랜치", value: repo.branch)
            RepoTaskChip(title: "기준", value: repo.baseBranch.isEmpty ? "-" : repo.baseBranch)
            RepoTaskChip(title: "변경", value: "\(repo.dirtyCount)")
            Spacer(minLength: 0)
        }
    }

    private var effectiveTargetBranch: String {
        let trimmed = targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? repo.baseBranch : trimmed
    }

    private func openCodex() async {
        isOpeningCodex = true
        let taskInstruction = selectedTask.composedInstruction(
            baseInstruction: instruction,
            repo: repo,
            targetBranch: effectiveTargetBranch
        )
        let result = await runner.openCodexForRepositoryTask(
            repo: repo,
            instruction: taskInstruction,
            convention: convention,
            taskKind: selectedTask.title
        )
        resultMessage = result.displayText
        isOpeningCodex = false
        if result.succeeded {
            runner.closeRepoCodexTaskWindow()
        }
    }

    private static let defaultConvention = """
    - 먼저 `git status`, `git diff`, `git log --oneline --decorate -n 20`으로 현재 상태를 확인한다.
    - 사용자가 만든 변경을 되돌리지 않는다.
    - 커밋은 기능/수정/리팩토링/문서처럼 논리 단위로 나눈다.
    - 커밋 메시지는 repository의 AGENTS.md 또는 기존 git log 스타일을 우선한다.
    - PR은 기준 브랜치와 충돌 가능성, 테스트 결과, 확인 필요 사항을 포함해 작성한다.
    """
}

private enum RepoCodexTaskKind: String, CaseIterable, Identifiable {
    case commitSplit
    case pullRequest
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commitSplit:
            return "커밋 정리"
        case .pullRequest:
            return "PR 준비"
        case .custom:
            return "사용자 지시"
        }
    }

    func defaultInstruction(repo: LocalRepositoryOption, targetBranch: String) -> String {
        switch self {
        case .commitSplit:
            return """
            현재까지의 변경점을 검토해서 커밋 단위를 제안하고, 승인 가능한 단위로 나눠 커밋해줘.
            각 커밋은 변경 목적이 분명해야 하고, 불필요한 파일은 포함하지 말아줘.
            """
        case .pullRequest:
            return """
            현재 브랜치에서 \(targetBranch.isEmpty ? repo.baseBranch : targetBranch) 브랜치로 향하는 PR을 준비해줘.
            PR 제목/본문 초안을 만들고, 필요한 테스트와 리스크를 정리해줘.
            원격 push나 PR 생성은 사용자 승인 뒤 진행해줘.
            """
        case .custom:
            return """
            이 저장소에서 수행할 작업을 아래 지시에 맞춰 도와줘.
            먼저 현재 상태를 확인하고, 필요한 경우 작업 계획을 짧게 제안해줘.
            """
        }
    }

    func composedInstruction(baseInstruction: String, repo: LocalRepositoryOption, targetBranch: String) -> String {
        let trimmed = baseInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [trimmed.isEmpty ? defaultInstruction(repo: repo, targetBranch: targetBranch) : trimmed]
        if self == .pullRequest, !targetBranch.isEmpty {
            lines.append("PR target branch: \(targetBranch)")
        }
        return lines.joined(separator: "\n\n")
    }
}

private struct RepoTaskChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
