import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"

    var id: String { rawValue }

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("ja") ? .japanese : .english
    }

    var shortLabel: String {
        switch self {
        case .japanese: "日本語"
        case .english: "English"
        }
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .systemDefault
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

enum L10n {
    static func reconnectHub(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "Hubに再接続"
        case .english: "Reconnect Hub"
        }
    }

    static func start(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "開始"
        case .english: "Start"
        }
    }

    static func stop(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "停止"
        case .english: "Stop"
        }
    }

    static func theme(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "テーマ"
        case .english: "Theme"
        }
    }

    static func viewMode(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "表示モード"
        case .english: "View mode"
        }
    }

    static func export(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "会話をエクスポート"
        case .english: "Export conversation"
        }
    }

    static func setup(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "セットアップ"
        case .english: "Setup"
        }
    }

    static func setupTitle(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "クイックセットアップ"
        case .english: "Quick setup"
        }
    }

    static func setupIntro(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "登録コマンドとロールプロンプトをコピーして各アプリに貼り付けます。コマンドにはトークンが含まれます—共有しないでください。"
        case .english: "Copy the registration commands and role prompts into each app. The commands contain tokens — do not share them."
        }
    }

    static func setupUnavailable(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "Hub を開始すると登録コマンドを取得できます。"
        case .english: "Start the Hub to fetch the registration commands."
        }
    }

    static func copyRegistration(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "登録コマンドをコピー"
        case .english: "Copy registration command"
        }
    }

    static func copyPrompt(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ロールプロンプトをコピー"
        case .english: "Copy role prompt"
        }
    }

    static func registrationWord(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "登録コマンド"
        case .english: "registration command"
        }
    }

    static func promptWord(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "プロンプト"
        case .english: "prompt"
        }
    }

    static func copied(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "コピーしました"
        case .english: "Copied"
        }
    }

    static func exportFailed(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "エクスポートに失敗しました。"
        case .english: "Export failed."
        }
    }

    static func language(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "言語"
        case .english: "Language"
        }
    }

    static func roleAssignment(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ロール割当"
        case .english: "Role Assignment"
        }
    }

    static func applyRoles(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ロールを反映"
        case .english: "Apply Roles"
        }
    }

    static func applyRolesAccessibility(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ロールをHubに反映"
        case .english: "Apply roles to the Hub"
        }
    }

    static func session(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "セッション"
        case .english: "Session"
        }
    }

    static func repository(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "リポジトリ"
        case .english: "Repository"
        }
    }

    static func branch(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ブランチ"
        case .english: "Branch"
        }
    }

    static func role(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ロール"
        case .english: "Role"
        }
    }

    static func task(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "タスク"
        case .english: "Task"
        }
    }

    static func stopped(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "停止"
        case .english: "Stopped"
        }
    }

    static func queued(_ language: AppLanguage, count: Int) -> String {
        switch language {
        case .japanese: "受信 \(count)"
        case .english: "Queued \(count)"
        }
    }

    static func completed(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "完了"
        case .english: "Done"
        }
    }

    static func waiting(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "待機中"
        case .english: "Waiting"
        }
    }

    static func possibleStall(_ language: AppLanguage, seconds: Int) -> String {
        switch language {
        case .japanese: "停滞の可能性（最後の活動から \(seconds) 秒）"
        case .english: "Possible stall (\(seconds)s since last activity)"
        }
    }

    static func roleInputError(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ロール入力エラー"
        case .english: "Role input error"
        }
    }

    static func rolesUpdatedRemotely(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ロールがリモートで更新されました。編集中の内容は保持しています。"
        case .english: "Roles were updated remotely. Your edits are preserved."
        }
    }

    static func discardLocalEdits(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "編集を破棄して反映"
        case .english: "Discard edits and adopt"
        }
    }

    static func emptyLog(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "Hubイベントがここに表示されます"
        case .english: "Hub events will appear here"
        }
    }

    static func onboardingTitle(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "Duet へようこそ"
        case .english: "Welcome to Duet"
        }
    }

    static func onboardingStep1(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "両エージェントの MCP エンドポイントを登録する"
        case .english: "Register both agents' MCP endpoints"
        }
    }

    static func onboardingStep2(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "左パネルでロールを割り当てる"
        case .english: "Assign roles in the sidebar"
        }
    }

    static func onboardingStep3(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "各アプリにロールプロンプトを貼り付ける"
        case .english: "Paste the role prompts into each app"
        }
    }

    static func onboardingStep4(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "「開始」を押して対話を始める"
        case .english: "Press Start to begin the exchange"
        }
    }

    static func onboardingHint(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ツールバーの「セットアップ」から登録コマンドとプロンプトをコピーできます。"
        case .english: "Use Setup in the toolbar to copy the registration commands and prompts."
        }
    }

    static func jumpToLatest(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "最新へ"
        case .english: "Jump to latest"
        }
    }

    static func searchPlaceholder(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "会話を検索..."
        case .english: "Search conversation..."
        }
    }

    static func clearSearch(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "検索をクリア"
        case .english: "Clear search"
        }
    }

    static func humanFilter(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "人間"
        case .english: "Human"
        }
    }

    static func noResults(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "一致するメッセージがありません"
        case .english: "No matching messages"
        }
    }

    static func jumpToLatestCount(_ language: AppLanguage, count: Int) -> String {
        switch language {
        case .japanese: "最新へ（\(count)件）"
        case .english: "Jump to latest (\(count))"
        }
    }

    static func humanLabel(_ language: AppLanguage, recipient: String) -> String {
        switch language {
        case .japanese: "あなた ▸ \(recipient)"
        case .english: "You ▸ \(recipient)"
        }
    }

    static func interruptTarget(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "割り込み宛先"
        case .english: "Interrupt Target"
        }
    }

    static func recipient(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "宛先"
        case .english: "Recipient"
        }
    }

    static func interruptPlaceholder(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "会話に割り込んで指示を出す...  (例: このPRにテストも含めて)"
        case .english: "Interrupt with instructions...  (e.g. include tests in this PR)"
        }
    }

    static func interruptMessageAccessibility(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "割り込みメッセージ"
        case .english: "Interrupt message"
        }
    }

    static func sending(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "送信中"
        case .english: "Sending"
        }
    }

    static func interrupt(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "割り込む"
        case .english: "Interrupt"
        }
    }

    static func sendInterruptAccessibility(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "人間の割り込みメッセージを送信"
        case .english: "Send human interrupt message"
        }
    }

    static func unknownHubError(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "Hubが不明なエラーを返しました。"
        case .english: "Hub returned an unknown error."
        }
    }

    static func roleRequired(agent: String, language: AppLanguage) -> String {
        switch language {
        case .japanese: "\(agent) のロールは必須です。"
        case .english: "\(agent) role is required."
        }
    }

    static func roleTooLong(agent: String, max: Int, language: AppLanguage) -> String {
        switch language {
        case .japanese: "\(agent) のロールは \(max) 文字以内にしてください。"
        case .english: "\(agent) role must be \(max) characters or fewer."
        }
    }

    static func taskTooLong(agent: String, max: Int, language: AppLanguage) -> String {
        switch language {
        case .japanese: "\(agent) のタスクは \(max) 文字以内にしてください。"
        case .english: "\(agent) task must be \(max) characters or fewer."
        }
    }

    // MARK: - Transcript states
    //
    // Each empty state names the situation the user is actually in and what to
    // do next. One generic "no messages" line for every case is exactly the
    // unhappy-path gap this redesign set out to close.

    static func toHuman(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "→ 人間へ"
        case .english: "to human"
        }
    }

    static func emptyLogDetail(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "エージェントが調整メッセージを送るとここに流れます。"
        case .english: "Coordination messages appear here as the agents exchange them."
        }
    }

    static func emptyDisconnectedTitle(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "Hub に接続していません"
        case .english: "Not connected to the Hub"
        }
    }

    static func emptyDisconnectedDetail(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "Hub が起動していないか、接続に失敗しています。⌘⇧R で再接続できます。"
        case .english: "The Hub is not running or the connection failed. Press ⌘⇧R to reconnect."
        }
    }

    static func emptyStoppedTitle(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ルームは停止中です"
        case .english: "The room is stopped"
        }
    }

    static func emptyStoppedDetail(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "ツールバーの開始を押すと、エージェントのメッセージを受け付けます。"
        case .english: "Press Start in the toolbar to begin accepting agent messages."
        }
    }

    static func emptyNoAgentsTitle(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "エージェントがまだ接続していません"
        case .english: "No agent has connected yet"
        }
    }

    static func emptyNoAgentsDetail(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "Claude Code と Codex に Duet の MCP を登録し、プロンプトを貼り付けてください。接続すると右のインスペクタが緑になります。"
        case .english: "Register Duet's MCP endpoints in Claude Code and Codex, then paste the prompts. The inspector turns green once they connect."
        }
    }

    // MARK: - Inspector

    static func repository(_ language: AppLanguage, changedFiles: Int) -> String {
        switch language {
        case .japanese: "変更 \(changedFiles) ファイル"
        case .english: changedFiles == 1 ? "1 changed file" : "\(changedFiles) changed files"
        }
    }

    static func repoUnavailable(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "Git 情報を取得できません"
        case .english: "Git status unavailable"
        }
    }

    static func agents(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "エージェント"
        case .english: "Agents"
        }
    }

    static func connected(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "接続済み"
        case .english: "Connected"
        }
    }

    static func notConnected(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "未接続"
        case .english: "Not connected"
        }
    }

    static func diagnostics(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "診断"
        case .english: "Diagnostics"
        }
    }

    // MARK: - Sessions

    static func sessions(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "セッション"
        case .english: "Sessions"
        }
    }

    static func liveSession(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "実行中のセッション"
        case .english: "Live session"
        }
    }

    static func newSession(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "新しいセッション"
        case .english: "New Session"
        }
    }

    static func archivedBannerTitle(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "過去のセッションを表示しています"
        case .english: "Viewing an archived session"
        }
    }

    static func backToLive(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "実行中に戻る"
        case .english: "Back to Live"
        }
    }

    static func messageCount(_ language: AppLanguage, count: Int) -> String {
        switch language {
        case .japanese: "\(count) 件"
        case .english: count == 1 ? "1 message" : "\(count) messages"
        }
    }

    static func noSessions(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "まだ記録がありません"
        case .english: "No sessions recorded yet"
        }
    }

    static func toggleInspector(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "インスペクタを表示"
        case .english: "Toggle Inspector"
        }
    }

    static func humanShort(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "人間"
        case .english: "human"
        }
    }

    static func noSearchResults(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "該当するメッセージがありません"
        case .english: "No matching messages"
        }
    }

    static func noSearchResultsDetail(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "検索語を変えるか、送信者フィルタを解除してください。"
        case .english: "Try a different search, or clear the sender filter."
        }
    }

    static func filter(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "送信者で絞り込む"
        case .english: "Filter by sender"
        }
    }

    static func clearFilter(_ language: AppLanguage) -> String {
        switch language {
        case .japanese: "絞り込みを解除"
        case .english: "Clear filter"
        }
    }
}
