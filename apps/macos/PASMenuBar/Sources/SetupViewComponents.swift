import SwiftUI

struct SettingsTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct SettingsSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct GuideButton: Hashable {
    let title: String
    let url: String
}

struct SettingsSection<Content: View>: View {
    let title: String
    let summary: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        summary: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct GuideBox: View {
    let title: String
    let lines: [String]
    let buttons: [GuideButton]
    let runner: PASRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .bold()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text("- \(line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                ForEach(buttons, id: \.self) { item in
                    Button(item.title) {
                        runner.openExternalURL(item.url)
                    }
                }
                Spacer()
            }
            .padding(.top, 6)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ChannelIdField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        SettingsTextField(
            title: title,
            placeholder: "C0123456789",
            text: $text
        )
    }
}

struct ChannelPicker: View {
    let title: String
    let channels: [SlackChannel]
    @Binding var selection: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                Picker(title, selection: $selection) {
                    Text("기본 채널 사용").tag("")
                    ForEach(channels) { channel in
                        Text(channel.label).tag(channel.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct LocalRepositoryProjectPicker: View {
    let repositories: [LocalRepositoryOption]
    @Binding var selectedPaths: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("관리 repository")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Button("전체 선택") {
                    selectedPaths = Set(repositories.map(\.path))
                }

                Button("전체 해제") {
                    selectedPaths.removeAll()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(repositories) { repo in
                    Toggle(isOn: Binding(
                        get: { selectedPaths.contains(repo.path) },
                        set: { isSelected in
                            if isSelected {
                                selectedPaths.insert(repo.path)
                            } else {
                                selectedPaths.remove(repo.path)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(repo.name)
                                    .font(.body)
                                Text(repo.branch)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                if repo.dirtyCount > 0 {
                                    Text("변경 \(repo.dirtyCount)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                            }

                            Text("\(repo.syncLabel) | \(repo.path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

struct RemoteRepositoryPicker: View {
    let repositories: [GitHubRemoteRepositoryOption]
    @Binding var selectedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("가져올 GitHub repository")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Button("전체 선택") {
                    selectedIDs = Set(repositories.map(\.id))
                }

                Button("전체 해제") {
                    selectedIDs.removeAll()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(repositories) { repo in
                        Toggle(isOn: Binding(
                            get: { selectedIDs.contains(repo.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedIDs.insert(repo.id)
                                } else {
                                    selectedIDs.remove(repo.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(repo.nameWithOwner)
                                        .font(.body)
                                    Text(repo.visibility)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(nsColor: .textBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    if !repo.defaultBranch.isEmpty {
                                        Text(repo.defaultBranch)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }

                                Text(repo.sshURL.isEmpty ? repo.webURL : repo.sshURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }
}

struct ScheduleRow: View {
    let title: String
    @Binding var featureEnabled: Bool
    @Binding var scheduleEnabled: Bool
    @Binding var time: String
    @Binding var catchUp: Bool
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: $featureEnabled)
                .font(.headline)

            HStack(spacing: 12) {
                Toggle("자동 전송", isOn: $scheduleEnabled)
                    .disabled(!featureEnabled)

                TextField(placeholder, text: $time)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)
                    .disabled(!featureEnabled || !scheduleEnabled)

                Toggle("놓친 경우 켜진 시점에 1회 전송", isOn: $catchUp)
                    .disabled(!featureEnabled || !scheduleEnabled)

                Spacer()
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
