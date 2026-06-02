# BUILD_PROMPTS.md — Duet をCodexに作らせるためのプロンプト集

> Note: このファイルは実装作業用プロンプトの履歴です。現行仕様は `docs/SPEC.md` を優先してください。
> 特にMCP認証、`/health/details`、`repoPath`安全制約、出荷済み/未出荷機能はSPECとREADMEが正です。

---

## Phase 1 — Hubコア（headless / TypeScript）

```
まず CLAUDE.md と docs/SPEC.md を読んでこのプロジェクトの原則とアーキテクチャを把握して。
このフェーズのゴールは hub/（TypeScript/Node）の headless 実装だけ。GUIとOCRはまだ作らない。

実装すること:
1. hub/ を公式 Model Context Protocol TypeScript SDK と現行MCP仕様に沿ってセットアップ（strict TS, Zod, express, @modelcontextprotocol/sdk）。
2. streamable-HTTP MCPサーバーを 1プロセスで立て、2つのMCPエンドポイントを公開: /claude と /codex。
   接続パスで agentId(claude/codex) を解決し、peer は自動的にもう一方。状態は単一プロセスで共有する
   （stdioにしないこと。理由はSPEC §1）。
3. MCPツール3種を registerTool で実装（詳細はSPEC §2）:
   - get_briefing(): 自分のrole/peer/task/repoPath/protocolを返す。readOnly。
   - send({message}): peer宛にメッセージを1件キュー投入。コードは載せない前提。
   - await_reply({holdSec?}): peer または human からの次メッセージが来るまでホールドするロングポーリング。
     ホールド中 extra._meta.progressToken があれば <PROGRESS_INTERVAL_SEC> 秒ごとに notifications/progress を
     送ってクライアントのタイムアウトを延命する（Phase 0で実証済みの手法）。holdSec 既定は <HOLD_SEC>。
     何も来なければ {status:"empty", note:"再度await_replyを呼べ"} を返す。peer/humanどちらでも解決。
4. 共有状態 state.ts: agentごとの受信キュー、ロール、全文トランスクリプト、await_replyのresolver登録。
5. control用WebSocket /control を用意（control.ts）: per-run control token で接続を認証し、接続クライアント(将来のGUI)へ全ルームイベント
   （message/role変更/status）をpushし、コマンド（setRoles / injectHuman({to,message}) / start / stop）を受ける。
   injectHuman は対象エージェントのキューに from:"human" として入れる。このフェーズではGUIが無いので、
   起動時にイベントを console にも出す。
6. config/duet.config.example.json を作る（port, repoPath, roles{claude,codex:{role,task}}, holdSec,
   progressIntervalSec）。
7. README に Claude Desktop / Codex への登録方法（HTTP MCPのurl登録）、`config/duet.secrets.json` の
   per-agent MCP token、control token との違いを書く。設定形式は公式MCP/Codex/Claude docsを確認して更新する。

受け入れ基準:
- npm run build が通る。npx @modelcontextprotocol/inspector で3ツールが見え、呼べる。
- await_reply が holdSec まで正しくホールドし、send で投入されたメッセージで解決する。
- /control にWebSocketで認証付き接続すると、send/injectHuman/role変更のイベントが流れてくる。
- まだ作らないもの: GUI、OCR、起床、セッション更新。これらには手を出さない。
```

---

## Phase 2 — GUI（Duet.app / SwiftUI）= 製品の核

```
CLAUDE.md と docs/SPEC.md を再確認して。このフェーズのゴールは app/（Swift/SwiftUI のmacOSアプリ Duet.app）。
これがユーザーが起動する製品本体。Hubは Phase 1 の実装をそのまま使う。

実装すること:
1. app/ を SwiftUI macOSアプリ(macOS 14+)としてセットアップ（SwiftPM か Xcodeプロジェクト）。
2. DuetApp.swift: 起動時に `node hub/dist/server.js` を子プロセスとして起動し、終了時に確実に停止する
   死活監視つき。Hubのポートは config から読む。
3. HubClient.swift: URLSessionWebSocketTask で Hub の /control に control token 付きで接続。イベント受信とコマンド送信を担う
   （追加依存は入れない）。
4. RoomView.swift: ルームの対話ログをライブ表示（誰が誰に何を言ったか、時刻つき、human注入も区別表示）。
5. RolesView.swift: ロール割当UI（claude/codex に role と task を割り当て、Hubへ setRoles コマンド送信）。
6. InjectView.swift: 人間メッセージ入力ボックス。宛先(claude/codex)を選び、injectHuman コマンドで送る。
7. 開始/停止ボタンと接続状態表示。

受け入れ基準:
- Duet.app を起動するとHubが立ち上がり、ウィンドウに接続済みと表示される。
- 実機で Claude Desktop と Codex.app を Hub に登録し、Phase 2 までで「実装→レビューの1往復」が
  ウィンドウにライブで流れることを確認できる。
- 途中で人間メッセージを注入すると、対象エージェントの次の await_reply に from:"human" で届く。
- まだ作らないもの: OCR、起床、セッション更新、worktree、自由対話。
```

