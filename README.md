# Duet

GUI lovers, this one is for you.

Duet is a macOS-only OSS control room. It coordinates two official desktop agents: Claude Desktop with Claude Code and Codex.app. You launch one SwiftUI app, `Duet.app`. Duet starts a local TypeScript Hub as a child process, shows the two-agent conversation live, lets you assign roles, and lets the human jump in whenever the humans inevitably decide the robots need supervision.

There are already plenty of OSS projects that make Claude Code CLI and Codex CLI review each other while implementing changes. Duet is for people who would rather not live inside the terminal void. The agents stay in the official desktop apps, and Duet gives them a local coordination room. Source-first setup still includes a few commands because, well, OSS, but the product experience is GUI-first rather than a CLI-vs-CLI ritual.

GUI が大好きなみなさん！

Duet は macOS 専用の OSS で、2つの公式デスクトップアプリ (Claude Desktop 内の Claude Code と Codex.app) を、なんと！ローカルの MCP ハブ経由で会話・相互レビューさせることができます！あなたが起動するのは1つの SwiftUI アプリ（Duet.app）だけ。アプリが Hub を子プロセスとして起動し、対話ログをライブ表示し、ロールを割り当てられます。もちろん人間が割り込むことも可能です。

ターミナル(CLI)でお互いレビューさせて実装する OSS はかなり有名ですが、Duet はターミナルが嫌いだという人のためのものです。エージェント本体は公式デスクトップアプリのままで良いのです。ソースからのセットアップにはいくつかコマンドも出てきますが、そこは OSS なので許してください。これはGUI信者専用になると思います。あの暗闇の画面に抵抗があるという方はぜひ使ってみてください！

The important constraint is simple: **code does not travel through chat, OCR, or the message bus**. Claude and Codex share the same repository on disk and read or write real files with their own file tools. Duet only carries short natural-language coordination messages such as “please review `src/auth.ts`”.

**コードはチャット・OCR・メッセージバスを流れません**。Claude と Codex はディスク上の同じリポジトリを共有し、各自のファイルツールで実ファイルを直接読み書きします。Duet が運ぶのは「`src/auth.ts` をレビューして」のような短い自然言語の調整メッセージだけです。

![Duet demo](assets/duet-demo.gif)

## Status

This repository currently implements the Phase 1-2 MVP plus Phase 4b stall observation:

- TypeScript Hub with `/claude`, `/codex`, `/control`, `/health`, and `/setup`
- MCP tools: `get_briefing`, `send`, and `await_reply`
- Long-polling `await_reply` with progress notifications when the client provides a progress token
- SwiftUI macOS app that launches the Hub, connects to `/control`, displays the live transcript, updates roles, and injects human messages
- Transcript with a chat/log view toggle, text search and per-agent filtering, day separators, and a jump-to-latest control
- One-click Setup that copies the MCP registration commands (with the per-agent tokens) and the role prompts to the clipboard
- Conversation export to Markdown or JSON
- Repo-relative file paths in messages are clickable and open the file, restricted to `repoPath`
- Current Git branch shown in the toolbar and sidebar
- Stall observation and GUI warning display when an agent appears inactive without an active `await_reply` waiter
- Project-local Run action for the Codex desktop app

Phase 3 OCR, Phase 4c wake-up automation, session rollover, and worktree orchestration are intentionally documented but are not shipped as completed features yet.

## 現在の状態

このリポジトリは、現時点で Phase 1-2 の MVP と Phase 4b の停滞観測を実施しています:

- `/claude`、`/codex`、`/control`、`/health`、`/setup` を持つ TypeScript Hub
- MCP ツール: `get_briefing`、`send`、`await_reply`
- クライアントが progress token を提供する場合の progress notification 付きロングポーリング `await_reply`
- Hub を起動し、`/control` に接続し、ライブ transcript 表示・ロール更新・人間メッセージ注入を行う SwiftUI macOS アプリ
- チャット／ログの表示切替、テキスト検索とエージェント別フィルタ、日付区切り、最新へ移動を備えた transcript 表示
- MCP 登録コマンド（エージェントごとのトークン入り）とロールプロンプトをクリップボードにコピーするワンクリック・セットアップ
- 会話の Markdown / JSON エクスポート
- メッセージ内のリポジトリ相対パスをクリックでファイルを開く機能（`repoPath` 内に限定）
- ツールバーとサイドバーに現在の Git ブランチを表示
- アクティブな `await_reply` waiter が無いままエージェントが非アクティブに見える場合の停滞観測と GUI 警告表示
- Codex デスクトップアプリ向けの project-local Run action

