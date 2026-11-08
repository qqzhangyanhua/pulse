# Pulse 十六期技术设计（首包：退出结果按 pid 留存与原处重试）

> 归档：这是第 16 期落地前的设计稿，写完后不再修改。当前实现以 [TECH.md](../TECH.md) 为准，后续期数可能已经改动这里的范围或口径。

> 一期至十五期正文不改写。一期把退出锁成侧栏 `terminate()`，失败后再 `forceTerminate()` + 系统确认；十一期起侧栏仍读 `selectedPid`；十二至十五期只动过滤 / 空态 / 菜单栏排序，**没有**按 pid 留存退出结果——**本文只覆盖这条主窗侧栏缺口**：本会话内最近一次普通退出 / 强退的结果跟 pid 走，用户回到该 pid 原详情原按钮即可手动重试；切到别的进程不串请求。A 的新发起才废弃 A 的上一 token；B 的选择或 B 的新动作不废弃 A 的有效 token，A 的回包只写 A。不重开十二至十五期，不改 Sampler 周期，不改强退确认 / 权限，不做自动重试、退出历史、通知中心、批量终止、按名称串身份。GPU Tab、全表 ring、新 cadence、恐吓文案仍不做。

**已锁定**：十六期 = **退出结果按 pid 留存与原处重试**。谁：主窗侧栏刚点过「退出」或「强制退出…」、结果还没看清或想再试一次的人。情境：今日结果挂在**全局** `quitPhase` / `quitMessage` 上，一切选 / 一切 pid 离开 `rows` 就被清掉，失败像没发生过；旧 `async` 回包还会写到新选中的进程上。成功：侧栏只在**本会话**记录该 pid 最近一次发起类型（普通退出 | 强制退出）以及可投影的三类可见结果——**退出中**、**失败（未退出）**、**已不在列表**；失败按 pid 留着，清选再选**仍在 `rows` 的同一 pid** 仍能看见失败并走原按钮；进程已不在列表是保留的可见状态，**不等于已成功**；同 pid 号以后再出现、又没有实例代次证明是同一进程时，**先当新进程、直接实时详情，不自动复活旧失败卡**。成功结束本次机会 = 清掉这次失败 / 重试展示，**不**新增成功横幅、**不**新增第四类可见「成功」态。

仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。退出仍走现成 `ProcessActions.terminate` / `forceTerminate` + 现系统 `NSAlert`。采样周期不变；**零新 Sampler period / cadence**。不新开 entitlements。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：Grok Bot 主控书面转达的十六期正式 Must / Won't，以及之后产品书面终修（失败详情卡不强制列表行选中；「已不在列表」≠ 成功；验收 A 采样缺席 vs 验收 B token 结算分开；退出中离表不得停在「正在退出…」；**同一 pid 复现先当新进程、能确认同一身份才恢复上次失败与手动重试、不抢当前选中**）。对照 main `64d596c42151f2e107d79605ca844e7f0cdc231f`（十五期② #53 已合；#51 / #52 / #53 均已合）的现实现，见「现模型里有什么」。本文是 DESIGN SCOPE，不是合并或实现授权。实现等本设计合并 + Grok merge gate 后再写 Swift。本 PR 不写 Swift、不合并。

开盘基线：

| 项 | 值 |
| --- | --- |
| base | `origin/main` `64d596c42151f2e107d79605ca844e7f0cdc231f`（`feat: 十五期② 内存页过滤空态双清接线 (#53)`） |
| 本 PR 改文件 | 仅 `docs/TECH.md`、`README.md`（索引加「十六期」） |
| 十五期旧分支 | **不改**（`cursor/period-15-filter-empty-design-15fc` / `cursor/memory-filter-clear-b-09a5` / `cursor/memory-page-filter-clear-wiring-ba46` 只作历史） |
| 并行 | 开稿时仓库 **无** 十六期 TECH / 实现 PR、无同名分支；本 agent 不抢并行合并 |

## 范围（相对一二三四五六七八九十十一十二十三十四十五期）

| 项 | 一二三四五六七八九十十一十二十三十四十五期 | 十六期首包 |
| --- | --- | --- |
| 定位 | 侧栏退出；结果是 VM 上**一份** `quitPhase` / `quitMessage`，跟选中绑定、跟 tick 清空 | **做**：本会话 per-pid 最近一次退出操作记录 + presence；原侧栏原按钮手动重试 |
| 退出 API | `ProcessActions.terminate` → `forceTerminate` + 系统确认 | **不改** API、权限、确认框文案 / 按钮 |
| 结果留存 | 切 `selectedPid` 即 `quitPhase = .idle`；pid 离开 `rows` 也清 | **做**：失败跟 pid 走；切选不串；采样不得把失败写成成功 |
| 已不在列表 | 今日当「没了」：清选中、清详情、退出中还会被打成 idle | **做**：旧实时详情和曲线**整卡**冻结，标 **「已不在列表／上次记录」**；进行中与失败都如此；不能停在「正在退出…」；不能点旧 pid 重试；失败历史留着，不称成功 |
| 同 pid 再出现 | 无此产品；pid 只是 `ProcessRow.id` | **终锁**：无实例代次 → **当新进程**，实时详情，**不**自动复活旧失败 / 重试卡。能确认同一身份才恢复失败卡与手动重试，且**不抢**当前选中 |
| 重试 | 用户再点同一侧栏按钮；无 token，回包写全局 phase | **做**：显式点击；按 pid 各自比对最新 token。同 pid 的新发起才废弃该 pid 的上一 token；别的 pid 的选择或新动作不废弃它 |
| 自动重试 / 轮询终止 | 无（`waitForExit` 只是一次操作内的短等） | **仍不做**。不新 Timer、不把后台 tick 当终止轮询 |
| 历史 / 通知 / 批量 / 跨启动 | 无 | **仍不做** |
| Sampler / 过滤 / 菜单栏 / 十五期双清 | 既有 | **不重开、不改周期、不改布局** |
| GPU / 新 Tab / 全表 ring / 新 cadence | 禁止 | **仍禁止** |
| Helper / entitlements / Electron | 无 | **仍无** |
| Mac 烟测 / 签名公证 | 八期清单；公证另路径 | **不作为本期交付** |

一二三四五六七八九十十一十二十三十四十五期验收与公证路径不因本文重开。十二期过滤谓词、九期 Top5、十三期采样重试、十四期菜单栏排序、十五期双清不重开。主窗侧栏退出结果的留存 / 原处重试 / 缺席冻结以**本文**为准（覆盖一期「失败态可见」但未按 pid 留存的实现缺口）。实现等本设计合并 + Grok merge gate 后再写 Swift。Mark 在技术设计合入后才可开工程。本 PR 不写 Swift、不合并。

## 架构（现实现，读仓库后的结论）

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

本刀落在 **Darwin-free 的 per-pid 退出操作记录 + presence 投影 + operation token**，不是第二套 VM，不是新侧栏页面，不是 Sampler 改周期，不是把 `MemoryDashboardVM` 整类塞进 Linux。

