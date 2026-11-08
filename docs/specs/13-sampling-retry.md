# Pulse 十三期技术设计（首包：采样失败手动重试合流）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 13 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。

> 一期至十二期正文不改写。一期写明失败进「采样中 / 失败」态、不假装 0；各资源页失败空态已有次按钮「重新采样」，但 `retrySampling` 会立即清态并另开 unstructured `Task`，与 `loopTask` 的 `SamplingClock` 周期 tick 重叠——**本文只覆盖那条调度缺口**：失败空态冷静重试，手动与定时请求共享同一单在途 sample。不改菜单栏、不开 GPU / 全表 ring / 新 Tab / 新 cadence / 新权限 / 新算法 / 恐吓文案 / 额外持久化。不新增自动定时重试、指数退避或进度条。已有周期循环是产品既有行为，不暗删、不偷偷变间隔。

**已锁定**：十三期 = **采样失败手动重试（合流）**。谁：主窗已落在采样失败冷静空态的人。情境：点次按钮想再采一帧，不要骨架闪一下、不要和后台周期 tick 打成两趟。成功：空态仍显示失败说明（主句不动；指向按钮的「重新采样」改为 **重试**，内存总览副句精确为 **这轮采样没有回来，点重试再试。**），下面次按钮 **重试**；点后同一空态出现 **正在重试…** 且禁止重入；成功回现表；仍失败回同一空态、按钮恢复。说明词与次按钮统一「重试」，**不再**把「重新采样」当失败空态按钮术语。这是十三期已锁范围，不是另核、不是文档以后再改。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`；Sampler / Top5 series / 选中生命周期**不改**。前台 **1.5s**、后台 **3s** 常值不变（`SamplingPace`）。零新 timer、零新 VM、零第二路 Mach。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：用户 + 产品锁定的十三期 Must（十二期② 仅上涨开关已合 #42 / `27482ad`）；对照现实现（`MemoryDashboardVM.start` / `loopTask` / `SamplingClock` / `retrySampling` / `tick`；`MemorySampler.sample()` 为 Actor **同步**方法；`ProcessTablePane` 与各 Overview 失败空态均调 `retrySampling`；`SamplingCore` 能测 `SamplingPace`，测不到 VM）。

## 范围（相对一二三四五六七八九十十一十二期）

| 项 | 一二三四五六七八九十十一十二期 | 十三期首包 |
| --- | --- | --- |
| 定位 | 失败空态有「重新采样」；`retrySampling` 立即清 `loadState` / 快照 / 行 / 历史并另开 `Task tick` | **合流**：同一单在途 sample；空态不闪；旧结果不得盖新状态 |
| 采样周期 | 前台 1.5s、后台 3s；`SamplingClock` 400ms wake 只为 `setForeground` | **常值不改**。不新开 cadence、不新开 timer、不暗删 loop |
| Sampler | 单 Actor、`sample()` 同步返回 `Result` | **零 Sampler 改动**。不取消、不拆内部任务、不以 Actor 串行冒充会话时序 |
| VM 生命周期 | 单 `loopTask` + `started`；`setForeground` 只改 step | **loop 保留**。去掉 retry 的第二路 unstructured `Task` |
| 失败空态 | `loadState == .failed`（及进程表 `processListFailed`）走 `AppEmptyState` +「重新采样」 | **做**：主句不动；说明里指向按钮的「重新采样」→ **重试**（如「点重试再试」）；次按钮 **重试**；重试中 **正在重试…** + 禁重入。非按钮指称不机械替换 |
| 菜单栏 A / B | 失败灰点 /「暂时读不到」 | **本刀不碰**。重试中 `samplingFailed` 仍真，灰点不回绿 |
| 增长 / 仅上涨 / Top5 | 九 / 十二期有界投影 | **不改**。重试点击不双清 `topMemorySeries` / 误清 `selectedPid` |
| GPU / 新 Tab / 全表 ring | 灰置 / 无 / 禁止 | **仍禁止** |
| 自动重试 / 退避 / 进度条 | 无（只有既有周期 loop） | **不新增**。既有 loop 照跑，不是本刀发明的「失败后自动再试」 |
| Helper / entitlements / Electron | 无 | **仍无** |
| 恐吓文案 | 禁止 | **仍禁止** |

一二三四五六七八九十十一十二期验收与公证路径不因本文重开。前期 TECH 正文不改写；主窗失败空态的按钮术语与指向按钮的说明指称以**本文**为准（覆盖「重新采样」按钮及「点重新采样再试」这类指称）。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

本刀落在 **纯 Swift 请求门闩**（与 `SamplingClock` / `SamplingSession` / `SamplingPace` 同层），**不是**新 Actor、不是新 timer、不是 VM 上一个没合流的 `isRetrying` 布尔。

- 现成 `loopTask` **仍是唯一**调用 `sampler.sample()` 的消费者。手动重试只向门闩登记「请现在采」，必要时打断当前 `Task.sleep`，**不**另开 `Task { await tick() }`
- `MemorySampler` 仍是同一 Actor、同一 `sample()`；增长 Top5、选中 pid ring 仍由这一趟写入
- Views 失败空态仍观察同一 VM；重试中 chrome 是门闩状态的投影，不是第二条采样通道
- 菜单栏继续只读 `snapshot` / `samplingFailed`，不调 `sample()`、不画「正在重试…」

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids` / Mach。
- 不改 `Pulse.entitlements`、不改公证脚本、不改 `SamplingPace` 1.5s / 3s、不改 `SamplingClock.wakeSliceNanoseconds` 的职责（仍只为前后台）。
- 自身占用仍优先：重试不得把在途 sample 加成两趟。
- 增长信号、仅上涨过滤、菜单栏 B **本刀不碰**。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `MemoryDashboardVM`、`SamplingPace.swift`、`MemorySampler.sample()`、`ProcessTablePane`、各 Overview、`Package.swift` 的 SamplingCore 切片。本刀必须按「已有 / 没有」落笔，**禁止**把 Actor 串行读成「已经单在途」，也**禁止**取消 `sample()` 调用方 Task 后假定结果不会回来。