Phase 3 の OCR、Phase 4c の起床自動化、セッション更新、worktree オーケストレーションは、意図的にドキュメント化されていますが、完成機能としてはまだ出荷されていません。

## Requirements

- macOS 14 or newer
- Node.js 20 or newer
- Swift toolchain with SwiftPM
- Claude Desktop and Codex.app for a real two-agent run

## 動作要件

- macOS 14 以降
- Node.js 20 以降
- SwiftPM を含む Swift ツールチェーン
- 実際に2エージェントで動かすには Claude Desktop と Codex.app

## Build and Run

Build the Hub:

```bash
cd hub
npm install
npm run build
npm test
```

Build the app:

```bash
swift build --package-path app
```

Or use the project entrypoint:

```bash
./script/build_and_run.sh --verify
```

The script builds the Hub, builds the SwiftPM app, stages `dist/Duet.app`, launches it as a real app bundle, verifies the app icon metadata, checks Hub `/health`, and connects to the control WebSocket. The staged development bundle is unsigned, not notarized, and expects to run from this source checkout. Until a release signing and notarization flow exists, expect normal local-development Gatekeeper behavior. See `docs/RELEASE_PACKAGING.md`.

To launch Duet as the always-on local room:

```bash
./script/build_and_run.sh run
```

## ビルドと起動

Hub をビルドします:

```bash
cd hub
npm install
npm run build
npm test
```

アプリをビルドします:

```bash
swift build --package-path app
```

または、プロジェクトのエントリポイントを使います:

```bash
./script/build_and_run.sh --verify
```

このスクリプトは Hub をビルドし、SwiftPM アプリをビルドし、`dist/Duet.app` を生成して実際のアプリとして起動し、アプリアイコンのメタデータを検証し、Hub の `/health` を確認し、control WebSocket に接続します。生成される開発用バンドルは署名・公証されておらず、このソースチェックアウトから実行する前提です。リリース用の署名/公証フローができるまでは、ローカル開発時の通常の Gatekeeper の挙動を想定してください。詳細は `docs/RELEASE_PACKAGING.md` を参照してください。

常駐起動するには:

```bash
./script/build_and_run.sh run
```

## Configuration

Copy the example and edit it for the shared repository the agents should work on:

```bash
cp config/duet.config.example.json config/duet.config.json
```

`config/duet.config.json` is gitignored because it can contain local paths and task text. Duet.app does not fall back to the example file at runtime. If the local config is missing, it starts in an error state and does not launch the Hub.

The values below match the conservative defaults the Hub ships with (`holdSec` 50s, `noProgressHoldSec` 25s, `progressIntervalSec` 20s) and are identical to `config/duet.config.example.json`. The Phase 0 timeout spike has not been measured on every machine, so treat these as safe starting points, not proven maxima. After you run `tools/duet-timeout-spike` against your Claude Desktop and Codex.app and confirm that periodic progress notifications extend a held tool call, you can raise `holdSec` toward ~180s (max 300) and `noProgressHoldSec` toward ~50s (max 60). Until you have measured your machine, keep these conservative values so `await_reply` always returns and re-arms cleanly.

```json
{
  "host": "127.0.0.1",
  "port": 8765,
  "repoPath": "/ABSOLUTE/PATH/TO/SHARED/REPOSITORY",
  "holdSec": 50,
  "noProgressHoldSec": 25,
  "progressIntervalSec": 20,
  "roles": {
    "claude": { "role": "implementer", "task": "Implement the change." },
    "codex": { "role": "reviewer", "task": "Review the changed files from disk." }
  }
}
```

The Hub is bound to loopback by default. Do not use a non-loopback `host` unless you also have a reviewed authentication and network exposure plan. If Node.js is not in a standard absolute path, set `DUET_NODE_PATH` to a Node 20+ executable before launching Duet.

On Hub startup, `config/duet.secrets.json` is created if missing. It is local-only, gitignored, and contains random per-agent MCP tokens:

```json
{
  "version": 1,
  "mcpTokens": {
    "claude": "<generated-token>",
    "codex": "<generated-token>"
  }
}
```

Keep this file private. To rotate these tokens, stop Duet, delete `config/duet.secrets.json`, start Duet again, and update the agent MCP registrations with the new bearer token values or fallback URLs.

## 設定

エージェントに作業させる共有リポジトリ用に、サンプルをコピーして編集します:

```bash
cp config/duet.config.example.json config/duet.config.json
```

