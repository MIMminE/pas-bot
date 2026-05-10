import SwiftUI

struct ReportAgentEditorView: View {
    @ObservedObject var runner: PASRunner

    @State private var rules = ""
    @State private var message = ""
    @State private var lastSavedRules = ""

    private var hasChanges: Bool {
        rules != lastSavedRules
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text("보고서 작성 규칙")
                        .font(.title3)
                        .bold()
                    Text("오늘 작업 보고서를 AI가 어떤 형식과 말투로 정리할지 정합니다.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasChanges {
                    Text("저장 안 됨")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Markdown 규칙")
                        .font(.headline)
                    TextEditor(text: $rules)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.75))
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("작성 가이드")
                        .font(.headline)
                    GuideHint(title: "섹션", detail: "오늘 한 일, 주요 변경점, 확인 필요, 내일 이어갈 일처럼 원하는 순서를 적습니다.")
                    GuideHint(title: "말투", detail: "간결/상세/관리자용, 명사형 선호 같은 톤을 지정합니다.")
                    GuideHint(title: "금지사항", detail: "모르는 내용을 단정하지 않기, 민감정보 제외 같은 규칙을 넣습니다.")
                    GuideHint(title: "우선순위", detail: "수동 메모를 커밋보다 우선할지, Git 근거만 사실로 볼지 정합니다.")
                    Spacer()
                }
                .frame(width: 220)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.contains("실패") ? .red : .secondary)
            }

            HStack {
                Button("기본 예시로 되돌리기") {
                    rules = Self.defaultRules
                }

                Spacer()

                Button("닫기") {
                    runner.closeReportAgentWindow()
                }

                Button("저장") {
                    let result = runner.saveReportAgentRules(rules)
                    message = result.displayText
                    if result.succeeded {
                        lastSavedRules = rules
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasChanges)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 620)
        .task {
            let loaded = runner.loadReportAgentRules()
            rules = loaded
            lastSavedRules = loaded
        }
    }

    private static let defaultRules = """
    # PAS Report Agent

    ## 목표

    - Slack에 바로 보낼 수 있는 한국어 일일 업무 보고서를 작성한다.
    - Git 커밋, 브랜치, 동기화 상태를 근거로 삼고, 사용자가 직접 작성한 메모를 함께 반영한다.
    - 확인된 사실과 추정은 구분한다.

    ## 출력 형식

    1. 오늘 한 일
    2. 주요 변경점
    3. 확인 필요
    4. 내일 이어갈 일

    ## 말투

    - 간결하게 쓴다.
    - 과장하지 않는다.
    - `했습니다`보다 명사형 또는 짧은 문장을 선호한다.

    ## 금지사항

    - 커밋 메시지만으로 알 수 없는 내용을 단정하지 않는다.
    - 민감한 토큰, URL, 개인 정보는 넣지 않는다.
    """
}

private struct GuideHint: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .bold()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}


