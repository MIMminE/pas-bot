import Foundation

struct PASSettingsStore {
    let configURL: URL
    let stateURL: URL

    func load() -> PASSettings {
        PASSettings(
            slackMode: "oauth",
            slackBotToken: readConfigValue(section: "slack", key: "bot_token"),
            slackDefaultChannelID: readConfigValue(section: "slack.channels", key: "default"),
            slackTestChannelID: readConfigValue(section: "slack.channels", key: "test"),
            slackMorningChannelID: readConfigValue(section: "slack.channels", key: "morning_briefing"),
            slackEveningChannelID: readConfigValue(section: "slack.channels", key: "evening_check"),
            slackJiraChannelID: readConfigValue(section: "slack.channels", key: "jira_daily"),
            slackGitReportChannelID: readConfigValue(section: "slack.channels", key: "git_report"),
            slackGitStatusChannelID: readConfigValue(section: "slack.channels", key: "git_status"),
            slackAlertsChannelID: readConfigValue(section: "slack.channels", key: "alerts"),
            jiraBaseURL: readConfigValue(section: "jira", key: "base_url"),
            jiraEmail: readConfigValue(section: "jira", key: "email"),
            jiraApiToken: readConfigValue(section: "jira", key: "api_token"),
            jiraDefaultProject: readConfigValue(section: "jira", key: "default_project"),
            gitAuthor: readConfigValue(section: "general", key: "git_author"),
            workEndTime: readConfigValue(section: "general", key: "work_end_time"),
            cloneRoot: readConfigValue(section: "developer", key: "clone_root"),
            repoProjectPaths: Set(readRepositoryProjects().map(\.path)),
            repoProjectBaseBranches: Dictionary(
                uniqueKeysWithValues: readRepositoryProjects().map { ($0.path, $0.baseBranch) }
            ),
            openAIKey: readConfigValue(section: "openai", key: "api_key"),
            jiraDailyEnabled: readBoolConfigValue(section: "feature_groups", key: "jira", defaultValue: true),
            gitReportEnabled: readBoolConfigValue(section: "feature_groups", key: "git", defaultValue: true),
            gitStatusEnabled: readBoolConfigValue(section: "feature_groups", key: "git", defaultValue: true),
            jiraDailyScheduleEnabled: readBoolConfigValue(section: "schedules.jira_daily", key: "enabled", defaultValue: false),
            jiraDailyScheduleTime: readConfigValue(section: "schedules.jira_daily", key: "time"),
            jiraDailyCatchUp: readBoolConfigValue(section: "schedules.jira_daily", key: "catch_up_if_missed", defaultValue: true),
            gitReportScheduleEnabled: readBoolConfigValue(section: "schedules.git_report", key: "enabled", defaultValue: false),
            gitReportScheduleTime: readConfigValue(section: "schedules.git_report", key: "time"),
            gitReportCatchUp: readBoolConfigValue(section: "schedules.git_report", key: "catch_up_if_missed", defaultValue: true),
            gitStatusScheduleEnabled: readBoolConfigValue(section: "schedules.git_status", key: "enabled", defaultValue: false),
            gitStatusScheduleTime: readConfigValue(section: "schedules.git_status", key: "time"),
            gitStatusCatchUp: readBoolConfigValue(section: "schedules.git_status", key: "catch_up_if_missed", defaultValue: true),
            defaultIDEAppName: readConfigValue(section: "developer", key: "default_ide_app"),
            workCommitPreviewRows: readIntConfigValue(section: "developer", key: "work_commit_preview_rows", defaultValue: 4)
        )
    }

    func save(_ settings: PASSettings) throws {
        try writeConfig(settings)
        try markSetupCompleted()
    }

