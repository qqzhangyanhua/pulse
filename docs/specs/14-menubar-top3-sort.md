# Pulse 十四期技术设计（首包：菜单栏 Top3 跟随主窗内存页四列排序）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 14 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。
>
> 已被取代：「不改菜单栏布局 / 主机行」：#78 在主机信息块加了可选的最忙一核一行。

> 一期至十三期正文不改写。七 / 十一期把菜单栏 B Top3 锁成「已采 `rows` 内存降序前 3 + 点选落内存页同 pid」；十二期名称过滤 / 「仅上涨」只收主窗表；九期 Top5 已跟内存页 `ProcessTableSort`——**本文正式锁定 A**：菜单栏 Top3 跟随主窗内存页**现有**名称 / CPU / 内存 / 线程四列排序。切换既有表头即与主窗未过滤序一致。主键相等统一 **pid 升序次键**。不新增 PID 表头。菜单栏仍只画名称 + 内存，不显示 PID。投影吃未过滤 `rows`（不受名称过滤 / 「仅上涨」影响）。CPU `nil` 走现有 `cpuSortKey == -1`。默认内存降序；切到资源 Tab 时菜单栏保留最后一次内存页 sort。十一期点选仍开内存页并选中同一 pid。最多 3 行。既有采样失败 / 进程列表失败空态不改。不改 Sampler `sample()` / tick / cadence，不新开第二套排序算法，不改菜单栏布局 / 文案 / 主机压力与已用信息行，不重开十三期重试，不做磁盘趋势 / GPU / 新 Tab / 全表 ring，不改十二期过滤 / 增长算法 / TopN=5，不另加持久化排序设置，不重做 `MenuBarPopoverSnapshot`、不引入第二个状态源。不改主窗排序按钮，不新增 PID 列。