- 主窗表：`rows` → 过滤 → `visibleRows` → `ProcessTableSort.ordered` → `ProcessTablePane` `List(..., selection: $vm.selectedPid)`
- 侧栏：`ProcessDetailSidebar` 读 `vm.detail ?? selectedFallback`，页脚读**全局** `quitPhase` / `quitMessage`，按钮调 `quitSelected()` / `forceQuitSelected()`
- 退出：Views → VM → `ProcessActions` → `NSRunningApplication`（按 pid）+ `waitForExit` 短等
- 选中：`selectedPid` didSet 清 `detail` 并 `sampler.setSelectedPid`；成功 tick 里 pid 不在 `frame.rows` 则 `selectedPid = nil`

约束：

- 不新开第二套 VM、不新开第二路 Mach、不改 `sample()` 周期。
- 不把整份 Actor VM 放进 SamplingCore。Linux 只测纯函数 reducer。
- 不改 `Pulse.entitlements`、不改公证脚本、不改 `confirmForceQuit`。
- 自身占用仍优先：一次点击至多一个 in-flight `ProcessActions` **针对该 pid**；不做无界队列。

### 现模型里有什么（必须按「已有 / 没有」落笔）

对照 `Pulse/Actions/ProcessActions.swift`、`Pulse/ViewModels/MemoryDashboardVM.swift`、`Pulse/Views/ProcessDetailSidebar.swift`、`Pulse/Views/ProcessTablePane.swift`、`Pulse/Models/MemoryModels.swift`、`Pulse/Models/ProcessSelection.swift`、`Pulse/Models/MemoryGrowthRisingFilter.swift`、`Pulse/Sampling/ProcessEnumerator.swift`、`Pulse/Sampling/MemorySampler.swift`、`Package.swift`、`Tests/SamplingCoreTests/`。禁止把别处 agent 报告当成已核实源代码。**现测试目录对 `quitPhase` / `quitSelected` / `ProcessActionResult` 零覆盖。**

| 现字段 / 调用 | 文件 | 十六期怎么用 |
| --- | --- | --- |
| `quitPhase: QuitPhase`（`.idle \| .quitting \| .failed`） | `MemoryModels.swift` + VM `@Published` | **今日全局一份**。要改成**派生**，不得再当唯一存贮。产品三可见是 viewState，内部更细 |
| `quitMessage: String?` | VM | 今日失败文案全局一份。切 pid 即 nil。改为按当前侧栏 subject 从 per-pid 记录投影 |
| `selectedPid` didSet | VM L38–46 | **缺口**：`oldValue !=` 就 `detail = nil`、`quitPhase = .idle`、`quitMessage = nil`。切 B、点 x、tick 清选中都会把 A 的失败抹掉 |
| `quitSelected()` | VM L198–204 | 读**当下** `selectedPid`，`quitPhase = .quitting`，`await ProcessActions.terminate`，**不带 token**，回包无条件 `applyQuit` |
| `forceQuitSelected()` | VM L206–213 | 先 `confirmForceQuit`；取消则 `return`（今日碰巧不改 phase）。确认后同样无 token |
| `applyQuit` | VM L215–226 | `.exited \| .notFound` → 清选中 / 详情 / idle（看起来像成功）；`.requestFailed \| .stillRunning` → `.failed`。**不看**回包是否仍属于当前选中 |
| 成功 `tick` pid 不在 `frame.rows` | VM L349–358 | `selectedPid = nil`、`detail = nil`；若 `quitPhase == .quitting` 再打成 idle。`selectedPid = nil` 的 didSet **连 `.failed` 也会清掉** |
| `ProcessSelection.acceptedPid` | `ProcessSelection.swift` | 只认「pid ∈ 当前 `rows`」。列表行选中继续走这条，**不**把消失 pid 写回 List |
| `MemoryGrowthRisingFilter.selectedPid` | Filter | 仅上涨把无徽标 pid 清选中。名称藏行**不清**选中。这是过滤选中，不是 enumerator 缺席 |
| `ProcessRow.id` | `MemoryModels.swift` | `var id: Int32 { pid }`。字段：pid / name / bundleIdentifier / executablePath / cpu / rss / threads / disk rates。**无 `startTime`、无 generation** |
| `RawProcessSample` | `ProcessEnumerator.swift` | 只 `proc_pidinfo(PROC_PIDTASKINFO=4)`：rss、线程、user/system 时间 + 可选 rusage 磁盘。**无 `p_starttime` / `pbi_start_*`** |
| `ProcessIdentity` | 同上 | name + bundleIdentifier + path，**显示名缓存**，不是实例代次。禁止拿来当「同一进程」 |
| `MemorySampler.setSelectedPid` | Sampler | pid 一变就清选中 ring。pid 不在当帧 `rows` 则 `detailFrame` 返回 nil |
| `ProcessActions.terminate` / `forceTerminate` | `ProcessActions.swift` | `NSRunningApplication.terminate()` / `forceTerminate()` 的 Bool 只表示**请求是否交出**；随后 `waitForExit` 轮询 `isAlive`（`NSRunningApplication` 或 `kill(pid,0)`，EPERM 当活着） |
| `ProcessActionResult` | `MemoryModels.swift` | `.exited \| .notFound \| .requestFailed \| .stillRunning`。**没有**「内核确认已死」 |
| `confirmForceQuit` | ProcessActions | 系统 `NSAlert`「立即退出“name”？」/「立即退出」/「取消」。**本期一字不改** |
| `ProcessDetailSidebar.footer` | 侧栏 | 失败句 + 「正在退出…」+ 两按钮；`quitPhase == .quitting` 时两按钮 disabled。按钮**总是**打当前 VM 选中，无 pid 参数 |
| SamplingCore | `Package.swift` | 列入 Models / 部分 Sampling / MenuBarStatus；**排除** `ViewModels/`、`Views/`、`Actions/`、`MemorySampler.swift`、`ProcessEnumerator.swift` |
| 退出单测 | `Tests/SamplingCoreTests` | **没有** |

**缺口（已核，不是采样缺口、不是「再做一个历史页」）：**

1. 结果不是 per-pid：全局 `quitPhase` 在 `selectedPid` didSet、tick 离表、`applyQuit` 成功支三条路上被清。
2. 无 operation token：回包写全局 phase，看起来像写进了新选中。Must3 的边界是 **按 pid 各自比对最新 token**：A 自己的新发起才废弃 A 的旧 token；B 的选择或 B 的新动作不废弃、不改写 A 的有效 token。
3. pid 离开 `rows` 被当成「可以收摊」：退出中打 idle，失败被 didSet 清掉，侧栏回空态。产品要的是整卡冻结并标「已不在列表／上次记录」，进行中和失败都一样；不能停在「正在退出…」，不能点旧 pid，失败历史留着，不称成功。
4. `.exited` / `.notFound` 被 `applyQuit` 当成 UI 成功清场。产品三态**无成功**；匹配 token 的终局只把 `opportunity` 关掉。采样帧无此权利。缺席中性句可以留到用户清侧栏，不得再被 tick 改回失败。
5. 没有实例代次。同 pid 再出现**不能**声称同一进程。
6. Linux 测不到 VM / `ProcessActions` / SwiftUI 按钮。

因此本刀：

1. **不改** `ProcessActions` 的 terminate / forceTerminate / 确认框 / `isAlive` 语义。
2. **不改** Sampler `sample()` / cadence / Top5。
3. **加** Darwin-free 的 per-pid 记录 + presence + token reducer（SamplingCore）。
4. VM / 侧栏只投影该 reducer；列表选中继续 `ProcessSelection`（消失 pid 不进 List）。
5. 本期生产路径 **无身份证据**（`identityEvidence` 恒为 false，见下节），复现当新进程。不新写采样来伪造证据。

