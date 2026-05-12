import SwiftUI

struct JiraListItem: Identifiable {
    let key: String
    let title: String
    let detail: String
    let link: String?

    var id: String {
        "\(key)-\(title)"
    }

    var scheduleText: String {
        detail
            .components(separatedBy: .newlines)
            .first { $0.contains("등록:") || $0.contains("마감:") || $0.contains("갱신:") } ?? ""
    }

    var statusText: String {
        metaValue("상태")
    }

    var priorityText: String {
        metaValue("우선순위")
    }

    var assigneeText: String {
        metaValue("담당")
    }

    var createdText: String {
        metaValue("등록")
    }

    var updatedText: String {
        metaValue("갱신")
    }

    var dueText: String {
        metaValue("마감")
    }

    var bodyText: String {
        detail
            .components(separatedBy: .newlines)
            .first { $0.hasPrefix("내용:") }?
            .replacingOccurrences(of: "내용:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func metaValue(_ name: String) -> String {
        guard let line = detail.components(separatedBy: .newlines).first(where: { $0.contains("\(name):") }) else {
            return "-"
        }
        let parts = line.components(separatedBy: "|")
        guard let match = parts.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("\(name):") }) else {
            return "-"
        }
        let value = match
            .replacingOccurrences(of: "\(name):", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "-" : value
    }
}

struct JiraFlowItem: Identifiable {
    let key: String
    let title: String
    let status: String
    let reporter: String
    let assignee: String
    let created: String
    let updated: String
    let due: String
    let issueType: String
    let project: String
    let link: String

    var id: String {
        "\(key)-\(updated)"
    }

    var isDone: Bool {
        let value = status.lowercased()
        return value.contains("done") || value.contains("complete") || value.contains("완료") || value.contains("배포")
    }
}

struct JiraIssueRow: View {
    let item: JiraListItem
    let openLink: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.key)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(item.title.isEmpty ? "제목 없음" : item.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            if item.link != nil {
                Button(action: openLink) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Jira에서 열기")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6))
        )
    }
}

struct JiraQuickCreateSheet: View {
    @Binding var summary: String
    @Binding var description: String
    @Binding var issueType: String
    @Binding var assignee: String
    @Binding var priority: String
    @Binding var dueDate: String
    @Binding var labels: String
    let isRunning: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void

    private let issueTypes = ["Task", "Bug", "Story", "Sub-task"]
    private let priorities = ["", "Highest", "High", "Medium", "Low", "Lowest"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "plus.app.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Jira 일감 만들기")
                        .font(.title3.weight(.semibold))
                    Text("제목과 담당자만으로 빠르게 만들고, 필요한 필드는 선택으로 추가합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("제목", text: $summary)
                    .textFieldStyle(.roundedBorder)

                TextField("담당자 이메일, accountId 또는 검색어", text: $assignee)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Picker("타입", selection: $issueType) {
                        ForEach(issueTypes, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Picker("우선순위", selection: $priority) {
                        ForEach(priorities, id: \.self) { item in
                            Text(item.isEmpty ? "우선순위 없음" : item).tag(item)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 10) {
                    TextField("마감일 YYYY-MM-DD", text: $dueDate)
                        .textFieldStyle(.roundedBorder)
                    TextField("라벨: web,urgent", text: $labels)
                        .textFieldStyle(.roundedBorder)
                }

                TextEditor(text: $description)
                    .font(.body)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.55))
                    )
            }

            HStack {
                Text("프로젝트는 현재 설정의 기본 Jira 프로젝트를 사용합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("취소", action: onCancel)
                    .disabled(isRunning)
                Button(isRunning ? "생성 중..." : "생성") {
                    onCreate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
