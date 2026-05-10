import SwiftUI

struct OutputView: View {
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("실행 결과")
                .font(.headline)

            ResultOutputView(output: output)
                .frame(minHeight: 360)
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 420)
    }
}

struct ResultOutputView: View {
    let output: String
    var maxHeight: CGFloat?

    private var rows: [ResultOutputRow] {
        ResultOutputRow.parse(output)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if rows.isEmpty {
                    ResultOutputLineView(row: .emptyMessage)
                } else {
                    ForEach(rows) { row in
                        ResultOutputLineView(row: row)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: maxHeight)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7))
        )
    }
}

private struct ResultOutputLineView: View {
    let row: ResultOutputRow

    var body: some View {
        switch row.kind {
        case .spacer:
            Rectangle()
                .fill(Color.clear)
                .frame(height: 4)
        case .heading:
            Text(row.text)
                .font(.headline)
                .textSelection(.enabled)
                .padding(.top, 4)
        case .status:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: row.statusIcon)
                    .foregroundStyle(row.tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.statusTitle)
                        .font(.subheadline)
                        .bold()
                    if !row.statusDetail.isEmpty {
                        Text(row.statusDetail)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(row.tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: 5, height: 5)
                    .padding(.top, 7)
                Text(row.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .plain:
            Text(row.text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 1)
        }
    }
}

private struct ResultOutputRow: Identifiable {
    enum Kind {
        case heading
        case status
        case bullet
        case plain
        case spacer
    }

    let id = UUID()
    let kind: Kind
    let text: String

    static let emptyMessage = ResultOutputRow(kind: .plain, text: "출력 없음")

    static func parse(_ output: String) -> [ResultOutputRow] {
        output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    return ResultOutputRow(kind: .spacer, text: "")
                }
                if line.hasPrefix("[OK]") || line.hasPrefix("[WARN]") || line.hasPrefix("[FAIL]") {
                    return ResultOutputRow(kind: .status, text: line)
                }
                if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    return ResultOutputRow(kind: .bullet, text: String(line.dropFirst(2)))
                }
                if looksLikeHeading(line) {
                    return ResultOutputRow(kind: .heading, text: line)
                }
                return ResultOutputRow(kind: .plain, text: line)
            }
    }

    private static func looksLikeHeading(_ line: String) -> Bool {
        if line.count > 42 {
            return false
        }
        if line.contains(":") || line.contains("|") || line.contains("\t") {
            return false
        }
        return !line.hasPrefix("[") && !line.hasPrefix("{")
    }

    var tint: Color {
        if text.hasPrefix("[OK]") {
            return .green
        }
        if text.hasPrefix("[FAIL]") {
            return .red
        }
        if text.hasPrefix("[WARN]") {
            return .orange
        }
        return .secondary
    }

    var statusIcon: String {
        if text.hasPrefix("[OK]") {
            return "checkmark.circle.fill"
        }
        if text.hasPrefix("[FAIL]") {
            return "xmark.octagon.fill"
        }
        if text.hasPrefix("[WARN]") {
            return "exclamationmark.triangle.fill"
        }
        return "info.circle.fill"
    }

    var statusTitle: String {
        let cleaned = text
            .replacingOccurrences(of: "[OK]", with: "정상")
            .replacingOccurrences(of: "[WARN]", with: "확인 필요")
            .replacingOccurrences(of: "[FAIL]", with: "실패")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.components(separatedBy: ":").first ?? cleaned
    }

    var statusDetail: String {
        let parts = text.components(separatedBy: ":")
        guard parts.count > 1 else { return "" }
        return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
    }
}