### 身份：现成没有 startTime / generation（本期默认新进程）

已核：`ProcessRow`、`RawProcessSample`、`ProcessIdentity`、`SampledFrame` **都没有**启动时间或代次。`ProcessRow.id` 就是 pid。macOS 上 `proc_pidinfo(PROC_PIDTBSDINFO)` 的 `pbi_start_tvsec` 或 `NSRunningApplication.launchDate` 都**没有**接到模型里。

产品终修（比「同 pid 再现还露旧失败卡」更明确，已拍板，不再等）：

- **同一 pid 复现也先当新进程**：直接实时详情，**不**自动复活旧失败卡 / 重试卡。
- **能确认同一身份**才恢复上次失败与手动重试，并且**不抢当前选中**。
- 成功结束本次机会后无旧失败 / 重试卡。
- 现模型没有实例代次 → **本期必须默认按新进程**，不可宣称已经识别同进程。
- 不可用进程名 / bundle / path 代替身份。

同 pid 再现的终锁（覆盖「同号就能看见旧失败 / 用待确认卡跟实时详情并列」）：

| 场景 | 终锁 | 不是 |
| --- | --- | --- |
| 清选再选、或切到 B 再切回 A，且 A **从未**离开本会话 `rows` | 仍是同一条 inRows 记录；侧栏再选 A 时**要**看到失败，原按钮可重试 | 不是跨启动历史，也不是 pid 复用 |
| 退出发起后 pid 离开 `rows`（进行中或已失败） | 旧实时详情和曲线**整卡冻结**，标 **「已不在列表／上次记录」**；不能停在「正在退出…」；不能点旧 pid；失败历史留在 store，不称成功。列表不强制高亮失踪行 | 不是成功、不是活着、不是终局 |
| 用户清选，且该 pid 已离开或随后离开 | store **保留待确认**（不结算、不称成功、失败历史还在）。侧栏可以是空态。这不是一张跟新进程并列的失败卡 | 不是把清选当成终局 |
| 同 pid **再出现**，现模型**无法**证明同一实例 | **默认新进程**：直接当前实时详情。不自动复活旧失败卡。不因为行上还是这个 pid 数字（或列表徽标）就留下退出操作 | 不是「pid 数字相同 = 同实例」 |
| 调用方**另行给出**同一身份证据 | 才恢复上次失败与手动重试。**不抢**当前已选的别的 pid，也不对另一个 pid 发这次退出 | 本期生产**没有**这份证据。单测注入 `true` 只证明 reducer，**不算**身份采样已实现、已验收 |

**现模型能否确认身份：不能。** `ProcessRow`、`RawProcessSample`、`ProcessIdentity`、`SampledFrame` 都没有 startTime / generation。pid 只是 `Int32`。名称、bundle、path、列表上涨徽标都不是实例证据。

**本期不新写实时身份采样，也不新写历史库来「解决」pid 复用。** 不改 `ProcessEnumerator`、不加 `launchDate`、不在缺席态追问 `NSRunningApplication`。复活旧失败**只能**在 reducer 收到显式身份证据时发生。VM 接线永远传「无证据」。无证据就保持待确认记录 + 屏幕上的实时详情。把这条不可在本仓库验到的身份识别写成「技术验收已完成」不合格。

Reducer 仍接收 `identityEvidence: Bool`，只为单测两支。`false`（生产）= 上表「默认新进程」。`true` = 只恢复**该 pid** 的失败与手动重试，且若列表当前选中是别人则不改选中。禁止用进程名填这个布尔。

## 内部模型（正交；产品三可见是投影）

不要用一个互斥 enum 同时表示「操作结果」和「还在不在表里」。那会在「退出中离表」「失败后离表」「失败后同号再现」上互打。

### 存贮（reducer 真源）

每个本会话碰到过退出操作的 pid 至多一条 **latest record**（不是无限历史）：

| 字段 | 含义 | 不是 |
| --- | --- | --- |
| `pid` | 发起时 point-in-time 捕获的 pid | 不是实例代次 |
| `kind` | `terminate` \| `forceTerminate`（最近一次**发起类型**） | 不是按钮文案 |
| `phase` | **仅** `quitting` \| `failed` | **无** `success`、**无** `absent`、**无** `idle` 当成功 |
| `token` | 单调 `UInt64`，每次用户点击 +1 | 不是时间戳 UI |
| `opportunity` | `open` \| `closed` | **不是**可见成功态。`closed` 只表示本次重试机会已结束 |
| `frozenDetail` | 离开 `rows` 那一拍拷贝的 `ProcessDetail`（行 + 当时曲线） | 不是新的历史 store；之后**不再 append** |
| `presence` | `inRows` \| `absentAndUnknown` \| `currentReappearedUnconfirmed` | 不是 operation phase |

另：全会话 `nextToken`。没有跨启动 persistence。App 退出即丢。

`QuitPhase.idle` 不再表示「成功了」，只表示「当前侧栏 subject 没有一条未结算记录」或「有记录但投影为新进程（不露失败）」或「机会已 `closed`、失败入口已关」。

`opportunity` 与 `presence` 正交：采样把 presence 打成缺席 **不得**把 `open` 改成 `closed`；匹配 token 的终局回包把机会 `closed` **不得**被之后的 tick 改回 `open` / `failed`。

### 派生 viewState（主控三类可见 + 复现新进程）

`viewState(record, listSelectedPid, sidebarSubjectPid)` —— UI 只认这个，文件里可以留一个 derived enum 方便侧栏 `switch`，**内部不得只存这一个**。

投影按下面顺序，**先命中先用**（这就是状态优先级，禁止用互斥 enum 把后项盖掉前项的存贮）：

| 顺序 | 投影 | 条件 | 侧栏 | 按钮 |
| --- | --- | --- | --- | --- |
| 1 | `liveAsNewProcess` | `presence == .currentReappearedUnconfirmed` 且 subject 是该 pid | **实时详情**（新进程）。**不**露历史失败 / 重试卡。`opportunity` 即使仍 `open` 或已 `closed` 都不把旧失败画出来 | 仅当该 pid **此刻**是当前合法选中：允许**新一次**当前操作（新 token） |
| 2 | `absentFromList` | `presence == .absentAndUnknown` 且 subject 是该 pid | 旧详情与曲线**整卡**冻结，标 **「已不在列表／上次记录」**。进行中与失败都走这里，**覆盖**「正在退出…」。`opportunity==open` 时失败历史与发起类型留着，不称成功；`opportunity==closed` 时没有失败卡 / 重试卡，也没有成功态，冻结标到正确清理 | **禁**。不能点旧 pid 重试 |
| 3 | `settledInRows` | `opportunity == .closed && presence == .inRows` | **无旧失败卡、无重试卡、无成功态**。pid 仍在表里就当当前进程，不要标「已不在列表／上次记录」 | 该次入口已关。之后 tick **不得**复活该次失败卡。用户若再点，是**新 token** |
| 4 | `failedStillPresent` | `opportunity == .open && phase == .failed && presence == .inRows` | 失败（未退出） | 对该 **当前合法选中** 可再试。再失败仍是本行 |
| 5 | `quitting` | `opportunity == .open && phase == .quitting && presence == .inRows` | 「正在退出…」 | 禁（in-flight） |
| — | `none` | 无记录，或 subject 不是该 pid，或中性卡已被正确清理且机会已 closed | 普通详情或空态 | 现规则 |

