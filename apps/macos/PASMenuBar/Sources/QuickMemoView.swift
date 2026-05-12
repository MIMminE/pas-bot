import SwiftUI

struct QuickMemoView: View {
    @ObservedObject var runner: PASRunner

    @State private var targets: [MemoTargetOption] = [.general]
    @State private var selectedTargetID = MemoTargetOption.general.id
    @State private var memoText = ""
    @State private var resultMessage = ""
    @State private var isLoadingTargets = false
    @State private var isWaitingForMemoReply = false
    @State private var chatInput = ""
    @State private var chatMessages: [MemoChatMessage] = [
        MemoChatMessage(role: "Codex", text: "메모 초안 같이 정리해볼까요? 예: 핵심만 정리해줘, 보고서 문장으로 바꿔줘, TODO로 쪼개줘")
    ]

    private var selectedTarget: MemoTargetOption {
        targets.first { $0.id == selectedTargetID } ?? .general
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("빠른 작업 메모")
                        .font(.title3.weight(.semibold))
                    Text("작업을 고르고, 편하게 적어두면 필요할 때 같이 다듬어볼게요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker("작업", selection: $selectedTargetID) {
                ForEach(targets) { target in
                    Text("\(targetLabel(target)) · \(target.title)")
                        .tag(target.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(isLoadingTargets || runner.isRunning)

            HStack(spacing: 8) {
                Label(selectedTarget.subtitle, systemImage: targetIcon(selectedTarget))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(isLoadingTargets ? "불러오는 중" : "대상 새로고침") {
                    Task { await reloadTargets(forceRefresh: true) }
                }
                .disabled(isLoadingTargets || runner.isRunning)
            }

            HSplitView {
                TextEditor(text: $memoText)
                    .font(.system(.body, design: .default))
                    .frame(minWidth: 280, minHeight: 230)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.6))
                    )

                memoChatPanel
                    .frame(minWidth: 260, minHeight: 230)
            }

            if !resultMessage.isEmpty {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            HStack {
                Text("저장된 메모는 기록 메뉴의 작업 메모에서 확인할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("닫기") {
                    runner.closeQuickMemoWindow()
                }
                Button(isWaitingForMemoReply ? "다듬는 중..." : "Codex로 다듬기") {
                    Task { await refineMemo() }
                }
                .disabled(runner.isRunning || isWaitingForMemoReply || memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("저장") {
                    Task { await saveMemo() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(runner.isRunning || memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
        .task {
            targets = runner.memoTargets
            await reloadTargets()
        }
    }

    private func reloadTargets(forceRefresh: Bool = false) async {
        isLoadingTargets = true
        let loaded = await runner.loadMemoTargets(forceRefresh: forceRefresh)
        targets = loaded.isEmpty ? [.general] : loaded
        if !targets.contains(where: { $0.id == selectedTargetID }) {
            selectedTargetID = targets.first?.id ?? MemoTargetOption.general.id
        }
        isLoadingTargets = false
    }

    private func refineMemo() async {
        isWaitingForMemoReply = true
        let result = await runner.refineMemoWithCodex(text: memoText, targetTitle: selectedTarget.title)
        isWaitingForMemoReply = false
        resultMessage = result.displayText
        if result.succeeded {
            memoText = result.displayText
            chatMessages.append(MemoChatMessage(role: "Codex", text: "좋아요. 메모를 조금 더 매끈하게 다듬어서 왼쪽에 반영해뒀어요."))
        }
    }

    private var memoChatPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("메모 대화", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption.weight(.semibold))
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(chatMessages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(message.text)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .background(message.role == "나" ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if isWaitingForMemoReply {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Codex가 메모를 읽고 답을 고르는 중...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                TextField("메모에 대해 물어보기", text: $chatInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await askMemoCodex() }
                    }
                Button {
                    Task { await askMemoCodex() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 24, height: 22)
                }
                .disabled(runner.isRunning || isWaitingForMemoReply || chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 6) {
                quickAskButton("정리") { "핵심만 간단히 정리해줘." }
                quickAskButton("TODO") { "실행해야 할 TODO 목록으로 쪼개줘." }
                quickAskButton("보고") { "보고서에 넣기 좋은 문장으로 바꿔줘." }
            }
        }
        .padding(9)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.46))
        )
    }

    private func quickAskButton(_ title: String, prompt: @escaping () -> String) -> some View {
        Button(title) {
            chatInput = prompt()
            Task { await askMemoCodex() }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .disabled(runner.isRunning || isWaitingForMemoReply || memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func askMemoCodex() async {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        chatInput = ""
        chatMessages.append(MemoChatMessage(role: "나", text: question))
        isWaitingForMemoReply = true
        let result = await runner.askCodexAboutMemo(text: memoText, targetTitle: selectedTarget.title, question: question)
        isWaitingForMemoReply = false
        resultMessage = result.displayText
        chatMessages.append(MemoChatMessage(role: "Codex", text: result.displayText))
    }

    private func saveMemo() async {
        let result = await runner.saveWorkMemo(target: selectedTarget, text: memoText)
        resultMessage = result.displayText
        if result.succeeded {
            runner.closeQuickMemoWindow()
        }
    }

    private func targetLabel(_ target: MemoTargetOption) -> String {
        switch target.type {
        case "jira": return "Jira"
        case "repo": return "Repo"
        default: return "일반"
        }
    }

    private func targetIcon(_ target: MemoTargetOption) -> String {
        switch target.type {
        case "jira": return "checklist"
        case "repo": return "folder"
        default: return "note.text"
        }
    }
}

private struct MemoChatMessage: Identifiable, Hashable {
    let id = UUID()
    let role: String
    let text: String
}