| 现字段 / 调用 | 文件 | 十三期怎么用 |
| --- | --- | --- |
| `loopTask` + `SamplingClock.plan` / `recordSleep` | `MemoryDashboardVM.start` | **保留为唯一消费者**。`plan.sample` 为真才 `tick`；sleep 可被手动重试打断 |
| `SamplingPace` 1.5s / 3s | `Sampling/SamplingPace.swift` | **常值不改**。前后台只换 step，不派生自动重试 |
| `SamplingClock` 400ms wake | 同上 | **仍只服务 `setForeground`**。重试立即采靠打断 sleep + `pendingImmediate`，不拿 wakeSlice 当重试延迟 |
| `SamplingSession.setForeground` | 同上 + `PulseAppDelegate.applyPace` | **不改**。关窗 / 后台只拉长间隔 |
| `retrySampling()` | VM | **今日缺陷**：`loadState = .sampling` 切骨架；清 snapshot / rows / 四条 history / `samplingFailed`；`Task { await tick() }` 与 loop 重叠。十三期改成只 `gate.requestManualRetry()`，不清态、不另开 Task |
| `tick()` | VM | 仍 `await sampler.sample()` 后按今日成功 / 失败规则写回。**加门闩 flight 承认**：过期结果丢弃。成功选中逻辑原样（pid 不在 `rows` 才清） |
| `MemorySampler.sample()` | `Sampling/MemorySampler.swift` | Actor **同步**方法，无内部 Task、无取消令牌。`await sample()` 只是 hop 进 Actor；调用方 Task 被取消**停不了**已开始的 `sample()`。**零改动** |
| Actor 隔离 | 同上 | 两个 `await sample()` 会**排队各跑一整趟**，两份 `Result` 都能回到 MainActor 写 VM。串行 ≠ 单在途，更 ≠ 会话时序 |
| `LoadState` | `MemoryModels` | 仍 `sampling \| ready \| failed`。**不**加 `.retrying`（会把 Overview 切走失败空态）。重试中保持 `.failed` |
| `AppEmptyState` | `Views/SharedUI.swift` | 今日按钮永远可点、无次要行。本刀加：禁重入 + 可选「正在重试…」次要行。**不用 `ProgressView`**。`retryTitle` 与含按钮指称的 message 按锁词表 |
| 失败空态调用 | Overview / CPU / Network / Disk Overview + `ProcessTablePane` 内存失败 / 进程列表失败 / 资源表失败 | **七处都走同一 `retrySampling`**。同一门闩、同一 chrome、**同一「重试」锁词**，不按 Tab 分叉 |
| `CPUPageCopy` / `NetworkPageCopy` / `DiskPageCopy` | `Models/*Page.swift`（已在 SamplingCore） | `retry` → **重试**；`failureMessage` 里「点重新采样再试」→ **点重试再试**。`failureTitle` 不动。内存总览 / 进程列表失败是 Views 内联，接线刀一并改 |
| `MemoryTablePhaseResolver` / `CPUPagePhaseResolver` | `MemoryTablePhase` / `CPUPage` | `loadState == .sampling` 才骨架。重试中必须保持 `.failed` / `.processListFailed`，否则闪骨架 |
| SamplingCore | `Package.swift` | VM / Sampler / Views **排除**。门闩必须 Darwin-free，才能 `swift test` |