「running absent 同时曾有 failure」：`phase` 仍可以是 `quitting` 或 `failed`，`opportunity` 仍 `open`，`presence = absentAndUnknown`。UI **只**走第 2 行，**不清** `phase`、不把 `opportunity` 改成 `closed`。presence 盖住「正在退出…」，并不清 operation failure。

**正确清理**（中性缺席卡何时从侧栏拿走）：用户点侧栏关闭，或侧栏 subject 改到别的 pid。不是 tick、不是 Timer、不是把缺席写成成功。`opportunity==closed` 的记录清理后不得被下一帧 freshness 改回 `failed` 或点亮该次重试。`opportunity` 仍 `open` 时，清理只拿掉缺席卡的展示，**不**结算；用户之后只能对**当时**的当前合法选中新发起，不能从缺席卡重试旧 pid。

### 为什么必须正交（测试反例）

反例都要进刀①单测。若有人把 `QuitPhase` 扩成 `.idle \| .quitting \| .failed \| .absent` 互斥四态，下列会失败：

1. **退出中离表**：互斥会把 `quitting` 改成 `absent`，in-flight token 丢相。正交：`phase=quitting`、`presence=absentAndUnknown`；UI 已不在列表；回包仍按 token 结算或改 `failed`。
2. **失败后离表**：互斥 `absent` 盖掉 `failed`。再要求「失败历史仍保留」只能靠猜。正交：`phase=failed`、`opportunity=open` 不动，presence 变；整卡「已不在列表／上次记录」，不称成功。
3. **失败后同号再现、无代次**：互斥若写成 `failed` 会错误复活失败卡；写成新 idle 又把内存里的失败结算掉（采样无权结算）。正交：`phase=failed` 可留在内存，`presence=currentReappearedUnconfirmed`，UI **liveAsNewProcess、不露失败**。
4. **失败帧空表**：互斥若 `rows.isEmpty ⇒ absent/success` 会把 enumerator 失败当成全体死光。正交：`processListFailed == true` 的帧**禁止**改 presence、禁止结算。
5. **切到 B 时 A 的 `.exited` 才回来**：互斥全局 phase 会把 B 打成成功或清空。切选**不是** ignore 的理由。A 的 token 仍是 A 当前 record 时，完成只写 A 的 store（可关 A 的机会）；B 的 record、phase、选中都不变。只有 A 之后又合法开了新 token，旧 token 才 ignore。

### 列表选中 vs 失败卡（终锁关联规则）

两套身份，禁止混成一个 `selectedPid` 兼当「失踪进程的失败卡」。

| | 列表行 `selectedPid` | 侧栏 subject |
| --- | --- | --- |
| 必须 | ∈ 当前成功进程帧的 `rows`（现成 `ProcessSelection`） | 可以是刚离开 `rows`、仍有未结算记录的 pid（只为冻结卡） |
| pid 在 rows 且用户点了该行 | 高亮该行 | 该 pid 实时详情 + 若 `presence==inRows` 则叠加失败 / 退出中 |
| 用户点侧栏 x 清选 | nil | **空态**。store **保留待确认**（不结算）。人还在 `rows` 时再选回同一 pid，失败卡还在 |
| pid 在 quitting/failed 时离开 rows | **不得**把失踪 pid 写进 List（不强制行选中） | 若原先就在看该 pid：整卡「已不在列表／上次记录」。清选离开也只是待确认，不称成功 |
| 用户此时点选 B | B | 侧栏改看 B；B 的按钮只发 B；A 的记录仍在 store |
| 同 pid 再现、无身份证据（本期生产） | **不抢**当前选中：当前是 B 就留 B，也不对 B 发 A 的退出。若侧栏正在看这个 pid：收成**实时详情**，不露旧失败，不因 pid 数字留下退出操作 | 投影 `liveAsNewProcess` |
| 同 pid 再现、且调用方传入同一身份证据（仅单测注入） | **不抢**当前选中，不对另一个 pid 动手。用户自己再选中该 pid 才看到上次失败 + 手动重试 | 不是「生产已能识别同进程」。无证据源就不许走这条 |

过滤藏行（名称过滤）**不是** `rows` 缺席。仅上涨清选中也只清 List，不清 per-pid 退出记录。

## 输入、生命周期、边界

### 点击（point-in-time）

只对**当前合法选中**发起（`acceptedPid` 非空）。缺席卡不能点旧 pid。每 pid 至多一条 record，**新的一次合法发起可以取代该条**；「至多一条」不是把旧 token 永久锁死的理由。匹配只看 **该 pid 当前 record 的 token**，不看此刻 `selectedPid`。

**普通退出**（无确认框）：

| 该 pid 当前 record | 再点 |
| --- | --- |
| `phase=quitting` 且 `opportunity=open` 且 `presence=inRows`（连续 in-flight，没有缺席后再出现） | 忽略。不换 token，不开第二路 `ProcessActions` |
| 无记录、`failed`、或 `presence=currentReappearedUnconfirmed` | **新 token 取代该 pid 这一条**。`kind=terminate`，`phase=quitting`，`opportunity=open`，`presence=inRows`。只打这个当前合法 pid。此前 token 相对新 record 变旧，之后 ignore，不改选中、不改新 record |

**强退**顺序是 `pendingForceConfirmation` → 现有 `confirmForceQuit` → 通过且目标仍合法才发起。确认未返回**不是**第四个产品可见 phase，侧栏仍投影确认前的记录。只承认最新一次未返回的确认代次；更早的 Alert 返回一律不发起。

| 步 | 规则 |
| --- | --- |
| 点「强制退出…」 | 已有一次确认未返回则不再开第二个 `NSAlert`。捕获当时的合法 `selectedPid` 为 `targetPid`，以及本次确认代次。**不**写 `kind`，**不**把 `phase` 改成 `quitting`，**不**清旧 `failed`，**不**换 token |
| 取消 | 记录原样。旧 `failed` 仍可手动重试。不得变成 `quitting`。其它 pid 的在途回包仍按各自 token |
| 确认通过，但此刻 `selectedPid` 已不是 `targetPid`，或 `targetPid` 已不是当前合法选中 | **不发起**。不新造 `quitting`，不清旧 `failed`，不改现有记录。不改打现在的 B，也不对已失效的 pid 调用 `forceTerminate` |
| 确认通过，且 `selectedPid` 仍是当初的 `targetPid` 且仍合法 | 这时才 `nextToken++` 写入该 pid：`kind=forceTerminate`，`phase=quitting`，`opportunity=open`，`presence=inRows`。请求只打这个 pid。确认前的 token 变旧 |

确认通过后该 pid 已是 inRows 的 `quitting`：再点按上表忽略，不再开 Alert。禁止 Timer / 自动再点。`waitForExit` 仍只是这一次调用里的短等。

### 回包（只在 MainActor 对 token+pid）

`ProcessActions` 返回后：

