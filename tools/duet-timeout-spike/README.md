# duet-timeout-spike

リスク検証専用の使い捨てMCPサーバー。一つの問いだけに答える:

> **Codex.app と Claude Code（Claude Desktop）の MCPクライアントは、1回のツール呼び出しの応答を
> 何秒まで待つか。定期的な進捗通知（progress notification）でその上限は伸びるか。**

得られる2値が本体Duetの `await_reply`（ロングポーリング）を決める:
- `holdSec` … 1回の待機でどこまでブロックしてよいか
- 進捗間隔 … 進捗通知でタイムアウトをリセットさせる場合、何秒ごとに送るか

計測が終わったら捨ててよい。

---

## 0. 配置とローカル動作確認（アプリ不要・30秒）

Duetリポジトリ内に置く想定:
```
/path/to/Duet/tools/duet-timeout-spike/
```

```bash
cd /path/to/Duet/tools/duet-timeout-spike
npm install
npm run smoketest
```

期待出力（要点）:
```
[client] connected, tools: ping, probe_block, probe_block_progress
OK   ping(...)                            waited=0.0s
OK   probe_block({"seconds":2})           waited=2.0s
   progress 1/4 .. 4/4
OK   probe_block_progress({"seconds":4})  waited=4.0s   ← 基準2sでも進捗でリセットされ完走
FAIL probe_block({"seconds":3})           waited=1.0s -> Request timed out  ← 進捗なし1s上限で失敗
```
最後の2行が肝。「進捗を送れば短いタイムアウトを越えられる／送らなければ上限で切れる」を示す。

---

## 1. サーバー起動（本体Hubと別ポート、例 8799）

```bash
PORT=8799 npm start
# -> http://127.0.0.1:8799/mcp で待受。ログは ./spike.log にも追記。
```

---

## 2. 各アプリに一時登録

### Claude Code（add-json, ユーザースコープ）
```bash
claude mcp add-json spike '{"type":"http","url":"http://127.0.0.1:8799/mcp"}' -s user
claude mcp list        # spike ... ✓ Connected
```

### Codex（`~/.codex/config.toml`）
```toml
[mcp_servers.spike]
url = "http://127.0.0.1:8799/mcp"
```
```bash
codex mcp list         # spike ... enabled
```

---

## 3. 実機での測り方（各アプリのチャットで指示）

1. 疎通: 「spike の ping を呼んで」→ 即返ればOK。
2. 素の上限（進捗なし）: 「spike の probe_block を seconds=10 で呼んで」を
   `10 → 30 → 45 → 60 → 90 → 120 → 180` と上げる。**最初にエラーになった秒数の手前が素の上限**。
3. 進捗で伸びるか: 「spike の probe_block_progress を seconds=180, everySec=5 で呼んで」。
   完走すれば延命が効く。結果の `hadProgressToken`:
   - `true` … そのアプリは進捗を要求＝延命が使える。
   - `false` … 要求しない＝延命は効かない。`holdSec` を素の上限内に収める。
4. 毎回 `./spike.log` を併読。アプリがエラーでもログに `probe_block COMPLETE seconds=120` があれば
   「サーバーは完走、クライアントが先に諦めた＝その秒数は上限超え」と確定できる。

記録:
```
Claude Code: 素の上限 ___s / 進捗延命 ___（hadProgressToken=__）
Codex      : 素の上限 ___s / 進捗延命 ___（hadProgressToken=__）
```

---

## 4. 結論の出し方（→ config/duet.config.json へ）

- 進捗が効く（両アプリ true で長秒数も完走）:
  → `await_reply` は進捗を「素の上限の半分」間隔で送り続ける。`holdSec` は長め（数分）でよい。
- 進捗が効かない（片方でも false／進捗ありでも切れる）:
  → `holdSec`/`noProgressHoldSec` を素の上限より少し短く。`empty` 即再アームで繋ぐ。
- 両アプリで値が違えば **厳しい方（短い方）に合わせる**。
- 補足: Claude Code は `.mcp.json` の該当サーバーに `"timeout": 600000`（10分）等でツールタイムアウトを
  延長できる。Codex 側に同等設定が無ければ Codex の素の上限が律速。

計測後は一時登録を外す:
```bash
claude mcp remove spike -s user
# Codex は config.toml の [mcp_servers.spike] を削除
```

---

## 5. 補助: ローカルドライバ（任意）

アプリを介さずサーバーを叩く。**このSDKクライアントの挙動を測るだけで、実アプリの上限ではない**点に注意。
```bash
PORT=8799 npm start
node probe-client.mjs                      # 自己テスト
node probe-client.mjs block 60 30          # 60s作業 / 30s上限 → 失敗するはず
node probe-client.mjs progress 120 5 30    # 120s作業 / 5sごと進捗 / 30s基準 → 進捗で完走するはず
```

---

## ファイル

```
duet-timeout-spike/
  src/index.ts        # MCPサーバー本体（ping / probe_block / probe_block_progress）createApp/buildServerをexport
  inproc-test.mjs     # 単一プロセス自己テスト（npm run smoketest）
  probe-client.mjs    # 任意のローカルドライバ
  package.json  tsconfig.json  .gitignore  README.md
```

## ツール仕様
- `ping()` → `{ ok, serverTime }`。疎通確認。
- `probe_block({ seconds })` → seconds 秒ブロックして返す（進捗なし）。素の上限測定。
- `probe_block_progress({ seconds, everySec })` → everySec 秒ごとに進捗通知しつつ seconds 秒ブロック。
  結果に `hadProgressToken`（アプリが進捗を要求したか）と `progressSent` を含む。
