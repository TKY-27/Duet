# Duet

**English version: [README.md](README.md)**

Duet は、すでにデスクトップアプリの中にいる2つのエージェントのための macOS コントロールルームです。

**Claude Desktop の Claude Code** と **Codex.app** をローカルの MCP ハブ経由で
つなぎ、その会話をライブ表示し、ロールを割り当て、いつでも割り込めるようにします。
起動するのは SwiftUI アプリ1つだけ。ハブはアプリが立ち上げます。

Claude Code CLI と Codex CLI に相互レビューさせる OSS はいくらでもあります。
Duet は、それを眺めるためだけにターミナルに住みたくない人のためのものです。
エージェント本体は公式アプリのまま。Duet は、彼らが何をしているかを見る窓であり、
人間が介入する場所です。

![Duet demo](assets/duet-demo.gif)

> この GIF は現行のインターフェースより前のもので、差し替え予定です。

## すべてを決めている1つのルール

**コードはメッセージバスを流れません。** Claude と Codex はディスク上の同じ
リポジトリを共有し、各自のファイルツールで実ファイルを直接読み書きします。
Duet が運ぶのは「`src/auth.ts` をレビューして」のような短い自然言語の調整だけ。
レビューはファイルを読んで行うものであって、チャットに貼り付けて行うものでは
ありません。

## 動作要件

- macOS 26 以降
- Node.js 22 以降
- SwiftPM を含む Swift ツールチェーン
- 実際に2エージェントで動かすには Claude Desktop と Codex.app

## ビルドと起動

```bash
cd hub && npm install && npm run build && npm test
```

```bash
swift build --package-path app
```

または、両方をビルドし `dist/Duet.app` を生成して起動し、ハブの health と
control WebSocket まで確認するプロジェクトのエントリポイント:

```bash
./script/build_and_run.sh --verify
```

常駐起動するには:

```bash
./script/build_and_run.sh run
```

生成される開発用バンドルは署名・公証されておらず、このソースチェックアウトから
実行する前提です。ローカル開発時の通常の Gatekeeper の挙動を想定してください。
詳細は [docs/RELEASE_PACKAGING.md](docs/RELEASE_PACKAGING.md) を参照。

## 設定

```bash
cp config/duet.config.example.json config/duet.config.json
```

`config/duet.config.json` はローカルパスやタスク文を含むため gitignore されて
います。実行時にサンプルへフォールバックはしません。ローカル設定が無い場合は
エラー状態で起動し、ハブを立ち上げません。

```json
{
  "host": "127.0.0.1",
  "port": 8765,
  "repoPath": "/ABSOLUTE/PATH/TO/SHARED/REPOSITORY",
  "holdSec": 180,
  "noProgressHoldSec": 50,
  "progressIntervalSec": 20
}
```

`holdSec` は MCP クライアントが progress notification を送る場合の値、
`noProgressHoldSec` は送らない場合の値です。上記は
[docs/MEASUREMENTS.md](docs/MEASUREMENTS.md) に記録された Phase 0 の実測経路に
基づいています。

ハブは既定でループバックにバインドされます。認証とネットワーク公開の計画を
レビュー済みでない限り、ループバック以外の `host` は使わないでください。
Node が標準的な絶対パスに無い場合は `DUET_NODE_PATH` を設定してください。

起動時、`config/duet.secrets.json` が無ければ自動生成されます（ローカル限定・
gitignore 済み・エージェントごとのランダムな MCP トークン）。トークンを更新
するには、Duet を停止し、このファイルを削除し、再起動して、両エージェントを
登録し直します。

## エージェントの接続

ハブはエージェントごとに MCP ルートを1つ公開します。素のルートを登録し、
トークンは `Authorization: Bearer` ヘッダに入れます。

**Claude** — **Claude Code** に HTTP 直結登録します:

```bash
claude mcp add-json duet '{"type":"http","url":"http://127.0.0.1:8765/claude","headers":{"Authorization":"Bearer <claude-token>"}}' -s user
```

```bash
claude mcp list
```

このローカル HTTP URL を Claude Desktop のコネクタ画面に貼らないでください。
また `claude_desktop_config.json` のリモート URL 形式もこの用途では使いません。
あの経路は公開到達可能な HTTPS / OAuth 風コネクタを前提にしており、動きません。

**Codex** — `~/.codex/config.toml` に、トークンは環境変数経由で:

```toml
[mcp_servers.duet]
url = "http://127.0.0.1:8765/codex"
bearer_token_env_var = "DUET_CODEX_MCP_TOKEN"
```