- token **不是**该 pid **当前** record 的 token，或该 pid 没有 record → **整包丢掉**。这才是「旧回包」。切到别的 pid、清选、离表都**不**使原 token 变旧。匹配上则**只**改这一条 record，不改选中，不写另一个 pid。
- 一致且 `.requestFailed` / `.stillRunning`，且该 token 尚未处理过 → `phase = failed`，`opportunity` 保持 `open`（未退出，保留 / 更新失败入口）。presence 不动。
- 同一 token 的失败回包再到达 → **幂等**：仍是 `failed` + `open`，不另开一条、不改 token。
- 一致且 `.exited` / `.notFound`，且 `opportunity` 仍 `open` → **只关本次机会**：`opportunity = closed`。**无旧失败卡、无重试卡、不新增成功态。** 不把 `presence` 改写成成功。若此时已缺席，整卡仍可标「已不在列表／上次记录」直到正确清理，但那是冻结观测，不是成功态，也不是失败卡。这不是「核证已死」。
- 同一 token 的 `.exited` / `.notFound` 再到达 → **幂等**：保持 `closed`，不复活失败、不出横幅。

切选、清选、离表、新采样、取消强退确认都不结算，也不改该 pid 当前 token。B 的选择或 B 的新发起**不**废弃 A 的有效 token。A 的回包只更新 A。只有 A 自己的新发起才使 A 的上一 token 失配。

### 验收 A vs 验收 B（必须分开写、分开测）

**A. `rows` 缺席 / 采样新鲜度（采样帧本身）**

只允许：

- 用**成功的进程列表帧**（`processListFailed == false`）更新 presence：pid 不在 `rows` → `absentAndUnknown`；从缺席回到 `rows` 且无身份证据 → `currentReappearedUnconfirmed`。
- 缺席那一拍把当时 `detail` **整份**拷进 `frozenDetail`（详情和曲线一起），之后冻结、无新点，整卡标 **「已不在列表／上次记录」**。进行中与失败都这样。保留 `kind` 与最近 `phase`。`opportunity` 保持原值。不称成功。
- `processListFailed == true`、失败采样、少样本 / freshness 不足（没有一份成功进程列表可以当观测）：**不**改 presence、**不**清失败、**不**推导成功、**不**关 `opportunity`。

禁止：

- 把缺席或 freshness 不足写成 `.idle` / 「已成功」/ `opportunity=closed`。
- 改 `phase`（A **不得**改 `quitting`/`failed`，也不得把已 `closed` 的机会改回 `failed`）。
- 清退出 failure，或给旧缺席 pid 一个重试按钮。
- 暗示 `terminate` 因此生效。
- 把冻结曲线当活跃采样，或给失踪 pid 继续 `setSelectedPid` 追加 ring。
- 新开第二条全表 / 退出历史曲线 store。

`phase` 在 A 路径保持原值。退出中或失败后离表：整卡改为 **「已不在列表／上次记录」**，不能停在「正在退出…」，不能点旧 pid；store 里的失败或仍在 `quitting` **留着**，等 B 路径的回包。缺席是观测，不是操作终局，不称成功。

**B. 机会结算（只有原退出 operation 的 completion）**

只有「发起时 token+pid」匹配、且来自**这一次** `ProcessActions.terminate` / `forceTerminate` 已有返回值里的 `.exited` / `.notFound`，才能把该记录的 `opportunity` 设为 `closed`、拿掉旧失败卡和重试卡。不新增成功态。若 presence 已是缺席，冻结标「已不在列表／上次记录」可留到正确清理，但不是失败卡也不是成功态。采样帧、freshness、presence 变化、切选、重新选中、Cancel **无此权利**，也不能换成另一个 token 的身份。

`.exited` / `.notFound` 的诚实含义见下节：关机会 ≠ 真死。已 `closed` 之后，后续 tick / freshness **不得**再把该次写成 `failed` 或点亮该次退出按钮。

### `ProcessActions` completion 实际提供什么（不要 API true = 确死）

已核 `ProcessActions.swift`：

| 返回 | 何时 | 保证 |
| --- | --- | --- |
| `.requestFailed` | 无 `NSRunningApplication` 但 `isAlive`，或 `terminate()` / `forceTerminate()` 返回 false | 请求没交出或进程仍像活着 |
| `.notFound` | 发起当下无 `NSRunningApplication` 且 `isAlive == false` | 发起当下看不到该 pid，**不是**「我们刚把它杀成功」 |
| `.exited` | `terminate`/`forceTerminate` 已交出后，`waitForExit` 在 2.5s / 2s 内某次 `isAlive==false` | **轮询窗口里看起来不在**。`isAlive` 是 `NSRunningApplication` 或 `kill(pid,0)`（EPERM 当活） |
| `.stillRunning` | 等到超时仍 `isAlive` | 未退出 |

`app.terminate() == true` 只表示 Apple API 接受了退出请求，**随后仍可能 `.stillRunning`**。pid 在等待期间复用、enumerator 漏列、SIP 进程 EPERM，都会让 `.exited` 与「真死」错位。因此：

- **禁止**第四类可见「成功」。
- **禁止**用 tick 里「突然不在 rows」去印证 `.exited`，也**禁止**为了凑 `.notFound` 再打一轮 `NSRunningApplication` 或 `kill`。
- 关机会只表示「这次重试入口结束」，**不新增成功态**。pid 若仍在成功帧 `rows` 里，不标「已不在列表／上次记录」；无旧失败卡。该次失败卡不得被下一 tick 复活。用户再点是新 token。同 pid 之后再现且无身份证据：实时详情，仍然没有旧失败卡。
- `.notFound` **已经是**今日 `ProcessActions` 的返回值之一（见上表「发起当下」），不是本期要新加的 API，也不是每次退出都必须出现的结果。发起时应用还在，调用会走 `terminate()` / `forceTerminate()` 然后 `waitForExit`，结束时更常是 `.exited` 或 `.stillRunning`，**不会**为了终局再变成 `.notFound`。reducer 只处理**这一次调用实际返回的那一个**枚举；返回 `.stillRunning` 就保持失败入口，**不**自动再轮询直到 `.notFound`。

`waitForExit` 内部 25 次 `Task.sleep` 是**这一次用户操作的完成等待**，不是产品「自动重试 / 后台轮询终止」，本期不拆、不延长、不改成 Timer 重试，也不加第二段「直到 notFound」的轮询。

### 事件与什么不是操作终局

操作终局只有一件事：这一次点击发出的 `ProcessActions` 调用返回，且 token+pid 仍指向该记录。终局值只取它**真实返回**的 `.exited` 或 `.notFound`（关机会）以及 `.requestFailed` / `.stillRunning`（失败入口）。不要假定每次都能拿到 `.notFound`，不要为没有返回的终局造一个新机制。

