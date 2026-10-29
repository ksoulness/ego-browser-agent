---
name: ego-browser-agent
description: 当需要打开或操作网页、填写表单、点击、截图、提取页面数据、登录或做 Web QA 时使用。唯一获授权的浏览器是 ego lite（ego-browser CLI），固定复用本 Agent 自己命名空间下的持久 TaskSpace。禁止 Playwright / browser-use / browser-harness / Chrome for Testing / Edge / 直连 CDP / 默认浏览器。
metadata:
  version: "3.0.0"
  date: "2026-10-29"
  target: "ego-browser 0.6.1.13 / guide v2.1.0"
  family: "generic（同一份文件供 Codex / DSH / 其他 agent 共用）"
---

# ego-browser-agent（v3，通用版）

本文件是**通用技能包**：Codex、DSH 以及后续接入的 agent 安装的是**同一份
`SKILL.md`**，差别只在技能目录旁边的 `AGENT-NAMESPACE.txt`（一行，本 agent 的空间名）。
技能正文不含任何 agent 专属事实，也不含任何 `spaceId`。

## 0. 事实基线（可复核，别凭记忆推断）

| 项 | 值 | 复核命令 |
|---|---|---|
| CLI / 内核 / node | `0.6.1.13` / chromium `156.0.8078.48` / node `v24.22.1` | `ego-browser --version` |
| 运行时指南 | guide `v2.1.0`，本机 550 行 | `ego-browser skill` |
| 指南结束标记 | `[ego-browser:skill] end of guide v2.1.0` | 同上；缺了就是被截断 |
| vendor 技能位置 | `<user>/.agents/skills/ego-browser` 是 **JUNCTION** → `<user>/.local/share/ego/ego-skills` | `dir /AL <user>\.agents\skills`；升级会覆盖它，别改 |
| 页面预算 | **由运行时按空间配置**；本机实测第 8 个 `newPage()` 报 `EGO_PAGE_BUDGET_REACHED Page budget reached (8/8) in space "<name>".` | 8/8 只作本机现场证据，本包另采更严的 5 页**本地策略**；运行时更小则以运行时为准 |
| 空间存活 | 跨 `ego-browser` 进程按名字复用；**ego lite 重启/升级/用户关闭后空间消失** | `listTaskSpaces()` 零匹配属正常 |
| 关页 vs 交还 | `page.close()` 关 Agent 页面；`release(label)` 只把 unknown 页交还用户、**不关标签**，对 Agent 页直接报错 `page p2 was created by the agent; close it instead of releasing it` | guide 183–185 行 |

指南随版本变。任何 API 不确定：先 `ego-browser skill` 重读，或 `help()` / `help("page.click")` 取签名。

## 1. 每次浏览器任务的前置

1. 公开、无需登录态、无需 JS 渲染的内容优先 `fetch` / API / `web_search`，不无故开浏览器。
2. `ego-browser skill`，读到结束标记。被截断就重定向到文件再分段读。
3. `ego-browser` 不存在 / `skill` 未知 / 读不到结束标记 → **停手报告**，不换浏览器兜底。
4. 不自行升级 ego。仅当输出含 `[ego-browser:notice]` 且用户明确批准，才 `ego-browser upgrade`，升级后立刻重跑 `ego-browser skill`。升级会丢空间，批准前先告知用户。

## 2. 身份与命名空间（本包唯一的 agent 差异点）

- 空间名 = **本 agent 自己的命名空间**，来自技能目录旁的 `AGENT-NAMESPACE.txt`（一行，小写短横线 slug）。
- 该文件缺失、为空、含多行或含空白以外异常字符 → **停手，问用户**。不要猜、不要默认、不要借用别的 agent 的名字，更不要自己发明一个。
- 示例绑定（由各 agent 安装时各自填写，不写进技能正文）：
  - DSH → `dsh`
  - Codex → `codex`
- 一个 agent 只有一个持久空间，名字**不随目标变化**（不要 `dsh-某任务`）。
- 名字是全局唯一键；`ownership` 只有 `user` / `agent`，**没有 per-agent 身份** → 同名就是共享空间，隔离只能靠不同名字。
- `spaceId` 由 ego 分配，不能指定、不能写死、不能跨机器复制。恢复入口永远是**名字**。
- 绝不进入、读取、操作别人的空间（例如 DSH 不碰 `codex`）；`ego builtin ...` 之类 ego 内部空间也不要动。