**缺口（已核，不是采样算法缺口）**：

1. **双调用方**：loop 的 `tick` 与 `retrySampling` 的 unstructured `Task` 都能 `await sample()` 再 `apply`。旧帧可以晚于新帧写上 VM。
2. **取消语义对不上**：`sample()` 没有可取消的内部任务。取消 loop / retry Task 之后 `sample()` 仍会跑完；今日 `tick` 也不看 `Task.isCancelled` 或代次。**不要**拆活 Sampler 后假定 result 停止。
3. **清态闪烁**：按钮一拍把 `loadState` 打成 `.sampling` 并 `snapshot = nil` / `rows = []` / 历史 `reset`。失败空态被骨架替换；`selectedPid` 虽未直接 nil，行被清空后选择语义已丢。失败帧本身已经是空表——再清一次没有信息增量，只有闪。
4. **Clock 无提前唤醒**：手动 tick 不把 `elapsed` 置到期，也不打断 sleep。loop 醒过来仍可能再 `plan.sample == true`，叠第二趟。

因此本刀：

1. **零 Sampler 改动**（无新字段、不改 `sample()`、不第二路 Mach、**零新 period / cadence**）。
2. **单消费者 loop + 请求门闩**。所有「该采了」（时钟到期、首次 `needsInitialSample`、手动立即）都进同一门闩；已在途则只加入、不 `begin` 第二次。
3. **Flight token 只服务在途这一趟的结果承认**，不是给 VM 每个字段打全局世代，也不是新 timer。
4. **UI 不靠假布尔**：`isRetrying` 若暴露，必须是门闩 `retrying` 的投影；禁止 VM 另写一个与在途无关的 flag。
5. 重试点击**不清** snapshot / rows / 历史 / `selectedPid` / `detail` / `topMemorySeries` / `loadState`。

### 为何是门闩，而不是全局世代 / 新 timer / select 输入

