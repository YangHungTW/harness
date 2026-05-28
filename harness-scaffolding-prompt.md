# Harness — Personal Claude Code Marketplace (with Observability)

> 把這整份貼進空資料夾的 Claude Code session 即可。先填好最上面三個 placeholder（尤其 `OWNER_EMAIL`）。

---

## 我要做什麼
在這個空資料夾建立一個「個人 Claude Code marketplace」，可以 push 到 GitHub
後，用 `/plugin marketplace add` 帶到任何機器、任何 client 專案；
並內建四個維度的可視性層（即時 / 單任務 / 跨任務 / 跨專案）。

## 變數（請以這些值取代）
- `MARKETPLACE_NAME`: harness            # 也是 repo name
- `PLUGIN_NAME`: yang-toolkit            # marketplace 內部的 plugin 名稱
- `OWNER_NAME`: YANG
- `OWNER_GITHUB`: YangHungTW
- `OWNER_EMAIL`: <我等下會填，先放 TODO>

## 動工前的事前作業（必做，不要跳過）
1. Web fetch 取得最新 plugin / marketplace / hooks / statusline schema，
   **不要靠記憶**：
   - https://docs.claude.com/en/docs/claude-code/plugins
   - https://docs.claude.com/en/docs/claude-code/plugin-marketplaces
   - https://docs.claude.com/en/docs/claude-code/hooks
   - https://docs.claude.com/en/docs/claude-code/statusline
   - https://github.com/anthropics/claude-plugins-official 的
     `.claude-plugin/marketplace.json`
   - https://github.com/anthropics/claude-code 底下 `plugins/` 任一官方 plugin
     當 plugin.json 對照組
2. 確認 `plugin-dev` plugin 是否已安裝（`/plugin` 看一下）；如果有，依它的
   skill 規範生成。
3. 把你查到的關鍵欄位（必填、optional、JSON schema、hooks event 名稱、
   statusline 介面）先在 chat 列出來給我確認，再開始建檔。

## 設計參考：從 YangHungTW/specaffold 借鏡
specaffold 是我之前做的 spec-driven workflow 系統，這個新專案**不繼承**它的
哲學，但有幾個技術設計值得借鏡。請 web fetch 以下檔案後納入設計參考：

- https://github.com/YangHungTW/specaffold/blob/main/README.md
  - `events.jsonl` 的事件流概念（我們的 `ledger.jsonl` 直接採用類似 schema）
  - SessionStart + Stop hook 的掛載方式
  - 「verb vocabulary」這種 explicit 狀態詞彙設計（ledger 的 outcome
    欄位也用受控詞彙，不要自由字串）
  - bash 3.2 portability 紀律（`statusline.sh` / hooks 都要遵守）
- https://github.com/YangHungTW/specaffold/blob/main/.claude/team-memory/README.md
  - global (`~/.claude/team-memory/`) + local (`<repo>/.claude/team-memory/`)
    兩層 memory 架構

**不要照抄 specaffold 的 spec-driven 角色或 stage 流程**——那套是 specaffold
的設計，這個新專案走 feature-dev plugin + 自製 4 個 domain agent 的輕量路線。

## 要產生的目錄結構
```
.
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   └── {PLUGIN_NAME}/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── agents/
│       │   ├── rails-dev.md
│       │   ├── solidity-dev.md
│       │   ├── client-manager.md
│       │   └── devops.md
│       ├── skills/
│       │   ├── today/
│       │   │   └── SKILL.md
│       │   ├── curate-claude-md/
│       │   │   └── SKILL.md
│       │   ├── dashboard/
│       │   │   ├── SKILL.md
│       │   │   └── templates/
│       │   │       └── dashboard.html      # HTML 雛形（見下方規格）
│       │   └── week/
│       │       └── SKILL.md
│       ├── commands/
│       │   ├── feature-dev-tracked.md
│       │   └── ledger-append.md
│       ├── hooks/
│       │   └── hooks.json
│       └── statusline/
│           └── statusline.sh
├── .gitignore
├── LICENSE          # MIT
└── README.md
```

## 各檔案內容要求

### marketplace.json
- 用最新官方 schema（含 `$schema` URL）
- owner: `name=OWNER_NAME`, `email=OWNER_EMAIL`
- 只列一個 plugin：source 用 `"./plugins/{PLUGIN_NAME}"`
- 寫好 description / category（productivity 或 development，你判斷）

### plugins/{PLUGIN_NAME}/.claude-plugin/plugin.json
- `name` = PLUGIN_NAME
- `version` = "0.1.0"
- `author` 填我
- `description` 寫「YANG 個人開發工具組：Rails / Solidity / 客戶管理 / DevOps
  agents + daily ops skills + 可視性層」