## 3. 解析或创建自己的空间

```js
// NS 来自技能目录旁的 AGENT-NAMESPACE.txt（一行）
const NS = "<AGENT-NAMESPACE>";
const hit = (await listTaskSpaces()).filter((s) => s.name === NS);
if (hit.length > 1) throw new Error("发现多个同名空间，停手报告");
let task;
if (hit.length === 0) {
  task = await taskSpace(NS);              // 重启/升级/用户关闭后的正常路径
} else if (hit[0].ownership === "agent") {
  task = await taskSpace(hit[0].id);       // 恢复
} else {
  // 空间属 user 或已交还：必须先拿到用户本次的明确要求
  if (!USER_APPROVED_CLAIM) throw new Error("空间归属 user：需用户明确要求后才能 claimTaskSpace");
  task = await claimTaskSpace(hit[0].id);
}
console.log({ spaceId: task.spaceId, name: task.name, ownership: task.ownership });
```

- `listTaskSpaces()` 条目字段只有 `createdBy / id / name / ownership / profileId / profileName / recentTabTitles / taskId`。
- 唯一同名且属 user 或已交还 → 需用户**本次明确要求**才 `claimTaskSpace(id)`；无授权就停手问。
- `claim` 之后 `finish()` **不能删除空间**，只会把它变回 `ownership: "user"` 并留一个 `about:blank`；CLI 没有删空间 API，真删除只能由用户在 ego lite 界面关闭。
- `takeOverTaskSpace()` 只对**进行中**的空间有效；对已 `finish()` 结束的空间无效，必须先 `claim`。
- 跨进程取用户页面用 `task.userPage()`；同一脚本内等控制权用 `waitForControl()`。
- 多空间/状态异常/无法唯一判断 → 停手报告。不得改名、删除或另建备用空间绕过。

## 4. 页面：预算、受管与未受管

- 默认 1 个工作页；换网址优先 `goto()` 复用，必须同屏并存才 `newPage()`。
- `await task.pages()` 只返回**受管**页面；`await task.tabs()` 返回空间内全部标签
  `{ label?, page, targetId, title, url, active, openedBy }`。没有 `label` 的是未受管标签，操作前先 `adopt(page, { as? })`。
- `task.page(label)` 只查已存在的页面，句柄**恒为 truthy**：`if (!page)` 与 `task.page("p2") || await task.newPage()` 都判断不出缺失。只用真实输出过的 label 或 `await task.pages()`。
- label 形如 `p1 / p2 / p3`，永久稳定，优先用 label 而非自定义 `{ as }`。
- **关自己的页面用 `page.close()`**；`release(label)` 只用于把来源未知页面交还用户（标签保留），对 Agent 页会报错（见 §0）。
- 预算报错（`EGO_PAGE_BUDGET_REACHED`）→ 用 `page.close()` 关掉本空间内 `openedBy: agent` 且已用完的页面；不关用户或 `unknown` 的页面；无法安全回收就停手报告。
- 本地策略：本 agent 同时存活页面**自限 5 个**（policy 常量，不是 API 常量）；运行时若先报更小预算，以运行时错误为准。
- 任务结束不 `finish()`：保留持久空间，用 `page.close()` 清掉自己不再需要的页面，留 1 个工作页。
- `finish({ keep })` 只能调一次，会结束整个任务并连带失效所有 page label；只有用户明确要求关闭该空间时才用。

## 5. 观察与交互

- 先观察再动手：`await page.url()` / `page.title()` / `page.snapshot()`。
- 定位：snapshot ref `@21` / `ref=21`；`loc=css:#id`；`loc=role:button[name='Sign in']`；`loc=href:`；`text=...`；模糊名 `loc=role:...[name*="..."]`。
- 等待用 `waitForURL` / `waitForSelector` / `waitForFunction`，不要 sleep 猜时间。
- 高影响动作（提交、发送、发布、购买、删除、授权、改账户/权限）必须先有本次任务范围内的明确授权；动作后用 url / title / snapshot / 返回值核验，不以"已点击"代替成功。
- 需要 Playwright 语义时停一下：`locator()` / `getByRole()` / `context()` / `route()` / `expect()` **都不存在**；缺口用 `page.evaluate()` / `page.cdp(method, params)`。