| 候选 | 为何不作为本刀主轴 |
| --- | --- |
| 全局世代（VM 每个 @Published 一个 gen） | 过重。需要防的只是「另一趟 sample 的 Result 写回」。Sampler 内部 ring 已由单 `sample()` 串行推进；选中 / Top5 清语义仍走今日 `tick` 成功支。门闩在 **begin 时发一个 `UInt64` flight id、complete 时对上才 apply** 就够 |
| 新 timer / 失败后自动再试 / 指数退避 | 产品禁止。1.5s / 3s 已有；再开 timer 会变成第二 cadence |
| Go 式 `select` 输入 | Swift 没有廉价的 sleep-vs-retry select。等价保障：**单消费者 loop** + `pendingImmediate` + 打断当前 `Task.sleep`。两个输入（时钟到期、手动）在 `plan` 处收束；在途时两者都变成 join |
| 只加 `isRetrying` | 禁。按钮禁用解决不了双 `tick` 写回 |
| 取消 / 拆 Sampler 内部 Task | `sample()` 根本没有内部 Task。取消调用方不能当会话边界 |
| 依赖 Actor 串行 | 两趟都会跑完，两份结果都会回来 |

Flight id **不是**「全局世代计数」：它只在 `beginSample` 时 +1，只活在这一趟 in-flight 上，complete / 丢弃后回到 idle。首次启动的 `needsInitialSample` 仍走 Clock，origin 为节奏而非手动，**不**显示「正在重试…」。

### 门闩契约（可验收，Linux 可测）

建议名：`SamplingRequestGate`（可与 Clock 同文件或紧邻的 Darwin-free 文件）。形状可改，语义钉住：

| 输入 | 行为 |
| --- | --- |
| `requestManualRetry()` 且 idle | `retrying = true`，`pendingImmediate = true`；调用方打断当前 sleep。**不**清 VM 态。连点幂等 |
| `requestManualRetry()` 且 in-flight | **join**：`retrying = true`，**不** `begin` 第二次，**不**把 complete 后再排一趟。连点仍一 in-flight |
| `plan(clock, step)` 且 in-flight | `sample == false`（loop 此时本就堵在 `await tick`，不得再入） |
| `plan` 且 idle 且（Clock 到期 **或** `pendingImmediate`） | `begin`：发出 `flightId`，清 `pendingImmediate`，Clock 按今日到期规则把 `elapsed` 归零（与现 `plan` 到期支相同，故下一间隔仍是 1.5s / 3s） |
| `plan` 且 idle 且未到期 | `sample == false`，sleep 仍取 `min(wakeSlice, remain)`——既有节奏 |
| `accept(flightId)` | id 对上当前 in-flight → 允许 VM apply，然后 idle、`retrying = false`。不对 → **丢弃**，VM 一字不写 |
| `setForeground` | 只改 `SamplingSession.step`。门闩**不**因此 `begin`，不发明失败自动重试 |
| 首次 `needsInitialSample` | 照旧立即 `begin`；`retrying` 仍 false（冷启动骨架不是重试空态） |

打断 sleep：取消**这一段** `Task.sleep`（或等价 wait），不是取消 `loopTask`，更不是取消 `sample()`。被打断的那截剩余时间**不要** `recordSleep` 成「又到期了」。`begin` 已经把 `elapsed` 归零；下一拍完整 step。

Quit / 未完成 Task：取消 `loopTask` 后，已 hop 进 Actor 的 `sample()` 仍可能返回；`tick` 必须 `accept(flightId)` 失败或 `Task.isCancelled` / `self == nil` 则不 apply。不要泄漏第二条 retry Task（今日的 unstructured `Task` 正是泄漏源，本刀删它）。

### VM / UI 契约（逐项）

`retrySampling()` 只允许做：`gate.requestManualRetry()` + 打断 sleep。下面「点击时」= 这一拍。