### agents/*.md
四個 agent 都用「最小有效骨架 + TODO」：
- YAML front-matter 含 `name` / `description` / `model` / `tools`（依官方目前 spec）
- description 一句話講這個 agent 處理什麼領域
- body 留 `## Responsibilities` / `## Constraints` / `## Examples` 三個 section，
  內容都是 `<!-- TODO -->`
- 內容主題各自為：
  - **rails-dev**: Rails / Ruby / 我既有 B&B + DeFi 專案
  - **solidity-dev**: Solidity / Morpho Blue / Cronos / ERC-4337
  - **client-manager**: 多 client contract 工作管理（不是 PM 軟體，是個人視角的
    客戶/任務切換）
  - **devops**: Synology NAS / Docker / Cloudflare Tunnel / 自託管服務

### skills/today/SKILL.md
- front-matter 包 `name=today`, description（強描述：什麼情境下該觸發）
- body 留 TODO，目的是聚合每日工作（GitHub PR、Jira issue、Slack mention、
  本機 markdown notes、各 client repo 的 `.claude/ledger.jsonl`）

### skills/curate-claude-md/SKILL.md
- front-matter 同上
- body TODO，目的是審計與生成巢狀 CLAUDE.md
- 提一句架構原則：upper 放技術規則，subdirectory 放業務邏輯與 domain invariant

### skills/dashboard/SKILL.md
- description: 讀當前 repo 的 `.claude/ledger.jsonl`，產出 HTML artifact
  做時間軸 + feature 狀態看板
- body 留 TODO，但要明確說：
  - 輸入：`.claude/ledger.jsonl`
  - 輸出：呼叫 Claude 內建視覺化或直接以 `templates/dashboard.html` 為基底
    填資料後輸出 artifact
  - 觸發時機：使用者問「最近做了什麼」「本專案進度」「dashboard」之類

### skills/dashboard/templates/dashboard.html（HTML 雛形 — 重點規格）
這個檔案要實際寫出來，不是 stub。要求：

**整體**
- 單檔 HTML，inline CSS + 一點 vanilla JS，不要外部 CDN（離線可用）
- 設計風格：dark mode 為主、低彩度、monospace 字體（資料感）
- 用 CSS Grid 切版，斷點：手機單欄、桌面三欄
- 頂部一個 `<script type="application/json" id="ledger-data">` 區塊，
  作為資料注入點，dashboard skill 之後把 ledger.jsonl 內容塞進來

**Section 1: 頂部 Header**
- 左：marketplace 名稱（harness）+ 當前 repo 名（變數）
- 右：最後更新時間 / 本週 session 數 / 本週 token 用量（三個數字大字）

**Section 2: 時間軸（橫向 timeline）**
- 以「天」為單位，最近 14 天
- 每一天一格，格內疊每個 session 的小色塊
- 色塊顏色依 outcome：merged=綠、in-progress=黃、abandoned=灰、failed=紅
- hover 顯示 tooltip：feature name / phase / files / tokens / PR link
- 用 div + CSS，不要用 SVG library

**Section 3: Feature 狀態看板（kanban-style，但純展示）**
- 四欄：Discovery / Architecture / Implementation / Review
- 每欄是該 phase 中的 feature 卡片
- 卡片內容：feature 名、最後動作時間、累計 tokens、最近 commit hash
- 卡片右上角顯示 agent 圖示（rails-dev / solidity-dev / client-manager / devops
  各用一個 emoji 或單字 badge）

**Section 4: 底部統計列**
- Token 用量分布（依 agent，水平 stacked bar，CSS 寫死）
- Tool call 熱度（最常用的前 5 個 tool）

**資料契約**
HTML 頂部用註解明確寫出預期的 ledger 欄位：
```
// ledger.jsonl 一筆 = 一個 JSON object
// {
//   "ts": ISO8601,
//   "feature": string,        // feature slug
//   "phase": "discovery"|"architecture"|"implementation"|"review"|"summary",
//   "agent": string,
//   "outcome": "in-progress"|"merged"|"abandoned"|"failed",
//   "files": number,
//   "tokens": number,
//   "tools": { [tool_name: string]: number },
//   "pr": string | null,
//   "commit": string | null
// }
```

**Mock 資料**
- 在 `<script id="ledger-data">` 塞 8–12 筆假資料，涵蓋四種 outcome、
  四個 agent、最近 14 天範圍內
- 假資料只是讓打開 HTML 就能直接預覽，dashboard skill 之後會覆寫

**JS 行為**
- DOMContentLoaded 後讀取 script tag 內 JSON
- 渲染三個 section
- 不做互動 filter，純展示（之後再加）

### skills/week/SKILL.md
- description: 跨 client repo 掃 `ledger.jsonl`，產出週報
- body TODO，但要列出預期掃描路徑的規格：
  - 從一個設定檔（例如 `~/.config/harness/repos.json`）讀「我關心的 repo 清單」
  - 對每個 repo 讀 `.claude/ledger.jsonl`
  - 輸出 markdown 週報：依 client 分組、依 feature 分組兩個視角

