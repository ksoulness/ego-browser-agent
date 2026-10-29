# 给 Agent 的使用说明

本包安装的是 `ego-browser-agent` v3.0.0。浏览器任务开始时按以下顺序执行。

## 1. 加载技能与身份

1. 完整读取 `SKILL.md`（与本文件同目录）。
2. 读取同目录 `AGENT-NAMESPACE.txt`：一行，无 BOM，即本 agent 的持久空间名（例如 `codex`、`dsh`）。
3. 确认 `ego-browser` CLI 可用。
4. 运行 `ego-browser skill`，把输出读到结束标记：

```text
[ego-browser:skill] end of guide v2.1.0
```

输出被截断、结束标记缺失或 CLI 不可用时停止并报告，不换其他浏览器。

> 身份只能来自文件或脚本内字面量。`process.env` 不含你在命令行设置的值（指南原文明确），不要试图用环境变量传身份。

## 2. 每轮脚本

不要把多行 JS 塞进 `-e`。每轮写一个 UTF-8 `.mjs`，再用单行入口运行：

```powershell
ego-browser nodejs -e "await import('file:///C:/absolute/path/round-01.mjs')"
```

`.mjs` 顶部用文件里的命名空间恢复空间：

```js
const fs = await import("node:fs/promises");
const NS = (await fs.readFile("C:/absolute/path/to/ego-browser-agent/AGENT-NAMESPACE.txt", "utf8")).trim();

const matches = (await listTaskSpaces()).filter((space) => space.name === NS);
if (matches.length > 1) throw new Error(`Multiple spaces named ${NS}; stop`);
if (matches.length === 1 && matches[0].ownership !== "agent") {
  throw new Error(`${NS} space is user-owned; explicit claim required`);
}

const task = matches.length === 0
  ? await taskSpace(NS)               // 零匹配属正常：ego 重启/升级后重建
  : await taskSpace(matches[0].id);

console.log({ spaceId: task.spaceId, name: task.name, ownership: task.ownership });
```

若唯一匹配空间属于 `user` 或已交还，只有用户本次明确要求接管时才使用 `claimTaskSpace(entry.id)`；否则停止并询问。不要猜、改名、删除或新建备用空间。

## 3. 页面操作

1. 优先复用 `p1`，用 `page.goto()` 导航，不要每页都 `newPage()`。
2. 操作前先观察：`await page.url()`、`page.title()` 或 `page.snapshot()`。
3. 用 snapshot ref、`loc=css:`、`loc=role:`、`loc=href:` 或 `text=` 定位；等待元素时裸 CSS 更稳。
4. 导航后等待 `waitForLoadState()`、`waitForSelector()` 或 `waitForURL()`，不要固定 sleep；异步渲染的列表用短轮询而不是一次判定。
5. 一次脚本推进一组有依赖的动作，结束时输出下一步需要的最小页面状态。

## 4. 安全与接管

- 登录、密码、MFA、验证码、扫码、支付确认、文件选择器和浏览器权限提示必须 `await task.handOff()`，说明用户要做什么并结束本轮。
- 提交、发送、发布、购买、删除、授权、账户或权限变更必须有当前任务范围内的明确授权。
- 不读取或修改 Profile，不清 Cookie、缓存或存储，不按进程名关闭浏览器。
- 不进入其他 Agent 的空间或 `ego builtin ...` 内部空间。

## 5. 收尾

- 正常结束不调用 `task.finish()`，保留持久空间。
- 用 `page.close()` 关闭自己创建且不再需要的页面，默认保留至多 1 个工作页。
- 只有用户明确要求关闭空间时才调用 `finish()`，且只调一次。
- 最终报告实际 `spaceId`、页面 label、URL、标题和验证结果。