---

## Phase 3 — OCR保険（Swift: ScreenCaptureKit + Vision）

```
CLAUDE.md を再確認。このフェーズのゴールは app/ 内のOCR保険レイヤー。コードはOCRに通さない原則(§2)を厳守。

実装すること:
1. app/Sources/Duet/OCR/WindowOCR.swift: ScreenCaptureKit で対象ウィンドウ(Codex.app / Claude Desktop)を
   撮影し、Vision(VNRecognizeTextRequest, .accurate, usesLanguageCorrection)でOCRしてテキスト＋行bboxを得る。
   対象ウィンドウのbundle idはCLAUDE.md §10の未確定事項の通り、推測せず mdls/osascript で確認してから埋める。
2. send が発生したタイミングで送信側ウィンドウを1枚OCRし、Hubへ ground-truth として送ってログ化、GUIにも
   「画面上の実際の発話」として控えめに表示する（保険・検証用）。
3. Screen Recording 権限の要求とエラーハンドリング、READMEへの権限手順追記。

受け入れ基準:
- 送信のたびに送信側ウィンドウのOCRテキストがログに残り、MCPの send 本文とおおむね整合する。
- まだ作らないもの: 完了検知のための画面安定判定・最新発話抽出・自動スクロール（必要になってから）。
```

---

## Phase 4 — 常時待受の堅牢化 / 起床

```
CLAUDE.md を再確認。ゴールは「エージェントがループから落ちない」堅牢化と、落ちた時の起床。

実装すること:
1. await_reply 再アームの遵守状況をHub側で観測（最後の活動からの経過、ループ離脱の検知）。
2. 寝たエージェントの起床トリガー:
   - Claude: claude:// URLスキームでCodeセッションに継続プロンプトを投入。自動送信されるか、Enterの
     キーストローク補完が要るかを実機で確認してから実装（§10 未確定事項）。
   - Codex: osascript によるアクティブ化＋継続プロンプト投入。
   起床は「読み取り」ではなく「書き込み(起こすだけ)」に限定し、画面スクレイピングはしない。
3. GUIに「停滞検知」と「起こす」ボタン、自動起床のオン/オフ。

受け入れ基準:
- 意図的にエージェントをターン終了させても、起床トリガーでループに復帰できる。
- まだ作らないもの: セッション更新、worktree、自由対話。
```

---

## Phase 5 — セッション自動更新

```
CLAUDE.md を再確認。ゴールはセッションが溜まったら自動で新規セッションへ引き継ぐこと。

実装すること:
1. 消費量の概算（メッセージ量ベース）またはエージェント自己申告で、上限接近を検知。
2. 接近したら対象エージェントに「引き継ぎサマリを書け」と指示し、サマリを取得。
3. 新セッションを開始してサマリを注入（Claude=claude://で新規Codeセッション＋サマリ、Codex=新スレッド＋注入）。
4. GUIに現在のセッション状態としきい値設定、手動更新ボタン。

受け入れ基準:
- 長時間の往復でセッションが更新され、文脈（サマリ）が引き継がれて作業が継続する。
```

---

## Phase 6 — 自由対話 / worktree / 自由ロール

```
CLAUDE.md を再確認。ゴールは応用機能。どれも既存のバス上のメッセージ交換とロール機構の組み合わせで作る。

実装すること（必要なものだけ）:
1. 自由対話モード: ロールを「自由」にして任意の往復（例: 三目並べ。手を send で交換するだけ）。GUIでモード切替。
2. git worktree による作業分離: 同じコードを双方が触る場合に衝突回避。各エージェントに別worktreeを割り当て、
   ファイル構成・分担・統合方針は get_briefing と send 上の交渉に委ねる。GUIでworktree状況を表示。
3. 自由ロール指示: 「フロントはClaude/バックはCodex、衝突回避は各自議論してから着手」のような自由度の高い
   タスクを task に書けるようにし、エージェント同士の交渉プロトコルをプロンプトで促す。

受け入れ基準:
- 三目並べが最後まで成立する。worktree分離で同時編集が衝突しない。自由ロール指示で分担交渉→実装が回る。
```

---

## 運用メモ（CCに毎回言わなくてよいよう、ここに集約）

- 各フェーズの最後に必ず動作確認（build通過＋手動シナリオ）。フェーズ境界を越えた先走り実装はさせない。
- 数値（holdSec / progressIntervalSec）は実測値を使う。未測定の断定をさせない。
- bundle id・MCP設定キー・claude://の挙動は「推測で埋めず実機/最新ドキュメントで確認」を徹底（CLAUDE.md §10）。
- ライセンスは MIT か Apache-2.0 を最初に決めて LICENSE を置く（OSS公開前提）。
```
