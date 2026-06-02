# CLAUDE.md — Duet

> このファイルはDuetリポジトリのルートに置く。Claude/Codex が毎セッションで参照する単一の正典。
> 迷ったらこの文書が優先。詳細なMCPバス設計は `docs/SPEC.md`を参照。
> **重要な改訂**: SPEC内で「GUI = Post-MVP」と書いた箇所は無効。**GUIは本製品の中核であり Phase 2** に置く。

---

## 1. これは何か

Duet は **macOS専用のGUI OSS**。1つのウィンドウを用意し、そこで **Codex.app** と
**Claude Desktop内蔵のClaude Code** が会話・相互レビューする様子をライブ表示し、人間が途中で
ロールを割り当てたり指示を割り込ませたりできる。エージェント本体は各公式アプリのまま（改造しない）。
Duetは「調整・観察・介入のための窓」であって、エージェントを画面操作でいじるものではない。

ゴール体験:
- 人間が「Claude=実装役 / Codex=レビュー役」のようにロールを割り当てる。
- 2エージェントが共有リポジトリ上で実装→レビュー→修正を自律で往復する。
- その対話がDuetのウィンドウにリアルタイムで流れる。
- 人間がいつでも割り込んでメッセージや指示を注入できる。
- レビューだけでなく、三目並べ等の自由対話モードもできる（同じバスでメッセージ交換するだけ）。

## 2. 譲れない原則（HARD RULES）

1. **エージェント本体はCLIでもSDKでもなく公式デスクトップアプリ**。CodexはCodex.app、ClaudeはClaude
   Desktopの中のClaude Code。ここを取り違えない。
2. **コードはOCR/チャットに載せない**。2エージェントは同じリポジトリ（同じファイルシステム）を共有し、
   コードはディスク上の実ファイルを各自のファイルツールで直接読み書きする。バス／OCRを流れるのは
   「調整メッセージ（自然言語）」だけ。レビューは相手の実ファイルを読んで行う。
3. **出力の取り出しはMCPツール経由が主軸、OCRは保険**（ground-truth・取りこぼし回収）。
   画面の応答テキストをスクレイピングして相手に渡す設計にはしない（AXで塞がれており壊れる）。
4. **速度は問わない**。安全・正確が最優先。ロングポーリングの待ち時間は許容する。
5. **Mac専用**。Windows/Linux対応のための抽象化に労力を割かない。

## 3. アーキテクチャ（GUI-first）

```
┌────────────────────────┐        ┌────────────────────────┐
│ Claude Desktop          │        │ Codex.app               │
│ (Claude Code) MCP client│        │ MCP client              │
└──────────┬──────────────┘        └──────────┬──────────────┘
           │ HTTP MCP /claude                  │ HTTP MCP /codex
           └───────────────┬───────────────────┘
                           ▼
              ┌─────────────────────────────┐   control WebSocket   ┌─────────────────────────┐
              │ Hub (TypeScript / Node)      │◀────────────────────▶│ Duet.app (Swift/SwiftUI) │
              │ - MCP server (/claude /codex)│   events ▲ commands  │ ← これがユーザーが起動する製品 │
              │ - message bus + roles + log  │                      │ - ライブ対話ログ表示        │
              │ - control WS (/control)      │                      │ - ロール割当UI            │
              └─────────────────────────────┘                      │ - 人間メッセージ注入        │
                           ▲ 子プロセスとして起動                      │ - OCR(ScreenCaptureKit+Vision)│
                           └──────────────────────────────────────── │ - (後)起床/セッション更新   │
                                                                     └─────────────────────────┘
```

- **Duet.app（Swift/SwiftUI）= 製品。ユーザーが起動するのはこれ**。起動時に Hub を子プロセスとして
  立ち上げ、control WebSocket で繋ぎ、ライブ表示・ロール割当・人間注入を行う。Phase 3 以降のOCRもここに持つ。
- **Hub（TypeScript/Node）= メッセージバス＋MCPサーバー**。Duet.appが起動・監視・終了させる。
  公式2アプリはHubのHTTP MCPエンドポイント(`/claude`,`/codex`)に繋ぐ。
- Node依存は許容（開発者向けツールのため）。将来 all-Swift（swift-sdk）に寄せる選択肢はあるが今はしない。