## 6. 执行路线（Windows 上最容易翻车）

- bash：可直接 heredoc 投递一段 JS。
- PowerShell：不要用 `-e` 塞多行或中文。每轮写 UTF-8 `.mjs`，用纯 ASCII 单行入口：
  `ego-browser nodejs -e "await import('file:///C:/绝对路径/round-01.mjs')"`（正斜杠）。
- 每次调用都是新 Node 进程：JS 变量不跨轮，空间与页面保留 → 每轮重新解析空间、重新观察。
- 一轮只推进一组有依赖的动作。

## 7. 用户接管

必须暂停并交用户：登录/密码/MFA/验证码/扫码、账户或身份选择、支付确认、浏览器权限提示、文件/设备选择器、屏幕录制/麦克风/摄像头授权、用户正在操作或空间不可控。

```js
await task.handOff();
```

结束后本轮、说明需要用户做什么；不 `finish()`、不新建空间。用户确认后重新解析**同一个**空间继续。

## 8. 截图与识图

- 截图落**绝对路径**（见 §10 的临时目录约定），再用本机识图能力读；不把 base64、整页 HTML 或大段 snapshot 塞进上下文。
- 跨 agent 约定只要求产物可定位，不绑定具体识图工具。

## 9. 隔离与安全

- TaskSpace 只隔离页面/工作区，**不隔离 Profile**：cookie、登录态、站点权限与其他 agent 共享。
- 不读、不改、不复制 Profile；不清 Cookie / 缓存 / 存储 / 会话数据（确需清理：先读 vendor 技能 `references/clearing-state.md`，并要用户批准——有些清理会打到整个 Profile）。
- 不按进程名批量关闭浏览器；不启动/重启/杀 ego 进程（会丢空间与用户标签）。
- 不动别人的空间、不动 `ego builtin ...` 内部空间、不连 CDP 端口、不碰其他浏览器。
- 不在脚本、日志、文件名、输出里写密码、令牌、Cookie、私钥；敏感中间产物用完即删。

## 10. 排障表（错误原文 → 处置）

| 现象 | 处置 |
|---|---|
| `EGO_PAGE_BUDGET_REACHED Page budget reached (N/N) in space "..."` | 用 `page.close()` 关自己 `openedBy: agent` 的旧页；`release()` 关不掉也救不了预算 |
| `page pN was created by the agent; close it instead of releasing it` | 你把 `release()` 用在 Agent 页上：改用 `page.close()` |
| `EGO_TASK_SPACE_NAME_IN_USE` | 重新 `listTaskSpaces()`；唯一同名才按 ownership 接管，否则停手 |
| `This task space is no longer assigned to the agent...` | **硬停**，不 retry；等用户明确要求后再 `claimTaskSpace(spaceId)` |
| `skill` 输出没有 `end of guide` | 输出被截断：落文件后分段读，不猜 API |
| PowerShell 中文/多行报错或乱码 | 改写 `.mjs` 全 UTF-8，`-e` 只放 ASCII 单行 `await import('file:///...')` |
| `task.page("p2")` 有句柄但操作失败 | 该 label 不存在（`page()` 恒 truthy），改用 `await task.pages()` |
| 动作已发出但页面没变 | url/title/snapshot 复核 + `waitForSelector`，不要重复点击 |
| 登录/验证码/权限弹窗 | `handOff()` 交人 |

## 11. 收尾与清场

- 正常收尾：`page.close()` 自己的多余页面，保留本 agent 的持久空间，不 `finish()`。
- 临时脚本与截图放 `<userHome>/ego/<目标>-<时间戳>/`，轮次命名 `round-01.mjs`、`round-02.mjs`；结束删内容只留空目录。
- 不在空间里留无主页面；不把 label 写进长期文档。

## 12. 验收（改完技能或换 agent 后跑一遍）

1. `ego-browser --version` 与 `ego-browser skill | tail` 都正常，结束标记在。
2. 技能目录旁 `AGENT-NAMESPACE.txt` 只有一行且符合 slug。
3. 解析空间后打印的 `name` 必须等于该文件名内容；`spaceId` 每次可不同。
4. `page.close()` 能让 `tabs()` 数量减 1；`release()` 对 Agent 页报错（本条即 API 语义自检）。
5. 收尾后 `listTaskSpaces()` 里本 agent 空间仍在，且没有多余 Agent 页面。