| 字段 | 点击时 | `accept` 成功（今日 `tick` 成功支） | `accept` 失败（今日失败支） | 过期 / 取消的 Result |
| --- | --- | --- | --- | --- |
| `loadState` | **保持 `.failed`**（进程列表失败空态保持今日 `.ready` + `processListFailed`，不要改打成 `.sampling`） | `.ready` | snapshot 仍 nil → `.failed`；有 snapshot → 今日一样保持 `.ready` | 不写 |
| `samplingFailed` | **不改**（失败空态保持真，菜单栏继续灰点） | `false` | `true` | 不写 |
| snapshot / 各 host 速率 / rows / `processListFailed` | **不清** | 按帧写入（与今日相同） | **不清**（失败空态本来就是空表） | 不写 |
| `usageHistory` / cpu / network / disk 历史 | **不 `reset` / 不 `record(nil)`** | 按今日成功支 `record` | **不改** | 不写 |
| `topMemorySeries` | **不清** | 按帧覆盖 | **不清** | 不写 |
| `selectedPid` / `detail` | **不直接 nil**。成功支沿用今日：pid 不在新 `rows` 才清；试采期间合理选中保留是工程前提，不新开选择 API | 今日逻辑 | **不额外清** | 不写 |
| `retrying`（门闩投影） | `true`，按钮锁定 | `false` | `false`，按钮恢复，仍可再点 | 不把 UI 卡死在重试中：丢弃时若已 idle 则 `retrying == false` |

按钮锁定时机：`requestManualRetry()` **当下**（join 或即将 begin 都算承认手动意图），不必等 `sample()` hop 进 Actor。这才能禁止重入、并在 sleep 打断前就显示「正在重试…」。

`begin` 与结果代次：只有 `plan` 里那一次 `begin` 发 `flightId`；`tick(flightId)` 拿到 `Result` 后先 `accept`，再 apply。手动 join 的那一趟用的是**已经 begin 的节奏 flight**——这正是「不发起第二次」：结果就是这一趟，旧周期没有第二份回写。

## 建议工程顺序

门闩可测、VM 在 SamplingCore 外、Sampler 取消语义已核完。不要先开 Sampler PR。

合并后工程顺序（本文只锁设计；**本 docs PR 不写 Swift**）：

1. **门闩 + Clock 到期/立即 + 重试 chrome 谓词 + `swift test`**：`SamplingRequestGate` 与（若需要）Clock 的「立即到期」输入；`SamplingRetryChrome`（按钮 **重试**、指向按钮的说明 **点重试再试**、次要行「正在重试…」、`retrying` 时按钮禁用、失败相保持 `.failed` 而非 `.sampling`）。钉文末矩阵 1–8 能在 Linux 钉的部分。`Package.swift` 列入 SamplingCore。零 Sampler、零 AppKit。
2. **VM 单消费者接线 + 七处空态**：`retrySampling` 去掉清态与 unstructured `Task`；loop 用门闩 `plan` / `accept`；sleep 可打断；`AppEmptyState` 加禁用 + 次要行（**无 ProgressView**）；Overview ×4 与 `ProcessTablePane` 三处失败 / 进程列表失败走同一模型与**同一锁词**。成功选中逻辑不重开。

两刀都是小额可审：① 纯调度、Linux 可测；② 只把唯一消费者接到现成 loop / 现成空态。不一步塞进 Sampler。没有硬伤就不开第三条 polish PR。不要和 GPU / 全表 ring / 新周期捆在一起。合并不擅自写代码。

## UI 绑定

结论：只改**已有失败空态**的次按钮、指向按钮的说明指称、以及重试中次要行。各页失败**主句**不动。菜单栏不改。不用 ProgressView / spinner。

### 文案（已锁，工程刀就要改，不是以后另核）

说明词与次按钮统一 **重试**。失败空态不再使用「重新采样」当按钮术语。

只改**指向次按钮的指称**。自然中文，不造第二套词。

| 改 | 不改 |
| --- | --- |
| 次按钮标题「重新采样」→ **重试** | 失败主句（title）一字不改 |
| 副句里「点重新采样再试」→ **点重试再试**（其余字词、标点不动） | 「这轮采样没有回来」等副句其余字 |
| | 磁盘主句「暂时读不到磁盘数据，稍后重试」——这里的「重试」不是按钮标签，**不改** |
| | 「正在采样…」「采样中…」冷启动骨架；菜单栏「暂时读不到」 |
| | 非按钮指称的动作表述（不要见「重新采样」就整句替换） |
| | 函数名 `retrySampling` 等代码标识；一期至十二期 TECH 正文 |

