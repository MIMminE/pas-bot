import SwiftUI

struct StatusPill: View {
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

struct DashboardPanel<Content: View>: View {
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

struct DashboardButton: View {
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

struct CommandGroup<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let content: Content

    init(title: String, subtitle: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.50))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45))
        )
    }
}

struct RepositoryDashboardRow: View {
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

                    RepoGuidanceView(
                        title: guidanceTitle,
                        message: guidanceMessage,
                        color: statusColor
                    )
                }

                Spacer()

                HStack(spacing: 6) {
                    RepoIconButton(title: "오늘 커밋", systemImage: "list.bullet.rectangle", action: onCommits)
                        .disabled(isRunning)
                    RepoIconButton(title: "원격 확인", systemImage: "arrow.triangle.2.circlepath", action: onFetch)
                        .disabled(isRunning)
                    RepoIconButton(title: "최신화", systemImage: "arrow.down", action: onPull)
                        .disabled(isRunning || !repo.canFastForward || repo.dirtyCount > 0)
                    RepoIconButton(title: "재정렬", systemImage: "arrow.triangle.branch", action: onRebase)
                        .disabled(isRunning || !repo.needsUpdate || repo.dirtyCount > 0)
                    RepoIconButton(title: "올리기", systemImage: "arrow.up", action: onPush)
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

    private var guidanceTitle: String {
        if repo.dirtyCount > 0 && repo.needsUpdate {
            return "판단 필요"
        }
        if repo.dirtyCount > 0 {
            return "로컬 변경 정리"
        }
        if repo.needsRebase {
            return "rebase 권장"
        }
        if repo.canFastForward {
            return "pull 가능"
        }
        if (repo.ahead ?? 0) > 0 {
            return "push 가능"
        }
        return "정상"
    }

    private var guidanceMessage: String {
        let ahead = repo.ahead ?? 0
        let behind = repo.behind ?? 0
        if repo.dirtyCount > 0 && behind > 0 {
            return "1. 변경사항 commit/stash -> 2. Fetch -> 3. \(ahead > 0 ? "Rebase" : "Pull") -> 4. 테스트 후 Push"
        }
        if repo.dirtyCount > 0 {
            return ahead > 0
                ? "1. 변경사항 commit/stash -> 2. 테스트 -> 3. Push"
                : "1. 변경사항 commit/stash -> 2. 필요한 경우 Fetch로 원격 상태 확인"
        }
        if behind > 0 && ahead > 0 {
            return "1. Fetch -> 2. Rebase -> 3. 충돌 해결/테스트 -> 4. Push"
        }
        if behind > 0 {
            return "1. Fetch -> 2. Pull로 최신화 -> 3. 테스트"
        }
        if ahead > 0 {
            return "1. 원격 상태 확인 -> 2. 테스트 -> 3. Push"
        }
        return "추가 조치 없이 작업을 시작해도 됩니다."
    }
}

struct RepoGuidanceView: View {
    let title: String
    let message: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct RepoIconButton: View {
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
            .frame(width: 68, height: 42)
        }
        .buttonStyle(.bordered)
        .help(title)
    }
}

struct RepoStatusBadge: View {
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

struct EmptyDashboardState: View {
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

struct WorkNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let succeeded: Bool
}

struct WorkNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    let notice: WorkNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(noticeColor.opacity(0.15))
                    Image(systemName: notice.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(noticeColor)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title)
                        .font(.title3)
                        .bold()
                    Text(notice.succeeded ? "작업이 완료되었습니다." : "작업을 완료하지 못했습니다.")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ResultOutputView(output: notice.message, maxHeight: 320)
                .frame(minHeight: 150)

            HStack {
                Spacer()
                Button("닫기") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private var noticeColor: Color {
        notice.succeeded ? .green : .red
    }
}

struct RepoAction: Identifiable {
    let id = UUID()
    let repo: LocalRepositoryOption
    let mode: String
}