### commands/feature-dev-tracked.md
- description: 包 `/feature-dev`，每 phase 結束後落檔到
  `docs/decisions/{YYYY-MM-DD}-{slug}/0X-{phase}.md`
- body 寫成 prompt 形式（這就是 slash command 的 spec），明確要求：
  - 開始前建立目錄
  - 每 phase 結束時呼叫 Write 工具落檔
  - 最後一個 phase（summary）同時 append 一筆到 `.claude/ledger.jsonl`

### commands/ledger-append.md
- description: 手動補登一筆 ledger（漏記、事後追補用）
- body 用 prompt 形式，要求 Claude 問清楚欄位（feature / phase / outcome）
  再 append

### hooks/hooks.json
給最小可運作版本：
- `PreToolUse`：append tool call 到
  `.claude/logs/session-{YYYYMMDD}.jsonl`，欄位：ts / tool / params 摘要
- `SubagentStop`：更新 `.claude/state/current-agent.txt`
- `Stop`：寫一筆 summary 到 `.claude/ledger.jsonl`
  - outcome 預設 `"in-progress"`，使用者可後續用 `/ledger-append` 修正
- 用 json 內的 `_comment` 欄位標哪幾個 event 之後會擴充
- 注意：hooks 是寫在 client repo 的 `.claude/` 還是這個 plugin 內，
  依官方目前 spec 為準（先 fetch 確認）

### statusline/statusline.sh
- bash script，無外部相依（最多 jq）
- 讀 `.claude/logs/session-{today}.jsonl` 最後一筆 + `.claude/state/current-agent.txt`
- 輸出單行：
  `[harness] {agent} · {phase} · {files}f · {tokens}t`
- 找不到檔案時 graceful degrade，不報錯

### README.md
要包含：
- 一句話定位
- 安裝步驟（含 `/plugin marketplace add {OWNER_GITHUB}/{MARKETPLACE_NAME}`
  與 `/plugin install {PLUGIN_NAME}@{MARKETPLACE_NAME}`）
- 內含的 agents / skills / commands / hooks 清單
- **Observability section**，用 ASCII 圖解四個維度：
  ```
  即時 (statusline + hooks log)
      ↓
  單任務 (feature-dev-tracked → docs/decisions/)
      ↓
  跨任務 (ledger.jsonl → /dashboard)
      ↓
  跨專案 (~/.config/harness/repos.json → /week, /today)
  ```
- 每個 client repo 該約定俗成放的檔案結構：
  ```
  client-repo/
  ├── .claude/
  │   ├── ledger.jsonl       # commit
  │   ├── logs/              # gitignore
  │   └── state/             # gitignore
  └── docs/decisions/        # commit
  ```
- 「Personal use, no warranty」聲明

### .gitignore
Node + macOS + Claude Code 暫存（`.claude/sessions/`、`.DS_Store` 等）
注意：marketplace repo 本身不需要 ignore `.claude/logs/`，那是 client repo 的事，
但仍可以列著當參考。

## 完成後的驗證
1. 把 `marketplace.json` / `plugin.json` / `hooks.json` 全部 `jq .` 驗證 JSON 合法
2. 把每個 `.md` 的 YAML front-matter 用 `python -c 'import yaml; ...'` 確認 parse
3. 用瀏覽器（或 `file://` 開）打開 `skills/dashboard/templates/dashboard.html`，
   確認 mock 資料能渲染三個 section（你可以用 `open` 指令）
4. `tree -a -I '.git'` 列出最終結構
5. 給我一份「下一步該手動填什麼」的待辦清單，依優先級：
   - **P0**：能讓 plugin 跑起來的最小填空
   - **P1**：能讓可視性層產生有意義資料的填空
   - **P2**：nice-to-have

## 行為要求
- 不要憑印象寫 schema，先 fetch docs 再下筆
- agents / skills 內容**不要替我發明**業務細節，只留 well-structured stubs + TODO
- `dashboard.html` 是唯一例外：要寫到「打開就能看」的程度（含 mock 資料）
- 真有歧義再問我，最多一個問題；其它直接合理預設並在 README 註明
- 完成後不要主動 `git init` / commit，等我決定

---

## 跑之前的小提醒
- 如果 `plugin-dev` 還沒裝，先 `/plugin marketplace add anthropics/claude-code`
  然後 `/plugin install plugin-dev@claude-code-plugins`，Claude Code 生成時會
  引用官方 spec，schema 準確度高很多。
- HTML 雛形如果跑出來你想再改風格（例如配色換成跟 `clock.hung.engineer` 同調），
  可以丟一張現成的截圖給它當參考。