精确锁定（接线与单测钉这些字符串）：

| 表面 | 主句（不动） | 副句（十三期） | 按钮 |
| --- | --- | --- | --- |
| 内存总览 | 暂时读不到内存数据 | **这轮采样没有回来，点重试再试。** | **重试** |
| CPU 总览 / 表失败 | 暂时读不到 CPU 数据 | 这轮采样没有回来，点重试再试。 | 重试 |
| 网络总览 / 表失败 | 暂时读不到网络数据 | 这轮采样没有回来，点重试再试。 | 重试 |
| 磁盘总览 / 表失败 | 暂时读不到磁盘数据，稍后重试 | 这轮采样没有回来，点重试再试。 | 重试 |
| 内存表 `.failed` | 进程列表还没有数据 | 总览还没回来，列表先空着。（无按钮指称，副句不动） | 重试 |
| 内存表 `.processListFailed` | 暂时无法列出进程 | **这轮没读到进程列表，点重试再试。** | 重试 |

重试中次要行仍是 **正在重试…**。`*PageCopy.retry` / `failureMessage` 与 `ProcessTablePane` 内联标题按上表改；这是本包范围。

### 调用点（全部遵循同一模型，不新增入口）

| 表面 | 今日 | 十三期 |
| --- | --- | --- |
| 内存总览 `OverviewSection.failureBody` | 「暂时读不到内存数据」+「这轮采样没有回来，点重新采样再试。」+「重新采样」 | 主句不动；副句 **这轮采样没有回来，点重试再试。**；按钮 **重试**；重试中同一空态 + **正在重试…** + 按钮禁用 |
| CPU / 网络 / 磁盘总览 failureBody | 各页 `*PageCopy.failureTitle` / `failureMessage` +「重新采样」 | 主句不动（磁盘主句「稍后重试」保留）；副句同上「点重试再试」；按钮 **重试** |
| 内存表 `.failed` | 「进程列表还没有数据」+「总览还没回来，列表先空着。」+「重新采样」 | 主句 / 副句不动（无按钮指称）；按钮 **重试** |
| 内存表 `.processListFailed` | 「暂时无法列出进程」+「这轮没读到进程列表，点重新采样再试。」+「重新采样」 | 主句不动；副句 **这轮没读到进程列表，点重试再试。**；按钮 **重试**。今日已有入口，不是新 feature |
| CPU / 网络 / 磁盘表 `.failed` | 各页失败文案 +「重新采样」 | 与对应总览同一锁词 |
| 冷启动 `.sampling` 骨架 | 「采样中…」/「正在采样…」 | **不改**。不是重试空态，不出现「正在重试…」 |
| 就绪表 / 名称过滤空 / 仅上涨空 | 无重试按钮 | **不改** |
| 菜单栏 | 灰点 +「暂时读不到」 | **不改**。重试中仍 `samplingFailed == true` |

重试中：**不要**切骨架、不要 `ProgressView`、不要进度条、不要把失败说明换成「重试中」。主句仍在；副句按上表（已改指称处不再出现「重新采样」）；「正在重试…」是按钮附近一条次要色短句（具体在按钮上 / 下由实现贴在 `AppEmptyState` 里，不新开第三种空态组件）。

有 snapshot 之后的后续 `sample()` 失败：今日 `tick` 只把 `samplingFailed = true`、`loadState` 保持 `.ready`（主窗仍显示旧表）。**本刀不把这条扩成新的失败空态**。既有周期 loop 会按 1.5s / 3s 再采——这是既有行为，不是新增自动重试。

### 明确不做（相对本刀）