`config/duet.config.json` はローカルパスやタスク文を含みうるため gitignore されています。Duet.app は実行時にサンプルファイルへフォールバックしません。ローカル設定が無いとエラー状態で起動し、Hub を立ち上げません。

以下の値は Hub の保守的な既定値（`holdSec` 50秒・`noProgressHoldSec` 25秒・`progressIntervalSec` 20秒）と一致し、`config/duet.config.example.json` と同じです。Phase 0 のタイムアウト実測は全マシンで取られたわけではないため、これらは「確定した上限」ではなく「安全な初期値」として扱ってください。`tools/duet-timeout-spike` を自分の Claude Desktop / Codex.app に対して実行し、progress notification がツール呼び出しの待機を延命することを確認できたら、`holdSec` を ~180秒（上限300）まで、`noProgressHoldSec` を ~50秒（上限60）まで上げて構いません。実測するまでは、`await_reply` が確実に返って再アームできるよう、この保守的な値を維持してください。

```json
{
  "host": "127.0.0.1",
  "port": 8765,
  "repoPath": "/ABSOLUTE/PATH/TO/SHARED/REPOSITORY",
  "holdSec": 50,
  "noProgressHoldSec": 25,
  "progressIntervalSec": 20,
  "roles": {
    "claude": { "role": "implementer", "task": "Implement the change." },
    "codex": { "role": "reviewer", "task": "Review the changed files from disk." }
  }
}
```

Hub は既定でループバックにバインドされます。認証とネットワーク公開の計画をレビュー済みでない限り、ループバック以外の `host` は使わないでください。Node.js が標準的な絶対パスに無い場合は、Duet 起動前に `DUET_NODE_PATH` に Node 20 以降の実行ファイルを設定してください。

Hub の起動時、`config/duet.secrets.json` が無ければ自動生成されます。これはローカル限定・gitignore 済みで、エージェントごとのランダムな MCP トークンを含みます:

```json
{
  "version": 1,
  "mcpTokens": {
    "claude": "<generated-token>",
    "codex": "<generated-token>"
  }
}
```

このファイルは非公開に保ってください。トークンを更新するには、Duet を停止し、`config/duet.secrets.json` を削除し、Duet を再起動して、新しいトークン値（またはフォールバック URL）でエージェントの MCP 登録を更新します。

## MCP Registration

The Hub exposes two agent-specific MCP route roots. When the MCP client can send an `Authorization: Bearer <token>` header, register the bare route root and put the token in the header:

- Claude: `http://127.0.0.1:8765/claude`
- Codex: `http://127.0.0.1:8765/codex`

Important Claude note: for the normal local Duet setup, “register the bare Claude root” means registering it in **Claude Code** with HTTP direct registration. Do **not** paste this local HTTP URL into the Claude Desktop connector screen, and do **not** use a `claude_desktop_config.json` remote-URL shape for this path. That connector flow assumes a different setup, such as a publicly reachable HTTPS or OAuth-style connector, and will not work for this local HTTP endpoint.

## MCP 登録

Hub はエージェントごとに2つの MCP ルートを公開します。MCP クライアントが `Authorization: Bearer <token>` ヘッダを送れる場合は、素のルートを登録し、トークンはヘッダに入れます:

- Claude: `http://127.0.0.1:8765/claude`
- Codex: `http://127.0.0.1:8765/codex`

Claude について重要な注意です。通常のローカル Duet 用途で「Claude の素のルートを登録する」と言う場合、それは **Claude Code** に HTTP 直結登録するという意味です。このローカル HTTP URL を Claude Desktop のコネクタ画面に貼らないでください。また、この用途では `claude_desktop_config.json` のリモート URL 形式も使わないでください。このコネクタ経路は、公開到達可能な HTTPS や OAuth 風のコネクタを前提とした別の仕組みで、このローカル HTTP エンドポイントでは動作しません。

If a client cannot set MCP HTTP headers, use the secret-bearing fallback URL only for that client:

- Claude: `http://127.0.0.1:8765/claude/<claude-token>`
- Codex: `http://127.0.0.1:8765/codex/<codex-token>`

Path tokens are supported only for clients without header support, because URLs are more likely to appear in logs, screenshots, copied configs, and shell history. Do not put these tokens in screenshots, bug reports, shell history intended for sharing, or docs examples.

`DUET_CONTROL_TOKEN` is separate from the MCP tokens. Duet.app generates it per run, passes it to the Hub child process, and uses it only for `/control` WebSocket authentication via `X-Duet-Control-Token`.

ヘッダを設定できないクライアントの場合のみ、トークンを URL に埋め込むフォールバックを使います:

- Claude: `http://127.0.0.1:8765/claude/<claude-token>`
- Codex: `http://127.0.0.1:8765/codex/<codex-token>`

URL 埋め込みトークンは、ヘッダ非対応クライアント専用です。URL はログ・スクリーンショット・コピーされた設定・シェル履歴に残りやすいためです。これらのトークンをスクリーンショット・バグ報告・共有用シェル履歴・ドキュメント例に載せないでください。

`DUET_CONTROL_TOKEN` は MCP トークンとは別物です。Duet.app が起動ごとに生成し、Hub 子プロセスに渡し、`/control` WebSocket 認証（`X-Duet-Control-Token`）のみに使います。

External MCP and agent configuration formats can change. These are the relevant reference pages to recheck before release work or before changing the setup flow:

- [MCP Streamable HTTP transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
- [Codex MCP docs](https://developers.openai.com/codex/mcp)
- [Codex configuration reference](https://developers.openai.com/codex/config-reference)
- [Claude Code MCP docs](https://code.claude.com/docs/en/mcp)

外部の MCP 仕様や各エージェントの設定形式は変わる可能性があります。リリース作業前やセットアップ手順を変える前には、以下を再確認してください:

- [MCP Streamable HTTP transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
- [Codex MCP docs](https://developers.openai.com/codex/mcp)
- [Codex configuration reference](https://developers.openai.com/codex/config-reference)
- [Claude Code MCP docs](https://code.claude.com/docs/en/mcp)

Register the Claude side in Claude Code with HTTP direct registration:

```bash
claude mcp add-json duet '{"type":"http","url":"http://127.0.0.1:8765/claude","headers":{"Authorization":"Bearer <claude-token>"}}' -s user
```

Verify it:

```bash
claude mcp list
```

If you see something like this, you are connected:

```text
duet: http://127.0.0.1:8765/claude (HTTP) - ✓ Connected
```

**Claude 側の登録**は Claude Code で HTTP 直結登録します:

```bash
claude mcp add-json duet '{"type":"http","url":"http://127.0.0.1:8765/claude","headers":{"Authorization":"Bearer <claude-token>"}}' -s user
```

登録できたか確認します:

```bash
claude mcp list
```

次のように表示されれば成功です:

```text
duet: http://127.0.0.1:8765/claude (HTTP) - ✓ Connected
```

Register the Codex side in `~/.codex/config.toml` with a bearer-token environment variable:

```toml
[mcp_servers.duet]
url = "http://127.0.0.1:8765/codex"
bearer_token_env_var = "DUET_CODEX_MCP_TOKEN"
```

Or register it with the CLI. Keep the token in an environment variable so the token itself does not end up directly in config or shell history:

```bash
export DUET_CODEX_MCP_TOKEN="<codex-token>"
codex mcp add duet --url http://127.0.0.1:8765/codex --bearer-token-env-var DUET_CODEX_MCP_TOKEN
```

**Codex 側の登録**は `~/.codex/config.toml` に bearer-token 環境変数で書きます:

```toml
[mcp_servers.duet]
url = "http://127.0.0.1:8765/codex"
bearer_token_env_var = "DUET_CODEX_MCP_TOKEN"
```

または CLI で登録します。トークンは環境変数経由にして、設定やシェル履歴に直接残さないようにします:

```bash
export DUET_CODEX_MCP_TOKEN="<codex-token>"
codex mcp add duet --url http://127.0.0.1:8765/codex --bearer-token-env-var DUET_CODEX_MCP_TOKEN
```

## Agent Prompts

Use the files in `prompts/` to start each official desktop agent. The prompts tell agents to call `get_briefing`, work on files directly in `repoPath`, use `send` for coordination, keep code/secrets/PII out of messages, and keep re-arming `await_reply` after `empty`.

Japanese and English prompt variants are available. Use `prompts/claude-implementer.md` and `prompts/codex-reviewer.md` for Japanese sessions, or `prompts/claude-implementer.en.md` and `prompts/codex-reviewer.en.md` for English sessions.

## エージェントへのプロンプト

各公式デスクトップエージェントを起動するには `prompts/` のファイルを使います。これらのプロンプトは、エージェントに対して `get_briefing` を呼ぶこと、`repoPath` のファイルを直接操作すること、調整には `send` を使うこと、コード・秘密・個人情報をメッセージに載せないこと、`empty` が返ったら `await_reply` を再度呼び続けることを指示します。

日本語版と英語版があります。日本語セッションには `prompts/claude-implementer.md` と `prompts/codex-reviewer.md` を、英語セッションには `prompts/claude-implementer.en.md` と `prompts/codex-reviewer.en.md` を使ってください。

## Typical Flow: One Implement → Review Round Trip

1. Start Duet.app with `./script/build_and_run.sh run`. Confirm the top-right status says the Hub is connected.
2. Register Duet’s MCP endpoints in Claude Code and Codex using the steps above.
3. Assign roles in Duet.app, for example `Claude = implementer` and `Codex = reviewer`.
4. First, paste `prompts/codex-reviewer.md` into the Codex reviewer chat and put it into the waiting loop with `await_reply`.
5. Next, paste `prompts/claude-implementer.md` into Claude Code. Claude edits files under `repoPath`, sends Codex a review request with `send`, and waits with `await_reply`.
6. The implement → review exchange appears live in Duet.app. Use the input bar at the bottom whenever you want to inject a human message to Claude, Codex, or both.

## 使い方の流れ（実装→レビューの1往復）

1. `./script/build_and_run.sh run` で Duet.app を起動します。ウィンドウ右上が「Hub 接続済み」になることを確認。
2. 上記の手順で Claude Code と Codex に Duet の MCP を登録します。
3. Duet.app でロールを割り当てます（例: `Claude = implementer` / `Codex = reviewer`）。
4. 先に Codex（reviewer）のチャットに `prompts/codex-reviewer.md` を貼り、待受ループ（`await_reply`）に入れます。
5. 次に Claude Code（implementer）のチャットに `prompts/claude-implementer.md` を貼ります。Claude が `repoPath` のファイルを編集し、`send` で Codex にレビュー依頼し、`await_reply` で待機します。
6. 実装→レビューの往復が Duet.app にライブ表示されます。下部の入力バーから、いつでも人間メッセージを最上位命令として割り込みできます（宛先は Claude / Codex / 両方）。

## Security

- Do not commit API keys, credentials, real customer data, or local `config/duet.config.json`.
- Do not commit `config/duet.secrets.json`; it contains per-agent MCP tokens.
- Do not paste source code into Duet messages. Agents must read files from the shared repository path.
- Keep Hub bound to `127.0.0.1` unless you have a reviewed reason to expose it elsewhere.
- Hub stdout logs only event metadata by default. `DUET_VERBOSE_EVENTS=1` still redacts message bodies, tasks, paths, and secret-looking values.
- OCR is a future insurance layer for screen-ground-truth only; it is not a code transport path.

## セキュリティ

- API キー・認証情報・実顧客データ・ローカルの `config/duet.config.json` をコミットしないでください。
- `config/duet.secrets.json` をコミットしないでください（エージェントごとの MCP トークンを含みます）。
- Duet のメッセージにソースコードを貼らないでください。エージェントは共有リポジトリのファイルを読みます。
- レビュー済みの理由が無い限り、Hub は `127.0.0.1` にバインドしたままにしてください。
- Hub の標準出力は既定でイベントのメタデータのみをログ出力します。`DUET_VERBOSE_EVENTS=1` でも、メッセージ本文・タスク・パス・秘密らしき値は伏せられます。
- OCR は将来の「画面の ground-truth」用の保険レイヤーであり、コードの転送経路ではありません。

## Limitations

- Duet is macOS-only.
- Phase 3 OCR, Phase 4c wake-up automation, session rollover, and worktree orchestration are not shipped as completed features.
- The development app bundle is unsigned and not notarized.
- Duet does not guarantee that either desktop agent will keep waiting forever; prompts and `await_reply` re-arming are part of the operating protocol.
- Duet is local developer tooling, not a sandbox boundary for untrusted repositories or untrusted MCP clients.

## 制限事項

- Duet は macOS 専用です。
- Phase 3 の OCR、Phase 4c の起床自動化、セッション更新、worktree オーケストレーションは、完成機能としてはリリースしていません。
- 開発用アプリバンドルは署名・公証されていません。
- Duet は、どちらのデスクトップエージェントも永遠に待機し続けることを保証しません。プロンプトと `await_reply` の再アームは運用プロトコルの一部です。
- Duet はローカルの開発者向けツールであり、信頼できないリポジトリや信頼できない MCP クライアントに対するサンドボックス境界ではありません。

## License

MIT. See `LICENSE`. Third-party dependency inventory is in `THIRD_PARTY_LICENSES.md`.

## ライセンス

MIT。`LICENSE` を参照してください。サードパーティ依存の一覧は `THIRD_PARTY_LICENSES.md` にあります。