### Hub の責務
- MCPツール: `get_briefing` / `send` / `await_reply`（詳細は §5 と docs/SPEC.md）。
- 共有状態: エージェントごとの受信キュー、ロール、全文トランスクリプト。
- control WS(`/control`): 全ルームイベント（メッセージ・ロール変更・状態）をGUIへpush、
  GUIからのコマンド（ロール設定・人間メッセージ注入・開始/停止）を受ける。
- 人間注入: GUIから来たメッセージは対象エージェントのキューに入れ、`from:"human"` として
  次の `await_reply` で配送する。

### Duet.app の責務
- control WS でHubのイベントをSwiftUIに反映（対話ログのライブ表示）。
- ロール割当パネル、人間メッセージ入力ボックス、開始/停止、状態表示。
- Phase 3 以降のOCR: ScreenCaptureKit でCodexとClaudeのウィンドウを撮影 → Vision でOCR → Hubへ送りログ化（保険）。
- Hubの子プロセス管理（起動・死活監視・終了）。

## 4. リポジトリ構成

```
duet/
  CLAUDE.md
  docs/SPEC.md                  # MCPバスの詳細仕様
  hub/                          # TypeScript: MCPサーバー + control WS（Duet.appが起動）
    src/
      server.ts                 # express: /claude /codex (MCP), /control (WS), /health
      state.ts                  # キュー / resolver / ロール / トランスクリプト
      tools/{getBriefing,send,awaitReply}.ts
      control.ts                # WebSocket: GUIへevent push / GUIからcommand受信
    package.json  tsconfig.json
  app/                          # Swift/SwiftUI: Duet.app（製品本体）
    Package.swift もしくは Duet.xcodeproj
    Sources/Duet/
      DuetApp.swift             # @main, Hub子プロセス起動/終了
      HubClient.swift           # URLSessionWebSocketTask で /control に接続
      RoomView.swift            # 対話ログのライブ表示
      RolesView.swift           # ロール割当UI
      InjectView.swift          # 人間メッセージ注入
      OCR/WindowOCR.swift       # ScreenCaptureKit + Vision
  prompts/
    claude-implementer.md       # 実行時にエージェントへ渡すロールプロンプト（§7）
    codex-reviewer.md
  config/duet.config.example.json
  README.md  LICENSE            # MIT or Apache-2.0
```

## 5. `await_reply` の設計（最重要・Phase 0スパイクの結果を反映）

スパイク(`duet-timeout-spike`)で実証済み: **進捗通知(notifications/progress)を定期送信すると、
多くのMCPクライアントは1回のツール呼び出しのタイムアウトをリセットして待ち続ける**。

実装方針:
- `await_reply` は peer からの次メッセージが来るまでサーバー側でホールドするロングポーリング。
- ホールド中、`extra._meta.progressToken` があれば `progressIntervalSec`（既定20s想定）ごとに
  `notifications/progress` を送り、クライアントのタイムアウトを延命する。
- `holdSec`（既定値はスパイク実測後に確定。未測定なら保守的に短めに）まで待って何も来なければ
  `{status:"empty"}` を返す。**エージェント側プロンプトで empty 時は必ず `await_reply` を再呼び出し**させ、
  常時待受ループを維持する。
- progressToken が無い（＝そのアプリが進捗を要求しない）場合は延命に頼らず、`holdSec` を素の上限内に
  収め、empty 即再アームで繋ぐ。
- 人間注入メッセージ・peerメッセージのどちらが来ても解決して返す。

> 着手前に `duet-timeout-spike` を実機で回し、`holdSec` と `progressIntervalSec` の実値を
> `config/duet.config` に確定すること。未測定のまま本実装の数値を断定しない。

## 6. ビルド & 実行

- **Hub**: `cd hub && npm install && npm run build`。開発時は `npm start` 単体起動も可。
  MCP単体検証は `npx @modelcontextprotocol/inspector`。
- **App**: Xcodeで `app/` を開く（SwiftUI, macOS 14+ — ScreenCaptureKitのスクショAPIに必要）。
  本番は Duet.app が `node hub/dist/server.js` を子プロセス起動する。開発時はHubを別途起動して
  AppをXcodeから実行してもよい。