- GPU Tab；新 Tab；全表 ring；新 Sampler cadence。
- 改菜单栏 A / B / Top3。
- 新权限 / Helper / XPC / 持久化重试状态。
- 指数退避、失败后额外定时器、ProgressView / spinner / 进度条。
- 恐吓文案、「泄漏」、假权限墙。
- 暗删 `loopTask` 或把 1.5s / 3s 改掉。
- 取消 / 拆 `MemorySampler.sample()` 内部工作。
- 仅加 `isRetrying` 却仍让 retry `Task` 与 loop 双 `tick`。
- 把已有失败说明主句改写成新文案包；见「重新采样」就整句机械替换（非按钮指称不动）。
- 失败空态再造「重新采样」按钮术语，或把说明指称与按钮拆成两套词。

## 风险

| 风险 | 应对 |
| --- | --- |
| Actor 串行被当成已经单在途 | 上文写死：两趟都会跑完；必须门闩 begin/accept |
| 取消 retry Task 后旧 `tick` 仍 apply | 删 unstructured Task；唯一消费者 + `accept(flightId)` |
| 点击清态闪骨架 / 丢选择 | 点击不清；`loadState` 保持失败相；选中只走今日成功支 |
| 打断 sleep 却 `recordSleep` 剩余时间导致立刻又到期 | 打断不记剩余；`begin` 归零 `elapsed`；下一间隔完整 step |
| 用 400ms wakeSlice 冒充「立即」 | 契约写死打断 sleep；wakeSlice 仍只为前后台 |
| 加新 timer / 失败自动再试 | 范围表禁止；既有 loop 不是本刀发明 |
| 菜单栏闪绿或出现重试文案 | 点击不把 `samplingFailed` 打假；B 不接线 |
| 双清历史 / 误清 `selectedPid` | 单 apply；点击路径禁止 reset / nil |
| 漏改按钮指称，或把非指称的「重新采样」动作句一并改掉 | 只改指向按钮的「重新采样」→「重试」；主句与其余字词不动；磁盘主句「稍后重试」不是按钮词 |
| Helper / GPU / 新 cadence | 范围表写死不加 |

## 验收（十三期首包）

产品 Must：

- [ ] 失败空态主句仍是今日句子；指向按钮的说明改为 **点重试再试**（内存总览副句恰为 **这轮采样没有回来，点重试再试。**）；次按钮 **重试**；点击后同一空态出现 **正在重试…** 且按钮不可重入。失败空态不再把「重新采样」当按钮术语
- [ ] 手动成功 → `loadState == .ready`，表回现；手动失败 → 同一空态、按钮恢复、可再点
- [ ] 手动与节奏共享**同一单在途** `sample()`；旧结果不能覆盖新状态
- [ ] 前台 1.5s、后台 3s 常值不变；不新开自动定时重试 / 退避 / 进度条；既有 loop 不暗删
- [ ] 重试点击不清 snapshot / rows / 历史 / `selectedPid` / `detail` / `topMemorySeries`，不切 `.sampling` 骨架
- [ ] Sampler Actor、VM、Top5、菜单栏不因本刀改语义
- [ ] 永不写「泄漏」/ leak / 「危险」；无假权限墙

测试矩阵（实现 PR 必须覆盖能 Linux 测的项；VM / GUI 标 Mac 剩余）：

1. 空闲失败态点重试：只 `begin` 一次；完成后下一间隔仍是 1.5s（前台）或 3s（后台），不是新 cadence
2. 节奏采样已 in-flight（测试里手控延迟未 `accept`）再点重试：不第二次 `begin`，`retrying == true`（join）；这一趟 flight 结算（成功或失败）只 apply 一次。再喂一个过期 / 不同 `flightId` 的 Result，`accept` 拒绝，不得第二次写 VM（这就是「旧周期回写」）
3. Clock 仍在 sleep / `elapsed` 未到期时点重试：下一次 `plan` 立即 `begin`，不等剩余 1.5s / 3s
4. 连点：仍一 in-flight；`requestManualRetry` 幂等
5. 手动失败：`accept` 失败支 → 仍 failed 相、锁词说明（点重试再试）、`retrying == false`、可再点
6. 手动成功：`accept` 成功支 → ready（VM 接线刀验收 apply；门闩刀验收 accept 后 idle）
7. `setForeground` 只换 step；门闩不因此多 `begin`，不新造自动重试
8. 首次 `needsInitialSample` 不是 retrying；`accept` 前取消 / quit：Result 丢弃；无第二条 Task 泄漏
9. 手动与周期同拍：历史 / `selectedPid` 只走一次成功支，不双 `reset`、不误 nil
10. 当前失败空态 / 其它 Tab 失败空态同一模型与同一锁词（按钮「重试」、有指称的副句「点重试再试」）；菜单栏 A / B、仅上涨、Top5 徽标不回退