| 事件 | 算不算操作终局 | reducer |
| --- | --- | --- |
| 普通退出的合法新点击 | 新操作开始 | 新 token 取代该 pid 这一条。连续 inRows `quitting` 的连点除外 |
| 强退确认未返回 / 取消 / 返回时目标已不是当初那个合法 pid | 否 | 不新造 `quitting`，不清旧 `failed`，不开第二个 Alert，不改打别的 pid |
| 强退确认通过且目标仍是当初的合法 pid | 新操作开始 | 此时才写入新 token 并 `phase=quitting` |
| 同 pid 仍是 inRows `quitting` 的连点 | 否 | 忽略，不换 token |
| `currentReappearedUnconfirmed` 上的显式点击 | 新操作开始 | 新 token **取代**该 pid 的旧 record，只打当前合法 pid。旧 token 之后 ignore |
| 匹配该 pid **当前** token 的 `.requestFailed` / `.stillRunning` | 失败终局（入口留着） | 只改这一条。同 token 再来：幂等 |
| 匹配该 pid **当前** token 的 `.exited` / `.notFound` | **唯一**能关掉本次机会的终局 | 只改这一条：`opportunity=closed`。无成功横幅。不看 `selectedPid` |
| 相对该 pid 当前 record 的 stale token | 否 | 整包 ignore。切走本身不制造 stale |
| 切选 / 清选 / 点 x | 否 | 不撤 token，不把 A 的完成写到 B |
| 成功帧里该 pid 离开 `rows` | 否（观测） | presence→缺席；整卡「已不在列表／上次记录」；`kind`+最近 `phase` 留着；不关机会；不称成功 |
| 失败帧 / `processListFailed` / freshness 不足 | 否 | phase、opportunity、失败入口都不动 |
| 同 pid 再现且无身份证据 | 否 | 当新进程实时详情；不自动露旧失败；不因 pid 数字留退出操作。之后的点击是当前合法选中上的**新**操作 |
| 已 `closed` 之后的 tick | 否 | 不得改回 `failed`，不得点亮该次重试 |

优先级（同一条记录上多信号叠在一起时，投影按上一张表，存贮按本表）：

1. **再试后又失败**（新 token 或同 token 的失败回包，且人还在 `rows`、机会仍 `open`）→ 失败卡 + 可再试。再失败一次仍是这张卡。
2. **操作终局 `.exited` / `.notFound`** → 关掉该次入口和机会。之后的 tick / freshness 不能把它变回失败，也不能复活该次退出按钮。缺席中性句可以留着，成功横幅不加。
3. **只有缺席、没有终局回包** → 机会仍 `open`（失败或退出中留在 store），但缺席卡**不提供**对旧 pid 的重试。用户清侧栏、重选一个仍在表里的进程、或同号再现成当前合法选中之后，才能走**当时**的当前合法操作（新点击、新 token）。这与「已不在列表不准重试旧 pid」是同一条，不是第二套自动重试。

### `selectedPid` / `quitPhase` / `quitMessage` 现重置路径 → 本期

| 今日路径 | 今日效果 | 本期 |
| --- | --- | --- |
| `selectedPid` didSet 任何变化 | 清 detail、`quitPhase=.idle`、清 message、`sampler.setSelectedPid` | **禁止**清 per-pid store。切换 subject / 清 List 选中。A 的记录留下。Sampler 仍可按**列表合法选中**重绑 ring（失踪 subject 不要活采） |
| `applyQuit` `.exited/.notFound` | 清选中 + idle | 改为 token 匹配才走验收 B 结算；不匹配 ignore |
| `applyQuit` `.requestFailed/.stillRunning` | 全局 `.failed` | 写入该 token 的 `phase=failed` |
| tick：pid ∉ `frame.rows` | 清选中 / detail；quitting→idle | 验收 A：presence 缺席 + 冻结；**不清** failure |
| tick：`processListFailed` / 失败采样 | 不走那条离表支（失败支不改 rows） | 明确钉：失败帧不得改 presence |
| `applyRisingOnlySelection` 清选中 | didSet 会误清退出态 | 只清 List 选中；退出记录不动 |
| 侧栏 x | `selectedPid = nil` → didSet 清退出态 | 空侧栏 + 保留 store |
| `retrySampling` | 不清 selectedPid | 仍不清退出 store |
| `confirmForceQuit` 取消 | `return`，phase 不动 | 确认前就不写 `quitting`。取消后旧 `failed` 还在且可再试。停在 `quitting` 又没有这次请求，即不合格 |

## UI（原侧栏原处，不新页面）

仍只改 `ProcessDetailSidebar` 页脚 / 详情是否冻结，不新开历史入口、不新 Tab、不进菜单栏。

- **退出中且仍 inRows**：现「正在退出…」+ 按钮 disabled（与今日同类）。
- **失败且 inRows、机会仍 open**：现失败句 + 现「退出」/「强制退出…」（见文案建议）。再失败仍留入口。强退仍弹**现**确认框。
- **缺席（进行中或失败）**：旧实时详情和曲线整卡冻结，标 **「已不在列表／上次记录」**。禁止新采样点、禁止写成当前 rss/cpu、禁止停在「正在退出…」、禁止写成「已成功」或暗示 terminate 已生效。按钮 disabled，不能点旧 pid。用户点 x 或改选别人即从侧栏拿走这张冻结卡；store 仍待确认，不结算。
- **机会已 closed**：无旧失败卡、无重试卡、无成功态。若人已不在列表，冻结标可留到正确清理，tick 不得把该次按钮点回来。若人仍在列表，不标「已不在列表／上次记录」。同 pid 再出现且无身份证据：实时详情，仍然没有旧失败卡。
- **同号再现、无身份证据**：直接当前实时详情（Sampler 新 ring，从零采，不把 frozen 曲线接上）。不复活旧失败卡。不因为 pid 数字或列表徽标留下退出操作。
- 切 pid：B 的页脚只反映 B。A 的卡不出现在 B 上。
- 不把失败句做成通知中心、不在列表行画退出 badge（Won't 布局）。

### 文案

**状态语义已锁**（这不是文案待核）：进行中、失败（未退出）、缺席整卡「已不在列表／上次记录」、同 pid 无证据则当新进程、成功只结束本次机会且不新增成功态。失败含义是未退出。缺席不称成功。

**按钮与失败句精词：产品没有锁。** 下面是设计文案建议，**待核**，来源是设计，不是产品锁。实现不得把建议写成验收锁词；默认可沿用现侧栏「退出」「强制退出…」和现失败句。状态语义不受这句话影响。

| 建议 | 文本 |
| --- | --- |
| 普通退出失败说明 | 上次退出未成功，可重试。 |
| 普通退出按钮 | 重试退出 |
| 强退失败说明 | 上次强制退出未成功，可重试。 |
| 强退按钮 | 重试强制退出… |

建议若被产品以后采纳，仍只出现在原侧栏：进行中两按钮禁用；强退「重试强制退出…」走**现**确认框；切到别的 pid 不串到上一个 pid。**在产品核可之前，这些句子不是锁。** 强退确认框文案维持现状，不在建议表里改。

**本期默认可保持行为不变、仍用现按钮「退出」「强制退出…」以及现成失败句**（「未能退出。可以请系统立即结束该进程。」/「系统未能结束该进程。」）。换词不是本刀范围，也不挡 Darwin-free 状态机。禁止把建议表写进验收当锁词。

禁词仍：泄漏 / leak / 危急 / 危险。不要「已成功结束该进程」横幅。

## 建议工程顺序（最少两刀）

两刀，不要拆成历史系统，不改其它范围。实现等本设计合并 + Grok merge gate 后再写 Swift。Mark 在技术设计合入后才可开工程。本 PR 不写 Swift、不合并。

1. **Darwin-free reducer + 状态转换测试（Linux `swift test`）**  
   新文件建议：`Pulse/Models/ProcessQuitOutcome.swift`（名称可调，须进 SamplingCore `sources`）+ `Tests/SamplingCoreTests/ProcessQuitOutcomeTests.swift`。  
   纯函数：`click` / `applyPresenceFromRows` / `complete` / `project`。零 AppKit、零 VM、不编 App、不调 `ProcessActions`。  
   `identityEvidence` 作为 `applyPresenceFromRows` 的显式参数。生产与默认测试钉 **false**（无证据 = 新进程实时详情）。`true` 只在单测里注入，证明「有证据才恢复、且不改别人的选中」；**不**表示本仓库已经能识别同进程，**不算**身份采样验收完成。