```bash
export DUET_CODEX_MCP_TOKEN="<codex-token>"
codex mcp add duet --url http://127.0.0.1:8765/codex --bearer-token-env-var DUET_CODEX_MCP_TOKEN
```

ヘッダを設定できないクライアントのためだけに、トークンを URL に埋め込む形式
(`http://127.0.0.1:8765/claude/<token>`) もあります。URL はログ・
スクリーンショット・コピーされた設定・シェル履歴に残りやすいため、可能な限り
ヘッダを使ってください。

`DUET_CONTROL_TOKEN` は MCP トークンとは別物で、Duet.app が起動ごとに生成し
`/control` の認証にのみ使います。

## 使い方の流れ（実装→レビューの1往復）

1. Duet を起動し、ハブが接続済みになることを確認します。
2. 上記の手順で両方の MCP エンドポイントを登録します。
3. ロールを割り当てます（例: Claude = implementer / Codex = reviewer）。
4. 先に `prompts/codex-reviewer.md` を Codex に貼り、`await_reply` の待受
   ループに入れます。
5. 次に `prompts/claude-implementer.md` を Claude Code に貼ります。Claude が
   `repoPath` のファイルを編集し、Codex にレビュー依頼を送り、待機します。
6. 往復を眺めます。下部の入力バーから Claude / Codex / 両方へ割り込めます。
   人間のメッセージは最優先指示として配送されます。

`prompts/` には日本語版と英語版の両方があります。

## プロトコル対応

ハブは v2 MCP TypeScript SDK 上に構築されており、**2026-07-28 リビジョンと
2025 年系プロトコルの両方**を同一エンドポイントで提供します。したがって、
どちらのデスクトップアプリが新リビジョンに追随済みかに関わらず動作します。
これは、2025 年系クライアントと 2026-07-28 に固定したクライアントを接続し、
両者の間をメッセージが渡ることを確認するテストで検証されています。

`await_reply` はロングポーリングです。クライアントが progress token を提供する
場合、ハブはホールド中に `notifications/progress` を送り、クライアント側の
リクエストタイムアウトを発火させません。提供しない場合はホールドを
`noProgressHoldSec` に制限し、エージェントは `empty` で再アームします。

## 実装済みと未実装

**実装済み**: 3つの MCP ツールと両プロトコル対応を持つハブ、control WebSocket、
プレゼンスと停滞の観測、読み取り専用の Git ステータス、追記専用のセッション
履歴と Markdown エクスポート。

**未実装**（ドキュメント上は記述あり）: ScreenCaptureKit + Vision による OCR、
停滞したエージェントの起床自動化、セッション更新、worktree オーケストレーション。

## セキュリティ

- `config/duet.config.json`、`config/duet.secrets.json`、API キー、認証情報、
  実顧客データをコミットしないでください。
- Duet のメッセージにソースコードを貼らないでください。エージェントは共有
  リポジトリのファイルを読みます。
- レビュー済みの理由が無い限り、ハブは `127.0.0.1` のままにしてください。
- ハブの標準出力は既定でイベントのメタデータのみを出力します。
  `DUET_VERBOSE_EVENTS=1` でもメッセージ本文・タスク・パス・秘密らしき値は
  伏せられます。
- セッション履歴は `~/Library/Application Support/Duet` 以下に `0600` で
  書き込まれます。
- Duet はローカルの開発者向けツールであり、信頼できないリポジトリや信頼できない
  MCP クライアントに対するサンドボックス境界ではありません。

脆弱性の報告は [SECURITY.md](SECURITY.md) に従ってください。

## 制限事項

- macOS 専用です。
- 開発用アプリバンドルは署名・公証されていません。
- Duet は、どちらのデスクトップエージェントも永遠に待機し続けることを保証しません。
  プロンプトと `await_reply` の再アームは運用プロトコルの一部です。

## ドキュメント

- [docs/SPEC.md](docs/SPEC.md) — 製品と実装の正典
- [docs/DESIGN.md](docs/DESIGN.md) — インターフェースの原則と、何を何に置き換えたか
- [docs/MEASUREMENTS.md](docs/MEASUREMENTS.md) — タイミングと自動化の判断根拠となる実測値
- [docs/RELEASE_PACKAGING.md](docs/RELEASE_PACKAGING.md) — パッケージングの注意点
- [CONTRIBUTING.md](CONTRIBUTING.md) — ローカルチェックと開発ルール
- [CHANGELOG.md](CHANGELOG.md)

## ライセンス

MIT。[LICENSE](LICENSE) を参照。サードパーティ一覧は
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)（`npm run license:generate`
で生成）にあります。
