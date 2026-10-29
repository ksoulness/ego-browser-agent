# ego-browser-agent

一个通用技能包：让 **Codex / DSH / 以及后续接入的任何 agent** 共用同一台 [ego lite](https://lite.ego.app) 浏览器，而各自持有自己的持久 TaskSpace、互不踩踏。

> A single `SKILL.md` shared by every agent on the machine. The only per-agent difference is a one-line `AGENT-NAMESPACE.txt` sitting next to it — that is the agent's TaskSpace name. No `spaceId` is ever hardcoded.

- 目标运行时：`ego-browser 0.6.1.13` / guide `v2.1.0` / chromium `156.0.8078.48` / node `v24.22.1`（Windows 实测）
- 技能正文 SHA-256：`6073F9842709B5422C73D07A5A461408F125501DBBCBE627045148B4497D6107`
- 许可：MIT

## 它解决什么

多 agent 同机开浏览器时，真正会打架的不是“谁来开浏览器”，而是这五件事：

| 冲突点 | 本包的做法 |
|---|---|
| 入口分裂（各家 agent 自带 Playwright / Chrome / CDP） | 唯一入口 = `ego-browser` CLI + `TaskSpace`/`Page` API；其余一律禁止 |
| 抢同一个空间 | 一个 agent 一个持久空间，名字来自 `AGENT-NAMESPACE.txt`（如 `codex`、`dsh`） |
| 硬编码 `spaceId` 失效 | 一律按名字解析；零匹配时按名字重建（ego 重启/升级会丢空间，属正常） |
| 页面把预算吃光 | 预算**按空间**计，本机实测 8/8；本包另加“优先复用 `p1` + 本机 5 页本地策略” |
| 任务结束把空间删了 | 普通任务**不调** `task.finish()`，只 `page.close()` 自己的页面，保留持久空间 |

## 安装

Windows PowerShell（不需要管理员）：

```powershell
# 给 Codex 装
pwsh -NoProfile -File .\install.ps1 -AgentName codex

# 给 DSH 装
pwsh -NoProfile -File .\install.ps1 -AgentName dsh

# 装到自定义技能根（部分宿主不扫描默认目录时）
pwsh -NoProfile -File .\install.ps1 -AgentName codex -SkillsRoot "D:\path\to\skills"
```

默认安装到 `%USERPROFILE%\.agents\skills\ego-browser-agent\`：

```text
ego-browser-agent\
  SKILL.md              # 所有 agent 逐字节相同的正文
  AGENT-NAMESPACE.txt   # 一行，本 agent 的空间名（无 BOM、无换行）
```

`-AgentName` 必须是 `^[a-z0-9][a-z0-9._-]{0,47}$`。已存在的技能目录会先移到 `<SkillsRoot>\.ego-browser-agent-backup-<timestamp>\`，不覆盖、不删除。

验证：

```powershell
pwsh -NoProfile -File .\install.ps1 -AgentName dsh -VerifyOnly
```

预期输出 `OK`，并核对 `SKILL.md` 的 SHA-256 与下文一致。

## 装完之后

把 [`AGENT-USAGE.md`](AGENT-USAGE.md) 交给目标 agent（或让它随技能一起被读到）。它规定了执行顺序：加载技能 → 读命名空间 → `ego-browser skill` 读到结束标记 → 每轮一个 `.mjs` → 观察再操作 → 需要人时 `handOff()` → 收尾不 `finish()`。

给 agent 的一句话版本：

```text
浏览器任务只能加载 ego-browser-agent 技能；空间名取自技能目录旁的 AGENT-NAMESPACE.txt；
每次先跑 `ego-browser skill` 读到结束标记；普通任务结束不调用 finish()，只关自己的页面。
```

## 已知坑（全部为实测，不是推测）

1. **环境变量不会传进脚本。** 指南原文：*"It also does not inherit your shell's environment variables: `process.env` will not contain values you set before running `ego-browser`"*。bash 前缀、`export`、PowerShell `$env:` 三种写法实测都到不了脚本 —— 所以身份必须来自文件或脚本内字面量，不能靠注入。
2. **页面上限按空间计，不是全局。** `EGO_PAGE_BUDGET_REACHED Page budget reached (8/8) in space "<name>".` 是本机实测值；运行时更小则以运行时为准。
3. **ego 重启/升级会让所有空间消失**（实测重启后 `codex` 与 `dsh` 双失，同名字空间 `spaceId` 从 10 变成 3）。所以绝不能硬编码 ID。
4. **`release(label)` 不释放预算**，它只把 `unknown`（用户开的）页面交还用户；对 Agent 页面直接报错 `page pN was created by the agent; close it instead of releasing it`。预算满了用 `page.close()`。
5. **`loc=css:xxx` 在 `waitForSelector()` 里可能超时**，而同样元素用裸 CSS `"#xxx"` 立刻命中。
6. **`page.fill()` 会因“零尺寸”失败**：`element has a zero-sized bounding box`，此时改用 `page.evaluate()` 写值并派发 `input` 事件。
7. **截图参数是 `fullPage`**，不是 `scope: "full_page"`。
8. **不要动 vendor 技能目录** `~/.agents/skills/ego-browser`（JUNCTION，ego 升级会覆盖），也不要用 `finish()` 之外的方式删空间；ego 没有删空间 API，只能由用户在界面关闭。

## 兼容性

| 项 | 状态 |
|---|---|
| Windows + PowerShell 7 / Windows PowerShell 5.1 | 实测可用 |
| macOS / Linux | 未验证（脚本为 PowerShell；技能正文与平台无关） |
| ego-browser | `0.6.1.13`（guide `v2.1.0`）实测；升级后请重跑 `ego-browser skill` |

## 文件

```text
SKILL.md             技能正文（通用，不含任何 agent 专属事实）
AGENT-USAGE.md       给目标 agent 的执行手册
install.ps1          安装/校验（-AgentName / -SkillsRoot / -VerifyOnly）
SHA256SUMS.txt       发布物校验和
```

## 许可

MIT，见 [LICENSE](LICENSE)。ego lite 本身由 Citro Labs 提供，与本仓库无隶属关系。