    private func markSetupCompleted() throws {
        var payload: [String: Any] = [:]
        if let data = try? Data(contentsOf: stateURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = existing
        }
        payload["version"] = payload["version"] ?? 1
        payload["updated_at"] = ISO8601DateFormatter().string(from: Date())
        payload["setup_completed"] = true
        payload["last_runs"] = payload["last_runs"] ?? [:]
        payload["issue_repositories"] = payload["issue_repositories"] ?? [:]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func readConfigValue(section: String, key: String) -> String {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return "" }
        var currentSection = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }
            guard currentSection == section, let separator = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            if name == key {
                return unquote(String(trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)))
            }
        }
        return ""
    }

    private func readBoolConfigValue(section: String, key: String, defaultValue: Bool) -> Bool {
        let value = readConfigValue(section: section, key: key)
        if value.isEmpty {
            return defaultValue
        }
        return value.lowercased() == "true"
    }

    private func readIntConfigValue(section: String, key: String, defaultValue: Int) -> Int {
        let value = readConfigValue(section: section, key: key)
        return Int(value) ?? defaultValue
    }

    private struct RepositoryProjectConfig {
        let path: String
        let baseBranch: String
    }

    private func readRepositoryProjects() -> [RepositoryProjectConfig] {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }
        var projects: [RepositoryProjectConfig] = []
        var inProject = false
        var path = ""
        var baseBranch = ""

        func flush() {
            if !path.isEmpty {
                projects.append(RepositoryProjectConfig(path: path, baseBranch: baseBranch))
            }
            path = ""
            baseBranch = ""
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[[repositories.projects]]" {
                if inProject {
                    flush()
                }
                inProject = true
                continue
            }
            if trimmed.hasPrefix("[") {
                if inProject {
                    flush()
                    inProject = false
                }
                continue
            }
            guard inProject, let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            let value = unquote(String(trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)))
            if key == "path" {
                path = value
            } else if key == "base_branch" {
                baseBranch = value
            }
        }
        if inProject {
            flush()
        }
        return projects
    }

    private func writeConfig(_ settings: PASSettings) throws {
        guard var text = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        text = replaceConfigValue(text, section: "general", key: "git_author", value: settings.gitAuthor)
        text = replaceConfigValue(text, section: "general", key: "work_end_time", value: settings.workEndTime)
        text = replaceConfigValue(text, section: "developer", key: "default_ide_app", value: settings.defaultIDEAppName)
        text = replaceConfigValue(text, section: "developer", key: "clone_root", value: settings.cloneRoot)
        text = replaceConfigIntValue(text, section: "developer", key: "work_commit_preview_rows", value: settings.workCommitPreviewRowsOrDefault)
        text = replaceConfigValue(text, section: "jira", key: "base_url", value: settings.jiraBaseURL)
        text = replaceConfigValue(text, section: "jira", key: "email", value: settings.jiraEmail)
        text = replaceConfigValue(text, section: "jira", key: "api_token", value: settings.jiraApiToken)
        text = replaceConfigValue(text, section: "jira", key: "default_project", value: settings.jiraDefaultProject)
        text = replaceConfigValue(text, section: "slack", key: "mode", value: "oauth")
        text = removeConfigValue(text, section: "slack", key: "webhook_url")
        text = replaceConfigValue(text, section: "slack", key: "bot_token", value: settings.slackBotToken)
        text = removeConfigSection(text, section: "slack.webhooks")
        text = replaceConfigValue(text, section: "slack.channels", key: "default", value: settings.slackDefaultChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "test", value: settings.slackTestChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "morning_briefing", value: settings.slackMorningChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "evening_check", value: settings.slackEveningChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "jira_daily", value: settings.slackJiraChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "git_report", value: settings.slackGitReportChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "git_status", value: settings.slackGitStatusChannelID)
        text = replaceConfigValue(text, section: "slack.channels", key: "alerts", value: settings.slackAlertsChannelID)
        text = removeConfigSection(text, section: "github")
        text = removeArraySection(text, section: "github.repositories")
        text = removeArraySection(text, section: "repositories.roots")
        text = replaceRepositoryProjects(
            text,
            projectPaths: settings.repoProjectPaths,
            baseBranches: settings.repoProjectBaseBranches
        )
        text = replaceConfigValue(text, section: "openai", key: "api_key", value: settings.openAIKey)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "jira", value: settings.jiraDailyEnabled)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "git", value: settings.gitReportEnabled || settings.gitStatusEnabled)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "routines", value: true)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "ai", value: true)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "dev_tools", value: true)
        text = replaceConfigBoolValue(text, section: "feature_groups", key: "notifications", value: true)
        text = replaceConfigBoolValue(text, section: "schedules.jira_daily", key: "enabled", value: settings.jiraDailyScheduleEnabled)
        text = replaceConfigValue(text, section: "schedules.jira_daily", key: "time", value: settings.jiraDailyScheduleTimeOrDefault)
        text = replaceConfigBoolValue(text, section: "schedules.jira_daily", key: "catch_up_if_missed", value: settings.jiraDailyCatchUp)
        text = replaceConfigBoolValue(text, section: "schedules.git_report", key: "enabled", value: settings.gitReportScheduleEnabled)
        text = replaceConfigValue(text, section: "schedules.git_report", key: "time", value: settings.gitReportScheduleTimeOrDefault)
        text = replaceConfigBoolValue(text, section: "schedules.git_report", key: "catch_up_if_missed", value: settings.gitReportCatchUp)
        text = replaceConfigBoolValue(text, section: "schedules.git_status", key: "enabled", value: settings.gitStatusScheduleEnabled)
        text = replaceConfigValue(text, section: "schedules.git_status", key: "time", value: settings.gitStatusScheduleTimeOrDefault)
        text = replaceConfigBoolValue(text, section: "schedules.git_status", key: "catch_up_if_missed", value: settings.gitStatusCatchUp)
        try text.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func replaceConfigValue(_ text: String, section: String, key: String, value: String) -> String {
        replaceConfigLine(text, section: section, key: key, renderedValue: "\"\(escapeToml(value))\"")
    }

    private func replaceConfigBoolValue(_ text: String, section: String, key: String, value: Bool) -> String {
        replaceConfigLine(text, section: section, key: key, renderedValue: value ? "true" : "false")
    }

    private func replaceConfigIntValue(_ text: String, section: String, key: String, value: Int) -> String {
        replaceConfigLine(text, section: section, key: key, renderedValue: "\(value)")
    }

    private func removeConfigValue(_ text: String, section: String, key: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var currentSection = ""
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                return false
            }
            guard currentSection == section, let separator = trimmed.firstIndex(of: "=") else { return false }
            let name = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            return name == key
        }
        return lines.joined(separator: "\n")
    }

    private func removeConfigSection(_ text: String, section: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var isRemoving = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                isRemoving = trimmed == "[\(section)]"
                if isRemoving {
                    continue
                }
            }
            if !isRemoving {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    private func removeArraySection(_ text: String, section: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var isRemoving = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]") {
                isRemoving = trimmed == "[[\(section)]]"
                if isRemoving {
                    continue
                }
            } else if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                isRemoving = false
            }
            if !isRemoving {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    private func replaceRepositoryProjects(_ text: String, projectPaths: Set<String>, baseBranches: [String: String]) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[[repositories.projects]]" {
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix("[") {
                        break
                    }
                    index += 1
                }
                continue
            }
            output.append(lines[index])
            index += 1
        }

        let rendered = projectPaths.sorted().compactMap { rawPath -> String? in
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            let baseBranch = (baseBranches[path] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let baseLine = baseBranch.isEmpty ? "" : "\nbase_branch = \"\(escapeToml(baseBranch))\""
            return """

            [[repositories.projects]]
            path = "\(escapeToml(path))"\(baseLine)
            """
        }
        if !rendered.isEmpty {
            if output.last?.isEmpty == false {
                output.append("")
            }
            output.append(rendered.joined(separator: "\n"))
        }
        return output.joined(separator: "\n")
    }

    private func replaceConfigLine(_ text: String, section: String, key: String, renderedValue: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var currentSection = ""
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }
            guard currentSection == section, let separator = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            if name == key {
                lines[index] = "\(key) = \(renderedValue)"
                return lines.joined(separator: "\n")
            }
        }
        if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("[\(section)]")
        }
        if let sectionIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) {
            let insertIndex = sectionEndIndex(in: lines, sectionStartIndex: sectionIndex)
            lines.insert("\(key) = \(renderedValue)", at: insertIndex)
        }
        return lines.joined(separator: "\n")
    }

    private func sectionEndIndex(in lines: [String], sectionStartIndex: Int) -> Int {
        var index = sectionStartIndex + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                break
            }
            index += 1
        }
        return index
    }

    private func unquote(_ value: String) -> String {
        if value.count >= 2 && value.first == "\"" && value.last == "\"" {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private func escapeToml(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
