# AGENTS.md — Duet

このファイルは Duet リポジトリの正典です。Codex も Claude Code もこれを読みます
（`CLAUDE.md` はこのファイルを指すポインタです）。

- 製品と実装の詳細は `docs/SPEC.md` が正。ここと矛盾したら SPEC が勝ちます。
- インターフェースの判断は `docs/DESIGN.md` が正。
- 実測値は `docs/MEASUREMENTS.md`。

---

## 1. これは何か

Duet は **macOS 専用の GUI OSS**。1つのウィンドウで、**Codex.app** と
**Claude Desktop 内の Claude Code** が会話・相互レビューする様子をライブ表示し、
人間がロールを割り当てたり指示を割り込ませたりできます。エージェント本体は
各公式アプリのまま（改造しません）。

Duet は「調整・観察・介入のための窓」であって、エージェントを画面操作で
いじるものではありません。

## 2. HARD RULES（譲れない原則）

1. **エージェント本体は CLI でも SDK でもなく公式デスクトップアプリ**。
   Codex は Codex.app、Claude は Claude Desktop の中の Claude Code。
2. **コードはバス／チャット／OCR に載せない**。2エージェントは同じリポジトリ
   （同じファイルシステム）を共有し、コードはディスク上の実ファイルを各自の
   ファイルツールで直接読み書きします。バスを流れるのは自然言語の調整
   メッセージだけ。レビューは相手の実ファイルを読んで行います。
3. **出力の取り出しは MCP ツール経由が主軸、OCR は保険**。画面の応答テキストを
   スクレイピングして相手に渡す設計にはしません（AX で塞がれており壊れます）。
4. **速度は問わない**。安全・正確が最優先。ロングポーリングの待ち時間は許容します。
5. **Mac 専用**。Windows/Linux 対応のための抽象化に労力を割きません。
6. **ハブはループバック束縛**。例外にはレビュー済みの認証・公開計画が必要です。

## 3. アーキテクチャ

```
Claude Desktop (Claude Code)        Codex.app
   MCP client                        MCP client
        │ HTTP MCP /claude                │ HTTP MCP /codex
        └────────────┬───────────────────┘
                     ▼
        ┌──────────────────────────┐  control WS  ┌────────────────────┐
        │ Hub (TypeScript / Node)   │◀────────────▶│ Duet.app (SwiftUI) │
        │ - MCP server (v2 SDK)     │  events ▲    │ ← ユーザーが起動する製品 │
        │ - message bus + roles     │  commands    │ - ライブ対話ログ       │
        │ - presence / stall / git  │              │ - ロール割当           │
        │ - session history (JSONL) │              │ - 人間メッセージ注入     │
        └──────────────────────────┘              └────────────────────┘
                     ▲ 子プロセスとして起動 ─────────────────┘
```

- **Duet.app（Swift/SwiftUI）= 製品**。起動時に Hub を子プロセスとして立ち上げ、
  control WebSocket で繋ぎます。
- **Hub（TypeScript/Node）= メッセージバス＋MCP サーバー**。Duet.app が起動・
  監視・終了させます。

## 4. リポジトリ構成

```
duet/
  AGENTS.md  CLAUDE.md  README.md  README.ja.md  CHANGELOG.md
  docs/{SPEC,DESIGN,MEASUREMENTS,RELEASE_PACKAGING}.md
  hub/src/
    server.ts          express: /claude /codex (MCP), /control (WS), /health
    nodeHttpBridge.ts  fetch 形式ハンドラ → Node req/res
    state.ts           キュー / waiter / ロール / トランスクリプト
    presence.ts        プレゼンスと停滞の観測
    git.ts             読み取り専用のリポジトリ状態
    store.ts           セッション履歴（JSONL）
    control.ts         control WebSocket
    tools/{getBriefing,send,awaitReply}.ts
  app/Sources/Duet/    Swift/SwiftUI: Duet.app
  prompts/             実行時にエージェントへ渡すロールプロンプト
  config/duet.config.example.json
```

## 5. コーディング規約

**TypeScript（Hub）**: strict。Zod で入力検証（`.strict()`）。
`server.registerTool` を使い `structuredContent` を返す。アノテーション
（readOnly/destructive/idempotent/openWorld）を明示。`any` 禁止。実用的な
エラーメッセージ。`ControlEvent` の switch に `default` を書かない
（新しいイベントが redaction 忘れのままビルドを通らないように）。

**Swift（App）**: SwiftUI + async/await、`@Observable`。control WS は標準の
`URLSessionWebSocketTask`（追加依存なし）。秘密情報をコードに埋めない。
UI は `docs/DESIGN.md` に従う。

**共通**: 小さく作って各段階で動作確認。フェーズ境界を越えた実装を先走らない。

## 6. 検証

```bash
cd hub && npm ci && npm test && npm run smoke && npm run license:check
```

```bash
swift build --package-path app && swift test --package-path app
```

Apple プラットフォームの変更は、まとまりごとに必ずビルドを通してから次へ進む
こと。ビルドが通っただけではビジュアル検証にはなりません。レンダリング結果の
確認手順は `docs/DESIGN.md` を参照。

依存を変えたら `npm run license:generate` を実行して
`THIRD_PARTY_LICENSES.md` を再生成すること（手編集しない）。

## 7. 実行時エージェントプロンプト

`prompts/` のファイルが製品からエージェントへ渡されるプロンプトです
（この開発用ドキュメントとは別物）。要点:

- まず `get_briefing` を呼び role/task/repoPath/protocol を確認する
- `repoPath` のファイルを直接読み書きする。コードをメッセージに載せない
- 調整は `send`、待機は `await_reply`
- `await_reply` が `empty` を返したら必ずもう一度呼んで待ち続ける。勝手に終了しない
- `from:"human"` は人間からの最優先指示として扱う

## 8. 着手前に確認すべき外部依存（推測で埋めない）

- MCP 仕様と TypeScript SDK は動きます。現行は 2026-07-28 リビジョン、SDK は
  v2 系（`@modelcontextprotocol/server`）。変更時は公式ドキュメントで再確認。
- Claude Code / Codex の MCP 登録方式は README と `docs/SPEC.md` の記述を正と
  します。公開前や実装変更時は各アプリ最新ドキュメントで再確認。
- Codex.app / Claude Desktop の bundle id とプロンプト投入の挙動は
  `docs/MEASUREMENTS.md` の実測値を参照。別のマシンや新しいバージョンでは
  再測定が必要です。