**已锁定**：十四期 = **A（菜单栏 Top3 跟随主窗内存页现有四列排序）**。谁：先看菜单栏、再对照主窗内存表的人。情境：内存页已经按名称 / CPU / 内存 / 线程排过表。成功：菜单栏最多 3 行与该序对未过滤 `rows` 的前三一致；行仍只画名称 + `memoryBytes`（pid 只作点选身份，不显示）；点选仍走十一期 `MenuBarPopoverTap`（dismiss → `selectPidIfPresent` → `focusMemoryPage`）。主键相等时，四列共用同一 **pid 升序次键**（不受 `descending` 翻转）。不新增 PID 表头。主窗名称过滤与十二期「仅上涨」**不**灌入菜单栏。失败 / 空态沿用。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`；弹出条**不**调 `sample()`。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：产品与设计书面正式锁定的十四期 A。技术发布入口沿用已核对的 MainActor publication（对照 main 十三期①#45 / ②#46 `e3fc8b7198ba68a986903fb94b692cd2e961a0a3` 的现实现：未过滤 `rows`、单 comparator + 主键 pid 升序次键、CPU nil=`-1`、资源 Tab live `tableSort` 不驱动菜单栏、Tap、max3、失败态、Linux / Mac 边界、默认内存降序不回退）。

现实现核对：`ProcessTableSort` 在 `Models/CPUPage.swift`；`MemoryDashboardVM.tableSort` = `navigation.sort`；`ProcessTablePane.sortedRows = vm.tableSort.ordered(vm.visibleRows)`；`setMemoryPageSort` 在 Darwin Actor `MemorySampler`，`memoryPageSort` **private**，只经 `publishMemoryPageSort()` 在 `selectedPage == .memory` 时 `Task { await sampler.setMemoryPageSort(tableSort) }`——**不是** VM 可读的同步值，`menuBarPopover` getter **读不到**它；`MenuBarPopoverSnapshot.topProcesses` 仍硬编码 `memoryBytes` desc + pid 升序；`menuBarPopover` 已吃完整 `rows`，不吃 `visibleRows`。

## 范围（相对一二三四五六七八九十十一十二十三期）

| 项 | 一二三四五六七八九十十一十二十三期 | 十四期首包 |
| --- | --- | --- |
| 定位 | 七 / 十一期：Top3 = 已采 `rows` **内存降序**前 3，可点选落内存页 | **投影对齐**：Top3 = 内存页已发布的 `ProcessTableSort` 对未过滤 `rows` 排序后的 `prefix(3)` |
| 菜单栏外观 A / B 槽位 | 栏上色点；压力 + 已用 + Top3 +「打开 Pulse」 | **布局 / 文案 / 主机行不改**。Top3 仍名称 + 内存字节，不显示 PID，不改写成 CPU / 线程列 |
| Top3 顺序 | 硬编码内存降序 + pid 升序次键（`MenuBarStatus.topProcesses`） | **做（本刀）**：复用主窗内存排序同一 comparator，再 `prefix(3)` |
| 点选 | 十一期 `MenuBarPopoverTap`：dismiss → `selectPidIfPresent` → `focusMemoryPage` | **原样保留**。host block 不可点；「打开 Pulse」只聚焦 |
| 主窗过滤 | 名称过滤 + 十二期「仅上涨」只进 `visibleRows` | **不灌入菜单栏**。投影继续吃完整 `rows` |
| 主窗表排序 | 单份 `navigation.sort`；切 Tab **重置**为该页 default | **不改**切 Tab 重置、不另加持久化、不改排序按钮、不新增 PID 表头。菜单栏绑 MainActor **publication**（最后一次内存页 sort）。资源 Tab 当下的 `tableSort` **不能**改菜单栏排序 |
| Sampler / Top5 | 九期 Actor 私有 `memoryPageSort` + `ordered(rows).prefix(5)` | **不改 Sampler / 不改 N=5**。「零 Sampler」不排斥 MainActor publication |
| 十三期重试 | 单消费者门闩 | **不重开** |
| GPU / 新 Tab / 全表 ring / 新 cadence | 禁止 | **仍禁止** |
| Helper / entitlements / Electron | 无 | **仍无** |

一二三四五六七八九十十一十二十三期验收与公证路径不因本文重开。十一期点选、十期已用内存行、十二期仅上涨、九期 Top5、十三期重试不重开。实现等本设计合并 + Grok merge gate 后再写 Swift。Mark 在技术设计合入后才可开工程。本 PR 不写 Swift、不合并。

## 架构（现实现，读仓库后的结论）

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

本刀落在 **Darwin-free 排序语义 + 现成 `MenuBarPopoverSnapshot.project` 加 sort 输入 + MainActor 同步发布入口**，不是第二套 VM sort，也不是第二套 menu sort。

- 主窗表：`rows` → `MemoryGrowthRisingFilter.apply`（名称 + 仅上涨）→ `visibleRows` → `ProcessTableSort.ordered` → `ProcessTablePane.sortedRows`
- 菜单栏今日：`MenuBarPopoverSnapshot.project(..., rows:)` 内部再 `sorted { memoryBytes desc; pid asc }.prefix(3)`——**故意不跟表头**
- 九期 Top5 已经：`publishMemoryPageSort` → `Task { await sampler.setMemoryPageSort }` → Actor **私有** `memoryPageSort` → `MemoryGrowthTopSeries.pids` = `sort.ordered(rows).prefix(5)`
- 十四期菜单栏应对齐「未过滤 `rows` + **同一**内存页 sort + prefix」，只是 N=3、映射现成 `MenuBarPopoverProcess`
- **缺口（同步读）**：`memoryPageSort` 只活在 Darwin Actor 里，给下一 tick 的 Top5 retention 用；`menuBarPopover` 是同步 getter。AppKit 菜单栏重绘**不是** suspension 点，禁止 `await` Actor 再刷 UI。必须在 MainActor 补一个与发布同批可读的 sort 快照。

约束：

- 不新开第二套 VM、不新开第二路 Mach、不调 `sample()`。
- 不重做 `MenuBarPopoverSnapshot` 类型、不引入第二个弹出条状态源；只给现成 `project` 加 sort 输入。
- 不把 Sampler 改成同步 Actor、不把 MenuBar snapshot 塞进 Sampler。
- 不改 `Pulse.entitlements`、不改公证脚本、不改十三期门闩。
- 「零 Sampler 改动」= 不改 `sample()` / tick / cadence / `setMemoryPageSort` 签名与 Actor 隔离。**不排斥**下面的 MainActor publication（那是 VM / SamplingCore 同步入口）。
- 自身占用仍优先：排序是纯投影，不是重采样。

### 现模型里有什么（必须按「已有 / 没有」落笔）

| 现字段 / 调用 | 文件 | 十四期怎么用 |
| --- | --- | --- |
| `ProcessTableSort` / `ProcessSortColumn` | `Models/CPUPage.swift`（SamplingCore） | **唯一 comparator**。列：`name` / `cpu` / `memory` / `threads` / `disk`。**没有 PID 列** |
| `ProcessTableSort.ordered` / `.selecting` / `.defaultSort(for:)` | 同上 | 主窗表已经在用。菜单栏改为调用同一份，禁止 piece-meal 再写一套 |
| `ProcessTableSort.defaultSort(for: .memory)` | 同上 | 冷启动 / 切回内存页默认：**内存降序** |
| `DashboardNavigation.sort` / `.select` / `.focusMemoryPage` / `.updateSort` | 同上 | **单份**当前表排序。切到另一可点页会 `sort = defaultSort(for: newPage)`；同页再选保持用户排序 |
| `MemoryDashboardVM.tableSort` | `ViewModels/MemoryDashboardVM.swift` | `navigation.sort` 的只读投影。主窗按钮写的就是它 |
| `MemoryDashboardVM.visibleRows` / `.rows` | 同上 | 菜单栏**继续吃 `rows`**。禁止改吃 `visibleRows` |
| `MemoryDashboardVM.setTableSort` / `ProcessTablePane` 表头 | VM + `Views/ProcessTablePane.swift` | 内存页可点：名称 / CPU / 内存 / 线程。点列 = `tableSort.selecting(column)` |
| `publishMemoryPageSort()` | VM private | 今日：`guard selectedPage == .memory` 才 `Task { await sampler.setMemoryPageSort(tableSort) }`。注释：*Only the memory-page sort drives Top 5.* **没有**同步写出值给 getter |
| `MemorySampler.setMemoryPageSort` / `memoryPageSort` | `Sampling/MemorySampler.swift`（**不在** SamplingCore） | Actor **private**，只给 Top5 / 采样 retention。切走资源 Tab 不改它。**不是** `menuBarPopover` 可读属性。本刀 **不改 Sampler** |
| `MemoryPageSortPublication`（本刀补） | SamplingCore（与 `ProcessTableSort` 同层，Darwin-free） | MainActor 同步持有「最近一次在内存页发布的 sort」。**不是**现成字段，也**不是** `@Published lastMemorySort`。见下节 |
| `MenuBarPopoverProcess` | 同上 | 仍 `pid` / `name` / `memoryBytes`。不改行字段、不改弹出条画法 |
| `MenuBarPopoverTap` | 同上 | **十一期步骤一字不改** |
| `MemoryGrowthRisingFilter` / `filter` / `risingOnlyFilter` | Models + VM | **不进**菜单栏投影 |
| `MemoryGrowthTopSeries.pids` | Models | **对照模式、不改 N=5**。菜单栏是同一 `ordered(rows)` 的 `prefix(3)` |
| Sampler `rows.sort`（内存降序 + pid 升序） | `MemorySampler.sample()` | **不改**。这是采样输出的默认排列，不是菜单栏第二套 sort |

**缺口（已核，不是采样缺口）**：

1. 菜单栏 `topProcesses` 仍硬编码内存降序，与主窗内存页表头脱节。
2. `ProcessTableSort.ordered` 主键 `.orderedSame` 时 `return false`；菜单栏与 Sampler 默认内存降序另有 **pid 升序次键**（`testEqualMemoryBreaksTiesByPidAscending`）。共享 comparator 收进这条次键：名称 / CPU / 内存 / 线程主键相等时统一 pid 升序（不受 `descending` 翻转）。已锁。不新增 PID 表头。
3. `navigation.sort` **不是**跨 Tab 持久的 last memory sort：切到 CPU / 网络 / 磁盘会重置为该页 default；切回内存页会重置为**内存降序**（`CPUPageTests.testColdStartStaysOnMemoryAndCPUSelectionChangesTheDefaultSort`）。菜单栏不跟这份 live 值，跟 publication。
4. **没有同步可读的「已发布内存页 sort」。** Sampler 私有态不能给 `menuBarPopover` 用。文档若只写「把 publishMemoryPageSort 最后一次发出的值传入 project」却不定义 MainActor 存在哪、何时更新，就是暗造状态。
5. 内存页表头已是名称 / CPU / 内存 / 线程。**不新增 PID 表头。** 菜单栏不显示 PID。主键相等走统一 pid 升序次键。

因此本刀：

1. **不改 Sampler**（不改 `sample()` / tick / cadence / `setMemoryPageSort` 签名）。「零 Sampler」不排斥 MainActor publication。
2. **一份 comparator**：主键相等之后收进 **pid 升序次键**（不受 `descending` 翻转）。消菜单栏硬编码副本。这是已锁次键，不是新指标，也不新增 PID 表头。
3. **MainActor 同步发布入口** `MemoryPageSortPublication` 持有「最近一次在内存页发布的 `ProcessTableSort`」。`menuBarPopover` **同步**读它传给 `project`。禁止 `Task { await sampler.… }` 当 UI 数据源。
4. `publishMemoryPageSort` **只在** `selectedPage == .memory` 时：先写 publication，再 `Task { await sampler.setMemoryPageSort(同一快照) }`。切走不更新。切回内存页：既有 `select` 改 `navigation.sort` → 本函数随后改 publication 并通知 Sampler；已采 `rows` **立即**按新 sort 重排，不等下一 tick。
5. `start()` 走同一 guard：冷启动在内存页则写入默认内存降序；**禁止**无条件在其它 Tab 把 publication 打回默认。
6. 切片：`sort.ordered(rows).prefix(MenuBarPopoverShell.maxProcessRows)`，不足 3 不补 0。
7. 不要新建第二个 `MemoryDashboardVM`，不要重做 Snapshot 类型，不要 `@Published lastMemorySort` 状态机。

### PID（已锁）

内存页表头保持名称 / CPU / 内存 / 线程。切换这四列既有表头，菜单栏 Top3 与未过滤 `rows` 同序。主键相等统一 pid 升序次键（不受 `descending` 翻转）。不新增 PID 表头。菜单栏仍只画名称 + 内存，不显示 PID。pid 继续只作十一期点选身份。

### MainActor 发布入口（必须写清，禁止暗造）

三份东西不要混：

| 名字 | 谁持有 | 何时变 | 谁读 |
| --- | --- | --- | --- |
| `navigation.sort` / `tableSort` | `DashboardNavigation` | 切 Tab 重置为该页 default；内存页点表头改它 | 主窗 `ProcessTablePane` |
| Sampler `memoryPageSort` | Darwin Actor **private** | 仅 `setMemoryPageSort`；异步 `Task` | 仅下一趟 Top5 / 采样。**菜单栏读不到** |
| **publication.sort**（本刀补的同步入口） | MainActor 持有 | **仅** `selectedPage == .memory` 的 `publishMemoryPageSort` | `menuBarPopover` → `project` |

这不是另一套排序规则，也不是并行 `lastMemorySort` 状态机：规则仍是同一份 `ProcessTableSort`。补的是「已有发布语义」的 **MainActor 可读快照**，好让主窗表头、Top5（仍走现成 `Task await`）、菜单栏投影 **无漂移**。

`publishMemoryPageSort` 更新契约：

| 调用点 | 今日 | 十四期 |
| --- | --- | --- |
| `setTableSort`（内存页点列） | 改 `navigation.sort` 后 `Task await` Sampler | 先写 publication（同步），再发**同一** snapshot 给 Sampler |
| `selectPage` 切到 CPU / 网络 / 磁盘 | `navigation.sort` 重置为该页 default；`guard` 早退 | publication **不改**；菜单栏保持离开内存页前的序 |
| `selectPage` / `focusMemoryPage` 回到内存 | `navigation.sort` 重置为内存降序；`Task await` Sampler | publication 写成该默认并通知 Sampler；已采 `rows` 立即按内存降序重排 Top3 |
| 已在内存页的 `focusMemoryPage` | 不改 sort | publication 不改 |
| `start()` | 无条件调用 `publishMemoryPageSort()`；冷启动页是内存 | **同一 guard**：只在内存页写 publication / 通知 Sampler。禁止 start 在其它 Tab 重设 publication |

切回内存后不等下一 `sample()` tick：`project` 吃的是已在 VM 上的 `rows` + 刚写入的 publication。Sampler 那一跳只服务 Top5 retention。

#### 发布类型（已核）

Darwin-free `MemoryPageSortPublication`，与 `ProcessTableSort` / `MenuBarPopoverSnapshot` 同层进 SamplingCore。VM 持有一份；`menuBarPopover` 同步读 `publication.sort`。不是第二套 VM，不是第二套 Sampler，不是 `@Published lastMemorySort`。Linux 能测「只在内存页更新 / 切资源 Tab 保持最后内存 sort / 默认内存降序」。

禁止：

- `@Published lastMemorySort` 当第二套状态机
- `menuBarPopover` 里 `await sampler` 取 sort（AppKit 菜单栏不是 suspension 点）
- 把 Sampler 改成同步 getter，或把 MenuBar snapshot 塞进 Sampler

### 切资源 Tab：菜单栏保留最后内存 sort

**已锁定**：切到 CPU / 网络 / 磁盘时，菜单栏保持离开内存页前的最后一次内存页 sort。资源 Tab 当下的 `tableSort` 不能改菜单栏排序。冷启动与切回内存页的默认仍是内存降序。

**表上的 `navigation.sort` 仍按现行为重置。** 内存页与资源 Tab **共享同一份** `DashboardNavigation.sort`（不是 per-page map）。`select(.cpu / .network / .disk)` 会写成该页 `defaultSort`（CPU / 网络 = CPU 降序；磁盘 = 合计磁盘速率降序）。切回内存页会写成内存降序，用户在内存页点过的 CPU / 线程 / 名称排序在**主窗表**上丢掉。同页再点同一 Tab、或已在内存页时 `focusMemoryPage()`，才保持当前 sort。菜单栏不读这份 live 值。

**Sampler `memoryPageSort`：maintain，但菜单栏读不到。** 只在内存页经异步 `Task` 更新；切走早退。这是九期 Top5 用的「上次内存排序」，不是 UI 同步源。

**十四期菜单栏绑哪一份：** 绑 **publication**（与发往 Sampler 的 snapshot 同一份 `ProcessTableSort`），**不是**资源 Tab 当下的 `tableSort`，也**不是** `await` Actor。禁止「跟随任一 Tab」。

切 Tab **不**重设 publication（菜单栏保持；Sampler 私有态也不改）。切回内存页走现成 `DashboardNavigation.select` → `publishMemoryPageSort` 同步写 publication + 通知 Sampler——这是现行为的同步补全，不另加持久化。

从资源 Tab 点 Top3：十一期 `focusMemoryPage()` 若从其它页回来，会把表 sort 重置为内存默认并发布；publication / 菜单栏随之回到内存降序。已在内存页时点 Top3 不重置。

## 映射规则

「主窗内存排序」= publication 持有的、最近一次在内存页发布的 `ProcessTableSort`（冷启动 / 切回内存默认 = 内存降序）。Top3 = 该 order 下未过滤 `rows` 的前三，**不是** Top 3 by memory，也**不是**把内存列改写成 CPU / 线程 / PID 数值。

| 内存页当前 sort | 主窗未过滤序（同一 comparator） | 菜单栏 Top3 | 行上仍显示 |
| --- | --- | --- | --- |
| 默认 / 切回内存页 | `column == .memory`，`descending == true` | 内存降序前 3 | 名称 + `ByteFormat.memory` |
| 再点内存列 | 升序翻转 | 同一升序前 3 | 同上 |
| 点 CPU | `selecting(.cpu)`：首点降序；`cpuSortKey`（`cpuPercent ?? -1`） | CPU 序前 3，**不是**内存最大的 3 个 | 同上，不画 CPU% |
| 再点 CPU | 升序 | 同一升序前 3 | 同上 |
| 点线程 | 首点 `threadCount` 降序 | 线程序前 3 | 同上，不画线程数 |
| 点名称 | 首点升序（`column != .name` 才默认降序） | 名称序前 3 | 同上 |
| 主键相等 | comparator 次键 **pid 升序**（名称 / CPU / 内存 / 线程共用；不受 `descending` 翻转） | 同序 | 身份仍是 pid，行上不显示 PID |

升降序规则沿用现成 `selecting`：同一列再点翻转；换列时名称升序、指标列降序。四列都是既有表头。默认内存降序不回退。主键相等统一 pid 升序次键。不新增 PID 表头。

| 主键相等 / 缺值 | 现测（以现 comparator 测试为准，不写新指标） | 十四期 |
| --- | --- | --- |
| 内存相等 | 菜单栏 `testEqualMemoryBreaksTiesByPidAscending`：pid 升序；`ProcessTableSort.ordered` 今日 `false` | 共享层收进 pid 升序次键，**不放宽**该菜单栏测试 |
| CPU `nil` vs `0` | `CPUPageTests.testNilCPUSortsBelowARealZero`：`cpuSortKey == -1`，真实 0% 在缺失之上 | **原样** |
| 线程相等 | 无独立次键测试；`compare` 到 `.orderedSame` | 走同一 pid 升序次键 |
| 磁盘列 | 仅磁盘 Tab 表头；内存页 UI 点不到 | 不把磁盘 Tab 的 `.disk` default 灌进菜单栏 |
| 不足 3 条 | 现测：有几条画几条，不补 0 | **原样** |
| `processListFailed` | 现测：`processes == []`，「暂无进程」 | **原样** |
| 采样失败主机行 | 压力 / 已用 `nil`，灰点，「暂时读不到」；进程切片仍可按 `rows` 投 | **原样**。本刀不碰主机行 |

| 切 Tab / 过滤（现行为，菜单栏映射） | 主窗表 | 菜单栏 Top3 |
| --- | --- | --- |
| 内存页点名称 / CPU / 内存 / 线程 | `visibleRows` 按新 sort | publication 同步写成该 sort；Top3 立即跟 |
| 切到 CPU / 网络 / 磁盘 | `navigation.sort` **重置**为该页 default；`publishMemoryPageSort` 早退 | publication **不改**（与 Sampler 私有态一样保持）。**不**改成 CPU / 磁盘 default |
| 切回内存页 | **重置**为内存降序；本函数写 publication + 通知 Sampler | 已采 `rows` 立即按内存降序重排，不等下一 tick |
| 已在内存页 `focusMemoryPage` | 不重置当前 sort | publication 不改 |
| 从其它页 `focusMemoryPage`（含点 Top3） | 重置为内存降序 | 同「切回内存页」 |
| 名称过滤 ON / OFF | 只改 `visibleRows` | **IDs / 顺序不变** |
| 「仅上涨」ON / OFF | 只改内存页 `visibleRows` | **IDs / 顺序不变** |
| `selectedPid` / Top5 series | 选中与九期 ring 照旧 | **不**灌入投影 |

## VM / UI 契约

`menuBarPopover` 今日：

```
MenuBarPopoverSnapshot.project(
    pressure: snapshot?.pressure,
    usedBytes: snapshot?.usedBytes,
    samplingFailed: samplingFailed,
    rows: rows,
    processListFailed: processListFailed
)
```

十四期只加 **sort 输入** = publication 的同步 `ProcessTableSort`（冷启动默认内存降序）。**不是**「未定义存放位置的最后一次发出值」，也**不是** `await` Sampler。`rows` / 失败旗标 / 主机行语义不动。

| 项 | 锁定 |
| --- | --- |
| 投影源 | 完整 `rows`，不是 `visibleRows` |
| 顺序 | 上述 sort 的 `ordered(rows).prefix(3)` |
| 行模型 | 现成 `MenuBarPopoverProcess`（pid / name / memoryBytes） |
| 行 UI | 现成 `MenuBarPopoverView`：名称 + `ByteFormat.memory`；不改宽度、不加数值标签 |
| 点选 | `MenuBarPopoverTap.steps`：`.dismissPopover` → `.selectPidIfPresent(pid)` → `.focusMemoryPage` |
| 「打开 Pulse」 | dismiss + `focusMemoryPage`，不写 `selectedPid` |
| host block | 不可点 |
| 最多行数 | `MenuBarPopoverShell.maxProcessRows == 3` |
| 空态 | `processListFailed` 或 0 行 →「暂无进程」，无行可点 |
| 采样 | 不调用 `sample()`；不另开 timer |

`AppEmptyState` / 十三期「重试」 / 仅上涨空态 / 九期徽标：**本刀不碰**。

### 明确不做（相对本刀）

- 改 Sampler / 采样源 / 频率 / `setMemoryPageSort` 签名；把 Sampler 改同步 getter；把 MenuBar snapshot 塞进 Sampler。
- 新排序算法、新指标、第二套 VM sort / menu sort、`@Published lastMemorySort` 状态机。
- `menuBarPopover` 用 `Task await` 刷 UI。
- 改菜单栏布局 / 文案 / 主机压力与已用行 / 栏上 A。
- 重开十三期重试 / 调度。
- 磁盘趋势 / GPU / 新 Tab / 全表 ring。
- 改十二期过滤 / 增长算法 / TopN=5；把名称过滤 / 仅上涨灌进菜单栏。
- 改主窗排序按钮、新增 PID 表头、让菜单栏显示 PID，或把 Top3 内存列改写成 CPU / 线程 / PID。
- 另加持久化排序设置、per-page sort map。
- 重做 `MenuBarPopoverSnapshot` 或第二个状态源。
- 让菜单栏跟随 CPU / 网络 / 磁盘 Tab 当下的 only-page sort。
- 把选中 pid / Top5 series 灌进菜单栏。
- 声称 Linux 测了 VM / Xcode / 真菜单栏 / 点击表头的 SwiftUI 行为。
- 改权限 / entitlements / 公证脚本。

## 建议工程顺序

两刀，不要拆成另一套 VM sort，不改其它范围。实现等本设计合并 + Grok merge gate 后再写 Swift。Mark 在技术设计合入后才可开工程。本 PR 不写 Swift、不合并。

1. **共享 `ordered` / publication / `project` 有界投影 + Linux `swift test`**：`ProcessTableSort.ordered` 收进已锁的 pid 升序次键；Darwin-free `MemoryPageSortPublication` 与 `MenuBarPopoverSnapshot.project(sort:)` 进 SamplingCore。钉：默认内存降序、主键相等 pid 升序、CPU nil=`-1`、只在内存页更新、切资源 Tab 保持最后内存 sort、切回立即用已采 `rows` 重排、`prefix(3)`。不改 Sampler、零 AppKit。
2. **VM publish 接线**：`publishMemoryPageSort` 只在内存页先同步写 MainActor publication，再 `Task` **同一份** snapshot 给 Sampler；`menuBarPopover` **同步**读 publication。切走资源 Tab 不得改传 live `navigation.sort`。不改其它范围。

没有硬伤就不开第三条 polish PR。不要和 GPU / 全表 ring / 十三期重试 / 新周期捆在一起。

## 风险

| 风险 | 应对 |
| --- | --- |
| 把 live `tableSort` 绑到菜单栏，切 CPU Tab 后 Top3 变成 CPU default | 契约写死：只吃 publication；单测钉切 Tab 后菜单栏 IDs 不变 |
| 文档称「已发布 sort」却无同步存放 | 必须有 MainActor publication；禁止只靠 `Task await` |
| `await` Sampler 刷菜单栏 | 禁止。AppKit 不是 suspension 点 |
| 硬造 `@Published lastMemorySort` / 第二套 menu sort | publication 只是同一 `ProcessTableSort` 的同步入口，不是平行规则 |
| 吃 `visibleRows`，名称过滤 / 仅上涨改 Top3 | 投影继续吃 `rows`；单测 ON/OFF IDs 不变 |
| 把内存列改写成 CPU% / 线程 / PID | 行模型与 View 不改字段 |
| 放宽菜单栏 pid 次键或主窗 ordered 测试 | 次键收进共享 comparator；**不改**现测断言 |
| 当成重采样 / 新 cadence | 范围表零 Sampler |
| 重开点选 / 十三期重试 | Tap 步骤与门闩本刀不碰 |
| Helper / GPU / 新 Tab / 恐吓文案 | 范围表写死不加 |

## 验收（十四期首包）

正式锁定 A 的验收：

- [ ] 内存页默认内存降序时，菜单栏 Top3 与今日相同（含 pid 升序次键）
- [ ] 内存页切换既有表头（名称 / CPU / 内存 / 线程）后，菜单栏前三 = 同一 comparator 对未过滤 `rows` 的前三；主键相等为 pid 升序
- [ ] 行仍只显示名称 + 内存字节；不显示 PID；不新增 PID 表头
- [ ] 名称过滤、「仅上涨」ON/OFF 不改变菜单栏 pid 顺序
- [ ] 切到 CPU / 网络 / 磁盘：菜单栏保持最后一次内存页 sort，不改成该 Tab default
- [ ] 切回内存页：现成重置为内存降序；publication 同步更新；已采 `rows` 立即重排
- [ ] 点选步骤同十一期：开内存页并选中同一 pid；host block 不可点；「打开 Pulse」只聚焦
- [ ] `processListFailed` / 空列表：「暂无进程」；不足 3 不补 0；采样失败主机行 nil / 灰点不改
- [ ] 无新 Sampler cadence；菜单栏不调 `sample()`；不 `await` Actor 刷 UI
- [ ] 永不写「泄漏」/ leak / 「危险」

测试矩阵（实现 PR 必须覆盖能 Linux 测的项；VM / GUI 标 Mac 剩余）。默认排序 equality 统一进 comparator：

**原有、不放宽：**

1. `MenuBarPopoverSnapshotTests.testEqualMemoryBreaksTiesByPidAscending` 与默认内存降序 Top3
2. `CPUPageTests.testNilCPUSortsBelowARealZero`（`cpuSortKey == -1`）
3. `CPUPageTests` / `NetworkPageTests` / `DiskPageTests` 的切 Tab 重置 `navigation.sort`、同页再选保持、`focusMemoryPage` 已在内存页不重置
4. `MenuBarPopoverTapTests` 十一期步骤
5. `MemoryGrowthTopSeries.pids`、菜单栏主机行 / 失败空态 / 不足 3 条

**新增（publication + 统一次键 + `project(sort:)`）：**

6. `ProcessTableSort.ordered`：名称 / CPU / 内存 / 线程主键相等 → pid 升序；`descending == true` **不**翻转次键
7. 内存页名称 / CPU / 内存 / 线程：`project(sort:).processes.pid` = `sort.ordered(rows).prefix(3)`；内存降序以外的列可 ≠ 内存最大三行
8. 名称过滤 / 「仅上涨」ON/OFF：菜单栏 IDs / 顺序不变
9. publication：仅模拟「内存页发布」才更新；切到 CPU / 网络 / 磁盘后 `project` 仍用旧 publication（不必起 VM）
10. 切回内存：publication 写成内存默认后，已有 `rows` 立即按该 sort 重排，不等下一 tick
11. `start` / 非内存页：不把 publication 无条件打回默认（纯 publication 单测即可）

明确不做（本包出现即不合格）：

- [ ] 无 GPU / 新 Tab / 全表 ring / 新 cadence
- [ ] 无第二套 VM sort / menu sort / `@Published lastMemorySort` 状态机
- [ ] 无 `await` Sampler 刷菜单栏；无把 MenuBar snapshot 塞进 Sampler
- [ ] 无新增 PID 表头；菜单栏不显示 PID
- [ ] 无菜单栏布局 / 主机行 / 点选改写
- [ ] 无 Helper / 新 entitlements / 持久化排序
- [ ] 无恐吓文案、无「泄漏」
- [ ] 无「跟随任一 Tab 当下排序」
- [ ] 无把过滤 / 仅上涨灌进菜单栏

共性：

- [ ] 一二三四五六七八九十十一十二十三期验收不回退
- [ ] 冷启动仍默认内存页 + 内存降序
- [ ] Linux：`swift test` 跑共享 ordered + publication + `project(sort:)` + 现成菜单栏 / Tap / CPU ordered 测试
- [ ] 不改公证脚本与 entitlements

### Linux 可测 vs Mac 剩余

已核 `Package.swift`：SamplingCore **列入** `Models/CPUPage.swift`（`ProcessTableSort` / `DashboardNavigation`）、`MenuBar/MenuBarStatus.swift`（`MenuBarPopoverSnapshot` / Tap）。**排除** `ViewModels/`、`Sampling/MemorySampler.swift`、Views、`MenuBarPopoverView.swift`、`MenuBarController.swift`、`PulseAppDelegate.swift`。因此：

- `MemoryPageSortPublication` 与 `ProcessTableSort.ordered`、`project(sort:)` 必须 Darwin-free / 无 AppKit，Linux CI 可跑矩阵里的投影 / 次键 / publication 更新规则。
- VM `publishMemoryPageSort` 接线、`start()` 真路径、Xcode 菜单栏、点击表头的 SwiftUI：**不能**在 Linux 声称已测。
- Sampler Actor 私有态与 `Task await`：**不在** SamplingCore，本刀也不改它。

本 docs PR **不跑**、也不声称：

- `MemoryDashboardVM` 实例测试
- Xcode GUI / 真菜单栏弹出 / 点击表头设 sort
- 实机 Sampler 发布时序

Mac 冒烟（**仅**本设计已合并且实现合并后；不挡本文档审阅）：

- 内存页点名称 / CPU / 内存 / 线程，打开菜单栏：前三 pid 与主窗未过滤表一致，行上仍是名称 + 内存字节，不显示 PID
- 打开名称过滤 / 「仅上涨」：菜单栏三行不动
- 切到 CPU Tab 再打开菜单栏：仍是离开内存页前的那一序，不是 CPU 表当下序
- 点 Top3：仍落内存页同 pid；从其它 Tab 点选后表回到内存降序（现 `focusMemoryPage`）
- 失败空态 / 灰点 /「暂无进程」不回退

## 工期

小：两刀都是天级。主因是复用现成 `ProcessTableSort` + Darwin-free `MemoryPageSortPublication` + 有界 `prefix(3)`，不是重采样、不是改 Actor。① 共享 `ordered` / publication / `project` 有界投影 + Linux `swift test`；② VM publish 接线，不改其它范围。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并 + Grok merge gate 后再写 Swift。Mark 在技术设计合入后才可开工程。本 PR 不写 Swift、不合并。