2. **Actor VM / 原侧栏接线（Mac 剩余）**  
   `MemoryDashboardVM` 持有 store；`quitSelected` / `forceQuitSelected` 发 token；`tick` 只走验收 A；`applyQuit` 改为 `complete`。`ProcessDetailSidebar` 按 viewState 投影。`didSet` 不再 `quitPhase=.idle`。不改 Sampler 周期、不改确认框、不改十五期过滤空态。

没有硬伤就不开第三条 polish PR。不要和 GPU / 全表 ring / 菜单栏 / 十五期双清捆在一起。

Linux 源码结构检查若刀②要做：必须标明「不是 VM 行为 / 不是 GUI / 不是真实退出」。

## 测试矩阵

**刀① Linux（必须实跑；这是状态转换，不是按钮 GUI）：**

1. 跨 pid：A `failed` 后选 B；B 的投影无 A 的失败；对 B `click` 不写 A 的 pid。
2. A in-flight 时**只切选到 B**（A 没有新 token）：A 的 `.exited` / `.notFound` **关闭 A 自己的机会并只写 A**。不改变 B 的选择、投影、record 或 phase。这一包不叫旧包。
3. 同 pid 仍 inRows 且 `quitting` 再点：忽略，token 不变。A 后来新开 token（含缺席后再现为 `currentReappearedUnconfirmed` 后的显式点击）才取代 A 的 record；**那时** A 的旧 token 即使同 pid 也 ignore，不改新 record、不改选中。B 的新点击不造成这件事。
4. **失败 + 缺席**：inRows `failed` + `open` → 成功帧 pid 缺席 → `phase` 仍 `failed`，`opportunity` 仍 `open`，整卡「已不在列表／上次记录」，不是成功，失败历史没清，不能点旧 pid。
5. **进行中 + 缺席**：`quitting` + 缺席 → 不再是「正在退出…」，整卡「已不在列表／上次记录」；`phase` 仍 `quitting`、机会仍 `open`。
6. 验收 A：`processListFailed`、失败帧或 freshness 不足，即使 `rows=[]` → presence / phase / opportunity 不变，失败还在。
7. **失败 + 再现且身份不同（无证据）**：同 pid 再出现、`identityEvidence=false` → 实时详情；**无**旧失败卡 / 重试卡；不因 pid 数字留下退出操作。store 可仍待确认，UI 不露。
8. **进行中 + 再现且身份不同（无证据）**：同样实时详情，不把「正在退出…」或失败卡贴到新进程上。
8b. **同身份证据才恢复**（单测注入 `identityEvidence=true`，不是生产路径）：只恢复**该 pid** 的上次失败与手动重试；当前选中若是别的 pid 则不改；不对另一个 pid 发退出。无证据源时这条不算已实现。
9. 验收 B：匹配 token 的 `.exited` / `.notFound` → `opportunity=closed`；无成功态、无旧失败卡、无重试卡。随后同 pid 再现且无证据：仍无旧失败卡。freshness **不能**把 `closed` 改回 `failed`。
10. 验收 B：匹配 token 的 `.stillRunning` / `.requestFailed` → `failed` 且 `open`；若当时缺席，仍是中性缺席投影，store 里失败入口还在，但缺席卡上不能点重试。同 token 再送一次失败：幂等。
11. 缺席后的 `.exited`（token 仍匹配）→ 关机会，**不是**成功横幅，**不是**把中性句改成「已成功」。同 token 再送一次 `.exited`：幂等。旧 token 即使同 pid：丢弃。
12. **清选离开保留待确认**：点 x 且 pid 随后不在 `rows` → 侧栏可空，store 不结算、不称成功、失败历史还在。人从未离表时清选再选：仍是失败卡。已 `closed` 后再选或再现：没有旧失败卡。
12b. **跨 pid**：A 进行中或失败时选 B；B 的按钮与投影都不是 A。A 的匹配回包仍只写 A，不写 B 的 record / phase / 选中。B 的缺席或 B 的新点击不改 A 的 token。
13. **取消强退**：点强退时不写 `quitting`。取消后仍不是 `quitting`，没有新 token，没有 `complete`；此前 `failed` 还在且可再试。停在 `quitting` 却没有这次请求即不合格。确认通过且 `selectedPid` 仍是当初那个合法 pid：record 里是新 token 且 `quitting`，请求只打它；确认前的回包 ignore。确认返回时已改选到 B 或目标不合法：不发请求，不打 B，A 的旧 `failed` 还在。
14. 冻结：缺席后 `applyPresence` 再来带同 pid 的假曲线 → `frozenDetail` 点数不增。
15. 禁词：新锁状态名不含泄漏 / 危险。
16. 互斥四态反例 1–5（见上）必须失败于「用单枚 phase 冒充 presence」。

**刀②（Linux 至多源码结构；Mac 才是实例）：**

17. VM 不再在 `selectedPid` didSet 里无条件 `quitPhase=.idle`。
18. 普通退出在点击时写入 token。强退的 token 在确认通过且目标仍是当初的合法 pid 之后才写入。`complete` 只比对 **该 pid 当前 record 的 token**，不比对 `selectedPid`。
19. 侧栏缺席投影禁用两按钮；`liveAsNewProcess` 不渲染旧失败句。
20. 无新页面 / 无菜单栏 terminate / 无 `Timer` 自动重试 / 无 `sample()` cadence 改动。

明确：**源码字符串匹配 ≠ 已验 SwiftUI 按钮 ≠ 已验真实退出。**

## 风险

| 风险 | 应对 |
| --- | --- |
| 把 `.exited` 或 rows 缺席写成成功态 / 横幅 | 验收 A/B 分开；三可见无成功；缺席只改 presence；终局只把 `opportunity` 设为 `closed` |
| 互斥 enum 丢掉 in-flight 或 failure | 正交字段 + 反例 1–5 |
| 同 pid 复现自动露失败卡 | 无证据 → `liveAsNewProcess`；`true` 只许单测注入，且不抢选中 |
| 用 name/path 冒充同实例 | Won't；identity 节写死 |
| 把切选当成 A 的回包失效，或让 A 的回包写 B | 只按该 pid 当前 token 比对；切选不撤 token；失配只来自同 pid 的新发起 |
| didSet / tick 继续清失败 | 重置路径表；刀②验收 |
| `processListFailed` 空表当全体缺席 | 验收 A 钉失败帧不动 presence |
| 把 `waitForExit` 当成自动重试 | 范围表：它是一次操作内短等 |
| 结构测试写成 GUI 已测 | Linux / Mac 分界 |
| 补 startTime 拖进本刀 | 第一刀明确不补 Enumerator |

## 验收（十六期首包）

产品 Must：