明确不做（本包出现即不合格）：

- [ ] 无 GPU Tab、无新 Tab、无全表 ring
- [ ] 无新 Sampler cadence / 新 timer / 指数退避 / ProgressView
- [ ] 无菜单栏改动
- [ ] 无 Helper / XPC / 新 entitlements / 额外持久化
- [ ] 无恐吓文案、无「泄漏」、无自动杀
- [ ] 无「只加 isRetrying、仍双 tick」
- [ ] 无拆 Sampler 内部任务当取消
- [ ] 无失败空态「重新采样」按钮术语；无漏改「点重新采样再试」指称；无机械改非按钮指称

共性：

- [ ] 一二三四五六七八九十十一十二期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏 A / B / Top3 点选、详情增长、九期徽标、十二期仅上涨、退出链路）。失败空态按钮术语与指向按钮的说明指称以**本文**为准（覆盖「重新采样」按钮及「点重新采样再试」；四 / 八期 TECH 正文不改写）
- [ ] 冷启动仍默认内存页、仍先骨架再第一帧（不是重试 chrome）
- [ ] Linux：`swift test` 跑门闩 / Clock / chrome 谓词，以及已在 SamplingCore 的 `*PageCopy.retry` / `failureMessage` 锁词；**不声称 VM 测试或 Xcode GUI 已完成**
- [ ] 不改公证脚本与 entitlements

### Linux 可测 vs Mac 剩余

`Package.swift` 的 SamplingCore **排除** `ViewModels/`、`MemorySampler`、Views。门闩必须无 Darwin / 无 AppKit，才能在 Linux CI 实跑矩阵 1–8 的调度部分（用测试替身记录 `begin` 次数、延迟 `accept`、喂过期 `flightId`）。`CPUPageCopy` / `NetworkPageCopy` / `DiskPageCopy` 已在 SamplingCore：实现刀把 `retry` / `failureMessage` 锁词钉进现有 `*PageTests`。内存总览与进程列表失败内联在 Views，标接线刀 / Mac。

本 docs PR **不跑**、也不声称：

- `MemoryDashboardVM` 实例测试（不在 SamplingCore）
- Xcode GUI / 主窗点按钮
- 实机 `HostMemoryReader` 失败

Mac 冒烟（实现合并后、本机；不挡本文档验收）：

- 伪造 / 制造一帧 host 失败，落到失败空态：主句仍在；内存总览副句恰为 **这轮采样没有回来，点重试再试。**；按钮 **重试**；点后出现「正在重试…」、按钮禁用、无骨架闪；空态不再出现「重新采样」按钮术语
- 成功回表；再失败回同一空态
- 重试过程中等待下一周期：不得看到表闪两次或选中无故丢失
- 菜单栏灰点在重试中保持灰，弹出条不出现「正在重试…」
- 过期结果乱序：优先信 Linux 门闩单测；Mac 上若无替身 Sampler，只做「点重试时 loop 仍在跑」的观感确认，不宣称已注入乱序

## 工期

小：按「门闩 + 单测 → VM / 空态接线」拆两个工程 PR，天级，不是周级。调度本身纯 Swift；不要按 Sampler 改造估。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。本 docs 分支**不写 Swift**。
