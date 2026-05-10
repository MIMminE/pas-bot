import SwiftUI

struct PASCommandResult: Sendable {
    let succeeded: Bool
    let output: String
    let summary: String

    var displayText: String {
        let value = output.isEmpty ? summary : output
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "출력 없음" : value
    }
}

struct PASSettings {
    var slackMode: String
    var slackBotToken: String
    var slackDefaultChannelID: String
    var slackTestChannelID: String
    var slackMorningChannelID: String
    var slackEveningChannelID: String
    var slackJiraChannelID: String
    var slackGitReportChannelID: String
    var slackGitStatusChannelID: String
    var slackAlertsChannelID: String
    var jiraBaseURL: String
    var jiraEmail: String
    var jiraApiToken: String
    var jiraDefaultProject: String
    var gitAuthor: String
    var workEndTime: String
    var repoRoots: [LocalRepositoryRoot]
    var repoProjectPaths: Set<String>
    var openAIKey: String
    var jiraDailyEnabled: Bool
    var gitReportEnabled: Bool
    var gitStatusEnabled: Bool
    var jiraDailyScheduleEnabled: Bool
    var jiraDailyScheduleTime: String
    var jiraDailyCatchUp: Bool
    var gitReportScheduleEnabled: Bool
    var gitReportScheduleTime: String
    var gitReportCatchUp: Bool
    var gitStatusScheduleEnabled: Bool
    var gitStatusScheduleTime: String
    var gitStatusCatchUp: Bool

    var testChannelID: String {
        slackTestChannelID.isEmpty ? slackDefaultChannelID : slackTestChannelID
    }

    var jiraChannelID: String {
        slackJiraChannelID.isEmpty ? slackDefaultChannelID : slackJiraChannelID
    }

    var usesSlackOAuth: Bool {
        slackMode == "oauth"
    }

    var isReadyForBasicTests: Bool {
        slackJiraReady
            && jiraBaseURL.hasPrefix("https://")
            && jiraEmail.contains("@")
            && !jiraApiToken.isEmpty
            && !jiraDefaultProject.isEmpty
    }

    var isReadyForSlackTest: Bool {
        !slackBotToken.isEmpty && !testChannelID.isEmpty
    }

    private var slackJiraReady: Bool {
        !slackBotToken.isEmpty && !jiraChannelID.isEmpty
    }

    var jiraDailyScheduleTimeOrDefault: String {
        jiraDailyScheduleTime.isEmpty ? "09:00" : jiraDailyScheduleTime
    }

    var gitReportScheduleTimeOrDefault: String {
        gitReportScheduleTime.isEmpty ? "18:30" : gitReportScheduleTime
    }

    var gitStatusScheduleTimeOrDefault: String {
        gitStatusScheduleTime.isEmpty ? "09:10" : gitStatusScheduleTime
    }
}

struct SlackChannel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isPrivate: Bool

    var label: String {
        "#\(name)\(isPrivate ? " (private)" : "")"
    }
}

struct LocalRepositoryRoot: Identifiable, Hashable, Sendable {
    var path: String
    var recursive: Bool

    var id: String {
        path
    }
}

struct LocalRepositoryOption: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let branch: String
    let ahead: Int?
    let behind: Int?
    let dirtyCount: Int

    var id: String {
        path
    }

    var syncLabel: String {
        if let ahead, let behind {
            if ahead > 0 && behind > 0 {
                return "rebase/merge 확인: ahead \(ahead), behind \(behind)"
            }
            if behind > 0 {
                return "rebase/pull 필요: behind \(behind)"
            }
            if ahead > 0 {
                return "push 필요: ahead \(ahead)"
            }
            return "동기화됨"
        }
        return "upstream 없음"
    }

    var needsUpdate: Bool {
        (behind ?? 0) > 0
    }

    var canFastForward: Bool {
        (behind ?? 0) > 0 && (ahead ?? 0) == 0
    }

    var needsRebase: Bool {
        (behind ?? 0) > 0 && (ahead ?? 0) > 0
    }
}

struct GitHubRemoteRepositoryOption: Identifiable, Hashable, Sendable {
    let nameWithOwner: String
    let sshURL: String
    let webURL: String
    let visibility: String
    let defaultBranch: String

    var id: String {
        nameWithOwner
    }

    var shortName: String {
        nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner
    }

    var cloneSource: String {
        sshURL.isEmpty ? nameWithOwner : sshURL
    }
}