- [ ] Must1：本会话侧栏能呈现最近一次普通退出或强退的发起类型，以及投影后的退出中 / 失败（未退出）/ 已不在列表；会外动作或后续采样不得把失败覆盖成已成功
- [ ] Must2：失败按 pid 留存。清选再选**仍在 rows** 的同 pid，侧栏能看到此前失败，可对**当前合法选中**走原按钮普通退出、必要时强退（现确认不改）。不强制为失踪 pid 恢复列表行选中
- [ ] Must3：A 有退出中 / 失败 / 结果时，B 的按钮不向 A 发请求。token 隔离是 **同 pid 的操作代次**：A 的新发起废弃 A 的旧 token；B 的选择或 B 的新动作永不废弃、不改写 A 的有效 token。各 pid 的 record 只跟自己的最新 token 比
- [ ] Must4：已不在列表不提供旧 pid 重试、不暗示仍存活。同 pid 再现且**不能**确认身份：当新进程、实时详情、不自动复活旧失败 / 重试卡，可对当前合法选中发起新操作，绝不把上次过程宣称成功
- [ ] Must5：Darwin-free 转换测试覆盖跨 pid、离开 / 再现、少样本 / 失败帧保留最近结果、重选；Mac 上 VM 真实 SwiftUI 按钮 / 真实退出 / GUI **标未验**；结构测试不冒操作验收
- [ ] 退出发起后 rows 缺席（进行中或失败）：旧实时详情和曲线整卡冻结并标「已不在列表／上次记录」；不能停在「正在退出…」；不能点旧 pid；失败历史保留且不称成功
- [ ] 验收 A 与验收 B 分开成立（见上）。采样缺席 / freshness 不足单独发生时，不得把失败改成成功或清掉失败
- [ ] 只有与该 pid **当前 record** 的 token 匹配的 `.exited` / `.notFound`（该次 `ProcessActions` 实际返回值）能关掉本次机会。切选不撤 token，完成只更新该 pid，不写另一个 pid、不改选中。旧回包 = 相对该 pid 当前 record 的 stale token。同 token 重复到达幂等
- [ ] 终局关掉入口后：无旧失败卡、无重试卡、不新增成功态。后续 tick 不得把该次改回失败或复活该次按钮。同 pid 无证据再现仍无旧失败卡
- [ ] 状态机至少覆盖：进行中缺席、进行中再现且身份不同、失败缺席、失败再现且身份不同、清选离开保留待确认、注入同身份证据才恢复且不抢选中、成功后再现无旧失败、跨 pid 隔离
- [ ] 现模型不能确认实例身份。不新写身份采样或退出历史来当作已经确认。无证据不得把复活写成验收完成
- [ ] 再试后又失败：失败卡 + 可再试（仅 inRows + 当前合法选中）。只有缺席、没有终局：机会仍 open，但缺席卡不能重试旧 pid；清侧栏 / 重选 / 再现之后才能对当时的当前合法选中新发起
- [ ] `.notFound` 只用今日 `ProcessActions` 已返回的那一次；不新增「直到 notFound」的轮询，也不假定每次退出都会返回 `.notFound`
- [ ] 强退：确认通过且目标仍合法才写入 `quitting` 和新 token。取消或返回时目标已失效：不新造 `quitting`、不清旧 `failed`、不改打别的 pid。取消后旧失败仍可手动重试。连点不开多个 Alert
- [ ] 现 `terminate` → `forceTerminate` 边界、cancellation、每 pid 最大 1 个 in-flight 不回退成无界任务
- [ ] 十二至十五期、Sampler 周期、菜单栏、过滤空态、强退确认框不回退
- [ ] 永不写「泄漏」/ leak / 「危险」；无成功横幅

明确不做（本包出现即不合格）：

- [ ] 无自动重试 / 无把 tick 当终止轮询 / 无新 Timer
- [ ] 无跨启动持久化、无退出历史页、无通知中心、无批量退出
- [ ] 无按名称 / bundle / path 串 pid
- [ ] 无改 `confirmForceQuit` 文案或权限 / entitlements
- [ ] 无改 Sampler cadence、无重开十五期双清、无菜单栏 terminate
- [ ] 无第四类可见成功态
- [ ] 无「源码匹配 = 已验真实退出 / GUI」
- [ ] 无把 `identityEvidence=true` 的单测写成「生产已能识别同进程」或「pid 复用已验收」

共性：

- [ ] 一期至十五期验收不回退
- [ ] 冷启动仍默认内存页
- [ ] Linux：`swift test` 跑 ProcessQuitOutcome 转换 + 既有 SamplingCore
- [ ] 不改公证脚本与 entitlements

### Linux 可测 vs Mac 剩余

已核 `Package.swift`：SamplingCore **可列入**新的 Darwin-free `ProcessQuitOutcome`（或同层文件）。**排除** `ViewModels/`、`Views/`、`Actions/ProcessActions.swift`、`Sampling/MemorySampler.swift`、`Sampling/ProcessEnumerator.swift`。因此：

- token / presence / phase / project / 验收 A 与 B / 跨 pid / 失败帧：Linux CI 可实跑。
- `MemoryDashboardVM` 实例、SwiftUI 点「退出」、真实 `NSRunningApplication`、Xcode 主窗：**不能**在 Linux 声称已测。
- 若刀②加 VM 源码结构检查：必须写明不是行为测试、不是 GUI。

本 docs PR **不跑**、也不声称：

- `MemoryDashboardVM` 实例测试
- Xcode GUI / 点退出 / 强制退出 / 触控
- 实机 `terminate` / `forceTerminate` / 进程真死
- 签名 / 公证

Mac 冒烟（**仅**本设计已合并且实现合并后；**不挡**本文档审阅，也**不是**本期 docs 交付）：

- 失败后切到另一进程再切回（pid 一直在表里）：失败还在，按钮打当前 pid
- 退出中或失败时该行从 enumerator 消失：整卡「已不在列表／上次记录」，不是「正在退出…」，不称成功；失败历史没被清掉；不能点旧 pid。同 pid 再出现：实时详情，没有旧失败卡
- 失败帧 / 列表失败把表抽空：侧栏失败不被改成成功
- 同 pid 后再出现：实时详情，**没有**旧失败卡（无 startTime）
- 切走之后旧退出才返回：当前进程页脚不被改写
- 强退取消：失败卡仍在
- 名称过滤 / 仅上涨 / 十五期双清 / 菜单栏 Top3 无回归

## 工期

小：两刀都是会话内 reducer + 原侧栏投影，不是新采样通道、不是历史产品。① Darwin-free 转换 + Linux `swift test`；② VM / 侧栏接线。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

## 依赖与未决

**产品行为已锁**：缺席整卡「已不在列表／上次记录」（进行中与失败都冻结，不称成功，不能点旧 pid）；同 pid 无证据默认新进程实时详情，不复活旧失败、不因 pid 数字留退出操作；只有另有同一身份证据才恢复失败与手动重试，且不抢当前选中；成功后无旧失败 / 重试卡，不新增成功态。采样不能单独清失败。终局只认该次 `ProcessActions` 实际返回的匹配 token+pid `.exited` / `.notFound`。现模型确认不了身份，本期不新写身份采样或历史库；无证据的复活不算验收完成。

**产品没有锁按钮精词。** 设计建议「上次退出未成功，可重试。」/「重试退出」以及强退对应两句是**待核**，不是锁。默认可沿用现「退出」「强制退出…」与现失败句。这不挡刀①。

没有其它产品待决需要把十六期停成草稿。

实现等本设计合并 + Grok merge gate 后再写 Swift。Mark 在技术设计合入后才可开工程。本 PR 不写 Swift、不合并。