- **権限**（READMEに明記）: Screen Recording（Phase 3 OCR実装時に必要）、Accessibility/Automation（Phase 4c起床実装時に必要）。
  両公式アプリは auto-approve 寄りにしないとツール連打が承認待ちで止まる。

## 7. 実行時エージェントプロンプト（製品がエージェントへ渡す。§開発用プロンプトとは別物）

Claude/Codex はこれを `prompts/` に作る。人間が各アプリに貼る（またはClaudeは `claude://` 経由で投入）。

`prompts/claude-implementer.md`:
```
あなたはDuetのエージェントです。まず get_briefing を呼び role/task/repoPath/protocol を確認。
あなたは implementer。repoPath のファイルを直接編集して実装し、終わったら send で codex に
レビュー依頼し、await_reply で待機する。await_reply が empty を返したら必ずもう一度 await_reply を
呼んで待ち続けること。決して勝手に終了しない。from:"human" のメッセージは人間からの最優先指示として扱う。
レビュー所見が来たら反映し、再度 send→await_reply を繰り返す。
```
`prompts/codex-reviewer.md`:
```
あなたはDuetのエージェントです。まず get_briefing を呼ぶ。あなたは reviewer。
await_reply で実装者の連絡を待ち、来たら repoPath の該当ファイルを実際に読んでレビューし、send で返す。
コードはメッセージ本文ではなく必ずディスク上の実ファイルを読むこと。empty が返ったら必ず await_reply を
再呼び出しして待ち続ける。from:"human" は人間からの最優先指示として扱う。
```

## 8. コーディング規約

- **TS（Hub）**: strict、Zodで入力検証(`.strict()`)、`server.registerTool`、`structuredContent` を返す、
  アノテーション(readOnly/destructive/idempotent/openWorld)を明示、`any` 禁止、実用的なエラーメッセージ。
  （公式 Model Context Protocol TypeScript SDK と現行仕様に準拠。）
- **Swift（App）**: SwiftUI + async/await。control WSは標準の `URLSessionWebSocketTask`（追加依存なし）。
  OCRは ScreenCaptureKit + Vision。秘密情報をコードに埋めない。
- 共通: 小さく作って各フェーズで動作確認。フェーズ境界を越えた実装を先走らない。

## 9. フェーズ・ロードマップ

- **Phase 0 — スパイク（完了）**: タイムアウト上限と進捗延命を実測。→ holdSec / progressIntervalSec を得る。
- **Phase 1 — Hubコア（headless）**: MCP 3ツール + 共有状態 + control WS（まずconsoleログ）。1往復を実機 or
  スタブで確認。
- **Phase 2 — GUI（Duet.app）= 製品の核**: Hubを起動し、対話ログのライブ表示・ロール割当・人間注入・
  開始/停止を持つSwiftUIアプリ。ここで「Macアプリ」として成立。
- **Phase 3 — OCR保険**: ScreenCaptureKit+Visionでウィンドウ撮影→OCR→Hubでground-truthログ→GUI表示。
- **Phase 4 — 常時待受の堅牢化/起床**: ループ維持、寝たエージェントの起床（Claude=`claude://`、Codex=`osascript`）。
- **Phase 5 — セッション自動更新**: 消費量しきい値で引き継ぎサマリ生成→新セッション開始。
- **Phase 6 — 自由対話/worktree/自由ロール**: 三目並べ等、git worktreeによる作業分離、自由なロール交渉。

**MVP = Phase 1〜2**（コアループ＋GUI）。Phase 3 は強く推奨。4〜6 は拡張。

## 10. 着手前に確認すべき外部依存（推測で埋めない）

- Codex.app / Claude Desktop の正確な **bundle id**（OCRのウィンドウ特定に必要）→ `mdls`/`osascript`で確認。
- 両アプリの **HTTP MCP 登録方式** は README と `docs/SPEC.md` の記述を正とする:
  Claude Code は `claude mcp add-json` でHTTP直結し `Authorization: Bearer` を使う。Codex は
  `~/.codex/config.toml` の `[mcp_servers.*]` と `bearer_token_env_var` を使う。公開前や実装変更時は
  各アプリ最新ドキュメントで再確認する。
- `claude://` でClaude Codeセッションにプロンプト投入後、**自動送信されるか/Enter補完が要るか**（Phase 4で実測）。
