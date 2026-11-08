# Pulse 十五期技术设计（首包：内存页过滤空态双清）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 15 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。
>
> 已被取代：「清空过滤」#80 起同时清掉「仅窗口 App」；「按 App」不清。
>
> 已被取代：只开「仅窗口 App」的空态也走「没有匹配的 App」，但副句仍是「清空名称和仅上涨过滤。」。

> 一期至十四期正文不改写。十二期把内存表「仅上涨」锁成有界 `.rising` 投影，并把 **ON 且投影为空**（含名称把 rising 行藏掉）收成仅上涨两行空态、**不强制**空态按钮；名称无匹配仍走「没有匹配的 App」+「换个名称试试，或清空过滤。」且按钮只写 `filter = ""`——**本文只覆盖这条内存页空态缺口**：过滤空态一次清名称 **和** 仅上涨，回到**当前排序**的完整已采表，不重取数。不重开十二期过滤谓词 / Top5 / 趋势算法，不重开十三期重试，不重开十四期菜单栏排序，不改 Sampler，不把清空传到其它 Tab。GPU Tab、全表 ring、新 cadence、恐吓文案仍不做。

**已锁定**：十五期 = **内存页过滤空态双清（产品终锁 B）**。谁：内存表已经被名称和 / 或「仅上涨」滤空、想一次回到全表的人。情境：现在名称空态只清名称；仅上涨空态没有按钮，组合空态还走「Top5 暂无上涨」。成功：点空态配对按钮 **清空过滤**，同一拍 `filter = ""` 且 `risingOnlyFilter = false`，表立刻按**当前** `tableSort` 展示完整 `rows`，不调 `sample()`。

文案终锁 **B**（产品已拍板，不是设计建议，不是待决）：

| 内存表过滤空态 | 标题（原句保留） | 副文案 | 按钮 |
| --- | --- | --- | --- |
| **纯仅上涨**（无名称过滤） | **Top5 暂无上涨** | **其他进程未做趋势判断**（十二期原句，解释有界 Top5，避免误读全表已判断） | **清空过滤**（本刀补；今日无按钮） |
| **有名称过滤**（名称单列，或名称＋仅上涨组合） | **没有匹配的 App** | **清空名称和仅上涨过滤。** | **清空过滤** |

A（两类空态都改成统一清空副文案、换掉「其他进程未做趋势判断」）**不是**本刀产品锁。实现不得把纯仅上涨副文案改成「清空名称和仅上涨过滤。」。前期讨论过 A，产品已改判 B。无其它待决。

仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。按钮只与上述过滤空态**配对出现**：空态在则按钮在，空态消失则按钮消失。禁止工具栏再放一枚无条件「清空过滤」，禁止空态走后按钮还留着。选中只走现成 `MemoryGrowthRisingFilter.selectedPid`：名称清空不复活已失效选中；仅上涨 OFF 不复活已失效选中。采样周期不变；**零新 Sampler period / cadence**，不改 `sample()` / tick / `setMemoryPageSort`。不新开 entitlements。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：Grok Bot 主控书面转达的十五期产品锁，以及产品终锁 B（纯仅上涨保留十二期两行，仅补按钮；有名称过滤才用统一清空副文案；组合标题仍「没有匹配的 App」）。对照 main `614fa46c6773e6c0f487116cb82ce587a3aed2bb`（十四期②已合）的现实现，见下一节「现模型里有什么」。本文是 DESIGN SCOPE，不是合并或实现授权。实现等本设计合并 + Grok merge gate 后再写 Swift。本 PR 不写 Swift、不合并。

## 范围（相对一二三四五六七八九十十一十二十三十四期）

| 项 | 一二三四五六七八九十十一十二十三十四期 | 十五期首包 |
| --- | --- | --- |
| 定位 | 十二期：内存 Tab「仅上涨」投影 + 两行 ON 空态、无强制按钮；名称空态按钮只清 `filter` | **空态双清**：内存页过滤空态一次 `filter="" + risingOnlyFilter=false`，回当前排序完整表 |
| 纯仅上涨空态 | 标题「Top5 暂无上涨」+ 副句「其他进程未做趋势判断」；**无**按钮 | **做**：两行**原句保留**；只补按钮「清空过滤」 |
| 名称空态 / 组合空态 | 今日组合（名称＋ON 且 `visibleCount==0`）走 `.risingOnlyEmpty`（`MemoryTablePhaseTests.testOnPlusNameHideStillUsesRisingEmptyNotNameEmpty`），标题是「Top5 暂无上涨」；名称 OFF 空态标题「没有匹配的 App」、副句「换个名称试试，或清空过滤。」、按钮只写 `filter=""` | **做**：只要名称过滤启用（含组合）→ 标题 **没有匹配的 App** + 副文案 **清空名称和仅上涨过滤。** + 按钮 **清空过滤**（一次双清）。这是空态**标题分流**，不改十二期 `apply` 谓词 |
| 过滤谓词 / Top5 / 趋势 | `rows` → 名称 →（内存页且 ON）`badge != nil`；N=5；`evaluate` 不改 | **不改** |
| 四列排序 / `rows` / 选中 | `tableSort.ordered(visibleRows)`；`selectedPid` 走 `MemoryGrowthRisingFilter.selectedPid` | **不改排序、不改 `rows`、不改 publication**。双清后仍用当前 sort 排完整 `rows` |
| 采样 / 重试 | 十三期单消费者；失败空态「重试」 | **不重开**。双清不调 `sample()` / `retrySampling()` |
| 菜单栏 Top3 | 十四期跟内存页四列排序 publication | **不重开十四期**。双清不写 publication、不灌过滤进菜单栏 |
| CPU / 网络 / 磁盘名称空态 | 共用 `ProcessTablePane.filterEmpty`：同一副句、按钮只清 `filter` | **不改**。禁止把内存页新副文案 / 双清说成其它 Tab 的附带收益 |
| 工具栏 | 内存 Tab 右侧「仅上涨」Toggle + `AppFilterField`（其 x 无障碍名也是「清空过滤」，**只清名称**） | **不移动上涨开关、不改工具栏布局、不把空态按钮塞进工具栏** |
| GPU / 新 Tab / 全表 ring / 新 cadence | 禁止 | **仍禁止** |
| Helper / entitlements / Electron | 无 | **仍无** |

一二三四五六七八九十十一十二十三十四期验收与公证路径不因本文重开。十二期过滤谓词、九期 Top5、三期趋势、十三期重试、十四期菜单栏排序不重开。内存页**过滤空态**的标题分流、副文案分支与双清按钮以**本文**为准（覆盖十二期「组合走仅上涨空态、不强制按钮」的空态表面；十二期 TECH 正文不改写）。实现等本设计合并 + Grok merge gate 后再写 Swift。Mark 在技术设计合入后才可开工程。本 PR 不写 Swift、不合并。

## 架构（现实现，读仓库后的结论）

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

本刀落在 **Darwin-free 的 phase / copy / clear 投影 + 现成空态 VStack 接线**，不是第二套过滤状态机，也不是新空态组件体系。

- 主窗表：`rows` → `MemoryGrowthRisingFilter.apply`（名称 + 仅上涨）→ `visibleRows` → `ProcessTableSort.ordered` → `ProcessTablePane.sortedRows`
- 内存表相：`MemoryTablePhaseResolver.resolve(page:loadState:processCount:visibleCount:hasActiveNameFilter:risingOnly:processListFailed:)`
- 资源表相：`CPUPagePhaseResolver`（CPU / 网络 / 磁盘共用）；**没有**仅上涨空态
- 选中：`MemoryGrowthRisingFilter.selectedPid`；VM `applyRisingOnlySelection()` 只在 `risingOnlyFilter.didSet`、`selectPage`、`focusMemoryPage`、成功 `tick` 里调用。**`filter` 无 `didSet`。Views 无 `onChange(of: filter)` / `onChange(of: risingOnlyFilter)`**（仅有 `processListScrollTarget` 与 `scenePhase`）
- 双清是对两枚已有 `@Published` 的同步写入；`visibleRows` / phase 是派生，禁止再加一份 filtered-phase 存储

约束：

- 不新开第二套 VM、不新开第二路 Mach、不调 `sample()`。
- 不把 `AppEmptyState` 的重试 chrome 复用成清空过滤（那是十三期失败态）。过滤空态继续用现成 `ProcessTablePane` 的 `VStack` 标题 / 副句 / `Button`，只把门控与文案按 B 分开。
- 不改 `Pulse.entitlements`、不改公证脚本、不改 Sampler Actor、不改十四期 publication。
- 自身占用仍优先：清空是投影，不是重采样。

### 现模型里有什么（必须按「已有 / 没有」落笔）

对照 `MemoryDashboardVM.swift`、`ProcessTablePane.swift`、`MemoryDashboardView.swift`、`SharedUI.swift`、`MemoryTablePhase.swift`、`MemoryGrowthRisingFilter.swift`、`CPUPage.swift`、`MemoryTablePhaseTests.swift`、`MemoryGrowthRisingFilterTests.swift`、`Package.swift`。禁止把别处 agent 报告当成已核实源代码。

| 现字段 / 调用 | 文件 | 十五期怎么用 |
| --- | --- | --- |
| `MemoryDashboardVM.filter` | `ViewModels/MemoryDashboardVM.swift` | `@Published var filter = ""`。**无 `didSet`**。名称查询；`hasActiveFilter` = trim 后非空 |
| `MemoryDashboardVM.risingOnlyFilter` | 同上 | `@Published`；默认 `false`；会话级，不写 Sampler / 偏好。`didSet`：值变化才 `applyRisingOnlySelection()` |
| `visibleRows` | 同上 | `MemoryGrowthRisingFilter.apply(rows:nameQuery:page:risingOnly:seriesByPid:)`。双清后这两枚输入变了，派生立刻是名称未滤 ∩ 仅上涨 OFF = 完整 `rows`（内存页） |
| `MemoryGrowthRisingFilter.apply` | `Models/MemoryGrowthRisingFilter.swift` | **谓词不改**。名称先行；仅当 `risingOnly && page == .memory` 才留 `badge != nil` |
| `MemoryGrowthRisingFilter.selectedPid` | 同上 | **选中唯一规则，本刀不新写**。ON+内存：无列表徽标则清；名称把仍 rising 的 pid 藏掉 **保留** `current`（`_ = (rows, nameQuery)`）；OFF 原样返回 `current`，**不复活**已被本开关清掉的 pid |
| `applyRisingOnlySelection()` | VM `private` | 把上一行结果写进 `selectedPid`。`guard next != selectedPid`。双清不要再叠一次无意义重写 |
| `hasActiveFilter` | VM | 只看名称 trim，**不**看 `risingOnlyFilter` |
| `tableSort` / `navigation` / `publication` | VM + `CPUPage` + `MemoryPageSortPublication` | **不写**。双清不改四列排序、不改 Tab、不改菜单栏 publication |
| `start` / `tick` / `retrySampling` | VM | **不改**。双清不是重试，不打断 sleep，不清 snapshot / rows / 历史 |
| `MemorySampler.sample` / `setMemoryPageSort` | `Sampling/MemorySampler.swift`（**不在** SamplingCore） | **不改**。双清禁止 `await sampler.sample()` |
| `MemoryTablePhase` / `MemoryTablePhaseResolver` | `Models/MemoryTablePhase.swift`（SamplingCore） | **本刀要改优先级**：今日 `visibleCount==0` 后先 `isRisingOnlyEmpty` 再 `hasActiveNameFilter`，所以组合走 `.risingOnlyEmpty`。B：有名称过滤（含组合）走 `.nameFilterEmpty`；纯仅上涨才 `.risingOnlyEmpty` |
| `MemoryGrowthRisingFilter.isRisingOnlyEmpty` | 同上 + Filter | 今日：`page == .memory && risingOnly && projectedCount == 0`，**不看**名称。可保持谓词；**resolver 必须先看 `hasActiveNameFilter`**，否则组合会继续盖住「没有匹配的 App」 |
| `MemoryGrowthRisingFilterCopy` | Filter | 纯仅上涨两行锁词，**B 原样保留**。不要改成清空副文案 |
| `MemoryTableEmptyCopy.risingOnlyLines` | `MemoryTablePhase.swift` | 只服务 `.risingOnlyEmpty`。组合改走名称空态后，这里继续只返回十二期两行 |
| `ProcessTablePane.memoryPhase` | `Views/ProcessTablePane.swift` | 已把 `hasActiveNameFilter: vm.hasActiveFilter`、`risingOnly: vm.risingOnlyFilter` 喂给 resolver。接线跟新优先级 |
| `ProcessTablePane.filterEmpty` | 同上 | **今日被内存 `.nameFilterEmpty` 与 CPU/网络/磁盘 `.filteredEmpty` 共用**。标题「没有匹配的 App」；副句「换个名称试试，或清空过滤。」；按钮 `vm.filter = ""`。**缺口**：内存页要换副句并双清；资源页必须留今日行为。禁止改共用函数却声称「只动内存页」 |
| `ProcessTablePane.risingOnlyEmpty` | 同上 | 十二期两行，**无按钮**。纯仅上涨补同一「清空过滤」，接双清；**副句不得改** |
| `AppFilterField` | `Views/SharedUI.swift` + `MemoryDashboardView` 工具栏 | 保留。其 x 无障碍名「清空过滤」**只把 `text = ""`**（即只清名称）。**不是**本刀空态按钮，不要改成双清 |
| `MemoryRisingOnlyChrome.showsToggle` | `MemoryTablePhase.swift` | 仍仅内存 Tab 画开关。不移动 |
| `CPUPagePhaseResolver` | `Models/CPUPage.swift` | 资源页：`hasActiveFilter && visibleCount==0` → `.filteredEmpty`。**不改** |
| `AppEmptyState` | `SharedUI.swift` | 失败 / 无进程 / 重试。**不要**把清空过滤塞进 `onRetry` |
| Sampler / Top5 / 菜单栏 | 九 / 十二 / 十四期 | **不进本刀** |

**缺口（已核，不是采样缺口）**：

1. 内存页没有「一次清名称 + 仅上涨」的同步动作。名称空态按钮只写 `filter`；仅上涨空态无按钮；工具栏 x 也只清名称。
2. 组合空态今日标题是「Top5 暂无上涨」，与产品终锁「没有匹配的 App」不符。这是 **resolver 优先级**缺口，不是要新 phase 枚举。
3. `filterEmpty` 跨 Tab 共用。若直接改文案 / 动作，会把 CPU / 网络 / 磁盘一并改掉——锁稿禁止。
4. 没有 Darwin-free 的「clear 后两枚输入 + `selectedPid`」纯函数；VM 清动作今日也不存在。Linux 测得了 phase / copy / selectedPid，测不到 VM 实例。

因此本刀：

1. **不改 Sampler**（不改 `sample()` / tick / cadence / `setMemoryPageSort`）。
2. **不改** `MemoryGrowthRisingFilter.apply` 与 `selectedPid` 规则。
3. **只改**内存表过滤空态的 phase 分流、B 文案、以及一个同步双清入口。
4. 资源页名称空态保持今日副句与 `filter=""`。
5. 不要 `@Published` 新相、不要等下一 tick、不要新空态框架。

### 文案终锁 B（分支验收，防止误覆盖纯上涨）

产品已拍板 B。下面三行是实现 / 单测必须分开钉死的表面；混用即不合格。

| 分支 | 判定（内存页、`processCount > 0`、`visibleCount == 0`） | 标题 | 副文案 | 按钮 | 动作 |
| --- | --- | --- | --- | --- | --- |
| 纯仅上涨 | `risingOnlyFilter == true` 且 **无**名称过滤（`!hasActiveFilter`） | Top5 暂无上涨 | 其他进程未做趋势判断 | 清空过滤 | 双清 |
| 名称单列 | 有名称过滤且 `risingOnlyFilter == false` | 没有匹配的 App | 清空名称和仅上涨过滤。 | 清空过滤 | 双清 |
| 组合 | 有名称过滤且 `risingOnlyFilter == true` | 没有匹配的 App | 清空名称和仅上涨过滤。 | 清空过滤 | 双清 |

锁词（精确，含中文句号）：

| 表面 | 锁定字符串 |
| --- | --- |
| 名称 / 组合标题 | `没有匹配的 App` |
| 名称 / 组合副文案 | `清空名称和仅上涨过滤。` |
| 纯仅上涨标题 | `Top5 暂无上涨` |
| 纯仅上涨副文案 | `其他进程未做趋势判断` |
| 按钮 | `清空过滤` |

禁止：

- 把纯仅上涨副文案改成「清空名称和仅上涨过滤。」（那是已否决的 A）。
- 组合标题写成「Top5 暂无上涨」（那是今日实现，不是 B）。
- 名称 / 组合副句继续「换个名称试试，或清空过滤。」（内存页换新句；资源页仍用旧句）。
- 第二套按钮文案（「关闭仅上涨」「清空名称」）；产品锁的按钮就是「清空过滤」，动作是双清，不是只请用户去关开关。
- 名称单列空态只清 `filter`、让用户自己关「仅上涨」。

### phase 分流（最小改动）

现成枚举已经够用：`.nameFilterEmpty` / `.risingOnlyEmpty`。**不要**为组合新增 case。

`processCount == 0` 的采样 / 进程列表失败 / 失败 / 无进程 **仍优先**（今日 `MemoryTablePhaseResolver` 前半段不改）。`visibleCount > 0` 仍 `.ready`（空态不出现，按钮不出现）。

`visibleCount == 0` 且 `processCount > 0` 之后，B 的顺序是：

1. `hasActiveNameFilter` → `.nameFilterEmpty`（名称单列 **和** 组合）
2. 否则 `MemoryGrowthRisingFilter.isRisingOnlyEmpty` → `.risingOnlyEmpty`（纯仅上涨）
3. 否则 `.empty`

这与今日顺序相反。今日单测 `testOnPlusNameHideStillUsesRisingEmptyNotNameEmpty` **必须改成**组合 → `.nameFilterEmpty`，标题走「没有匹配的 App」，**不得**再断言组合是 `.risingOnlyEmpty`。

`CPUPagePhaseResolver` 一字不改。非内存 `page` 传入 `MemoryTablePhaseResolver` 时，`isRisingOnlyEmpty` 本就是 false，资源页名称空态继续 `.nameFilterEmpty` 相——但 **View 不得复用内存页新副句 / 双清**。

### 双清模型（一次同步，不等 sample）

Darwin-free 纯函数（可与 Filter / Phase 同层，不要新 UI 类型）：输入当前 `filter` / `risingOnly` / `selectedPid` + 现成 `rows` / `page` / `seriesByPid`；输出：

- `filter = ""`
- `risingOnly = false`
- `selectedPid = MemoryGrowthRisingFilter.selectedPid(current:current, rows:rows, nameQuery:"", page:page, risingOnly:false, seriesByPid:seriesByPid)`

因为 OFF 分支是 `return current`，这个输出对选中是**身份**：

| 双清前 `selectedPid` | 双清后 | 验收 |
| --- | --- | --- |
| `nil`（含：仅上涨 ON 已因无徽标清掉） | `nil` | **不复活**失效选中。禁止按 badge / 上一行 pid 再选回去 |
| 仍是某个 pid（含：名称把仍 rising 的行藏掉而保留的选中；或 OFF 时名称藏行不清选中） | 同一 pid | 不是「用 badge 留选」。OFF 根本不看 badge。该 pid 若还在 `rows` 里，全表可见后仍是该行 |
| 不要新写「清空名称则 `selectedPid = nil`」 | — | 那会回退十二期「名称过滤藏行不清选中」 |

VM 接线（刀②，Linux 测不到实例）：

```
@MainActor
func clearMemoryPageFilters() {
    filter = ""
    risingOnlyFilter = false
}
```

要点：

- **一次方法里同步写两枚** `@Published`。即使其中一枚已是默认值也写（产品锁的是这一次动作，不是「只写脏的那枚」）。
- 不要给 `filter` 新加 `didSet`。今日名称变更本来就不走 `applyRisingOnlySelection`；加上会在双清路径上多一次选中计算。
- `risingOnlyFilter` 从 `true` → `false` 时，现成 `didSet` 已经用 **OFF** 调一次 `applyRisingOnlySelection`（身份，不复活）。方法末尾**不要再调一次**，避免无意义选中重写。若本已是 `false`，`didSet` 的 `oldValue !=` 早退，选中不动。
- 不要等 `tick` / `sample()`。`visibleRows` 是计算属性，写完两枚，同一拍表就是当前 `tableSort.ordered(rows)`。
- 不要写 `navigation` / `tableSort` / `publication` / `loadState` / `rows` / `topMemorySeries`。
- 不要新 `@Published` filtered-phase。phase 继续由 resolver 从现字段派生。

Views 现无 `onChange(of: filter)` / `risingOnlyFilter`。双清不要为此新加 onChange 去「再校正」选中。

工具栏 `AppFilterField` 的 x：**保持只清名称**。用户若在组合空态点的是搜索框 x 而不是空态按钮：`filter=""`、仅上涨仍 ON → 若此时有 rising 行则回 `.ready`；若仍无 rising 行则落到**纯仅上涨**空态（十二期两行 + 本刀按钮）。这是现成搜索框语义，不是漏做双清。

### 按钮何时出现 / 何时不能出现

「有配对时按钮不动出现」= **空态配对**，不是空态消失后还留按钮，也不是工具栏常驻按钮。

| 条件 | 内存表 | 「清空过滤」空态按钮 |
| --- | --- | --- |
| `.nameFilterEmpty`（名称单列或组合） | B 标题 + 清空副文案 | **出现**，双清 |
| `.risingOnlyEmpty`（纯仅上涨） | 十二期两行 | **出现**，双清 |
| `.ready`（过滤全命中或部分命中，`visibleCount > 0`） | 表 | **不出现**（即使开关仍 ON 或名称仍有字；工具栏 x / Toggle 是另一套现成控件） |
| `.sampling` / `.failed` / `.processListFailed` | 现成骨架或「重试」 | **不出现**（不要跟十三期重试抢按钮） |
| `.empty`（原始 `rows` 空，`processCount == 0`） | 「没有可显示的进程」 | **不出现**（即使此时有残留 filter 字符串：无进程门仍优先） |
| 过滤全不命中（有 `rows` 但 `visibleCount == 0`） | 上表三分支之一 | **出现**（在对应空态里） |

列头：今日 `showsColumnHeader = !vm.rows.isEmpty`，过滤空态（`processCount > 0`）仍画四列表头。**不改**。点列仍 `setTableSort`；双清不重置 sort。

### 资源页（必须门控，不是附带收益）

CPU / 网络 / 磁盘继续：

- 标题「没有匹配的 App」
- 副句「换个名称试试，或清空过滤。」
- 按钮「清空过滤」→ **只** `vm.filter = ""`
- 不写 `risingOnlyFilter`（会话里它可能仍为 true，但资源页 `apply` 本就不吃它；从资源页空态双清会变成「全 Tab 清除」，锁稿 Won't）

`ProcessTablePane.filterEmpty` 必须按 `selectedPage`（或 phase 来源）拆开。不要新组件体系：内存名称 / 组合走 B 文案 + `clearMemoryPageFilters()`；资源页留今日 VStack。纯仅上涨继续用 `risingOnlyEmpty`，只加按钮。

### 选中与侧栏（既有规则，本刀验收）

只调用现成 `MemoryGrowthRisingFilter.selectedPid`，不新开事务 / 状态机。

| 事件 | 规则（已在十二期实现 / 单测里） | 十五期双清 |
| --- | --- | --- |
| 名称藏行 | 不清 `selectedPid`；侧栏仍可对完整 `rows` 退出 | **不回退** |
| 仅上涨 ON 且当前 pid 无列表徽标（含不在 Top5） | 同一拍清 `selectedPid` | **不回退** |
| 仅上涨 ON 且当前 pid 仍有徽标、只是被名称藏掉 | 保留 `selectedPid` | 双清后 OFF：身份保留；全表可见后仍是该行。这不是复活 |
| 仅上涨 OFF | 返回 `current`，不把已 nil 的选中救回 | 双清走这条。单测钉：ON 清掉的 pid，双清后仍 nil |
| 名称清空 | 今日 `filter` 无 didSet，选中不动；不得改成「按 badge 再选一个」 | 空态按钮不是「只清名称」。双清后 OFF 也不按 badge 留选 / 复活 |
| `tick` 里 pid 离开 `rows` | 现成清选中 | **不改** |

「名称清空不沿用 badge 留选 / 不复活选中」：清空动作**禁止**根据 `MemoryGrowthList.badge` 去保留或挑回一个 pid。Badge 留选只属于「仅上涨仍 ON」的现成 `selectedPid` 规则；双清已经 OFF，不再走那条 keep。

### 明确不做（相对本刀）

- 改 Sampler / `sample()` / tick / cadence / `setMemoryPageSort`。
- 重开十四期 publication / 菜单栏布局 / Top3。
- 重开十三期重试；把清空过滤接到 `retrySampling`。
- 改十二期 `apply` 谓词、N=5、`evaluate`、徽标样式、详情三态。
- 全 Tab / 其它 Tab 清除；自动清筛选；过滤计数；移动「仅上涨」开关。
- 工具栏再放一枚双清按钮；空态消失后仍留按钮。
- 把 CPU / 网络 / 磁盘名称空态改成内存页副句或双清。
- 新 `@Published` 过滤相、等下一 sample、新空态框架、把 `AppEmptyState` 改成通用「动作空态」。
- 给 `filter` 加 didSet / 新 onChange 去叠选中重写。
- 双清重置 `tableSort` / 跳回默认内存降序。
- 用源码字符串匹配冒充 VM / GUI 实例行为（源码结构检查若做，必须标明不是行为测试）。

## 建议工程顺序

两刀，不要拆成另一套过滤状态机，不改其它范围。实现等本设计合并 + Grok merge gate 后再写 Swift。Mark 在技术设计合入后才可开工程。本 PR 不写 Swift、不合并。

1. **Darwin-free 的 clear 投影 / phase 分流 / B 锁词 + Linux `swift test`**：resolver 先名称后仅上涨；钉三分支标题 / 副文案；钉双清输出 `filter="" && risingOnly==false`；钉 `selectedPid` 身份与「OFF / 清空不复活」；钉采样 / 失败 / 无进程仍优先；钉 `CPUPagePhaseResolver` 文案与相不变。零 AppKit，不编 App。
2. **UI 同源接线**：VM 一个 `clearMemoryPageFilters()` 同步写两枚 `@Published`；内存 `.nameFilterEmpty` / `.risingOnlyEmpty` 接该动作与 B 文案；资源页 `filterEmpty` 保持旧副句与只清名称。不改工具栏、不改 Sampler。

没有硬伤就不开第三条 polish PR。不要和 GPU / 全表 ring / 十四期菜单栏 / 十三期重试捆在一起。

## 风险

| 风险 | 应对 |
| --- | --- |
| 按已否决的 A 改掉「其他进程未做趋势判断」 | 分支表写死；纯仅上涨单测钉原两行 |
| 组合仍走 `.risingOnlyEmpty`，标题变成 Top5 | resolver 先 `hasActiveNameFilter`；改十二期那条组合单测 |
| 改共用 `filterEmpty`，CPU/网络/磁盘副句/动作被顺手改掉 | View 按页门控；资源页单测 / 锁词保持旧句 |
| 给 `filter` 加 didSet 或双清后再 `applyRisingOnlySelection` | 造成无意义选中重写；VM 方法只写两枚字段 |
| 空态按钮只清名称 / 只关开关 | 产品锁双清；按钮文案仍是「清空过滤」 |
| 工具栏 x 被改成双清 | 写死：x 仍只清名称 |
| 把按钮放进工具栏或 `.ready` 后仍显示 | 只挂在两个过滤空态 VStack |
| 双清调 `sample()` / 重置 sort | 范围表零 Sampler、不写 navigation |
| 清空时按 badge 复活已 nil 的 pid | 只走现成 `selectedPid`；OFF 返回 current |
| 源码结构测试写成「已验双清行为」 | Linux / Mac 分界写死 |
| Helper / GPU / 恐吓文案 | 范围表写死不加 |

## 验收（十五期首包）

产品 Must（B）：

- [ ] 纯仅上涨空态（内存页、无名称过滤、ON、`visibleCount==0`、有 `rows`）：标题恰为 **Top5 暂无上涨**，副文案恰为 **其他进程未做趋势判断**，有按钮 **清空过滤**。副文案不得换成「清空名称和仅上涨过滤。」
- [ ] 名称单列空态（内存页、有名称过滤、OFF、`visibleCount==0`、有 `rows`）：标题 **没有匹配的 App**，副文案 **清空名称和仅上涨过滤。**，按钮 **清空过滤**
- [ ] 组合空态（内存页、有名称过滤、ON、`visibleCount==0`、有 `rows`）：标题仍 **没有匹配的 App**（不是「Top5 暂无上涨」），副文案 **清空名称和仅上涨过滤。**，按钮 **清空过滤**
- [ ] 上述任一按钮：同一拍 `filter==""` 且 `risingOnlyFilter==false`；表按**当前** `tableSort` 展示完整 `rows`；不调 `sample()` / 不改 cadence / 不重置 sort
- [ ] 按钮只与上述过滤空态配对；`.ready` / 采样 / 失败 / 原始 `rows` 空 **不**出现该按钮；工具栏不新增双清控件
- [ ] 选中只走 `MemoryGrowthRisingFilter.selectedPid`：双清不复活已被仅上涨清掉的 pid；不按 badge 另留 / 另选；名称藏行不清选中的规则不回退
- [ ] CPU / 网络 / 磁盘名称空态：仍「没有匹配的 App」+「换个名称试试，或清空过滤。」+ 按钮只清 `filter`
- [ ] 十二期谓词、九期 Top5、三期趋势、十三期重试、十四期菜单栏、四列表头 / `setTableSort` 不回退
- [ ] 永不写「泄漏」/ leak / 「危险」

测试矩阵（实现 PR 必须覆盖能 Linux 测的项；VM / GUI 标 Mac 剩余）：

**phase / 文案 / clear 投影（Linux）：**

1. 采样 / 进程列表失败 / 失败 / `processCount==0`：即使 `risingOnly==true` 或有名称过滤，仍不是过滤空态、无双清按钮锁词要求
2. 纯仅上涨：`.risingOnlyEmpty`；两行原句；`risingOnlyLines` 非 nil
3. 名称单列：`.nameFilterEmpty`；不是 `.risingOnlyEmpty`
4. 组合：`.nameFilterEmpty`（**覆盖**今日「组合走 risingOnlyEmpty」）；`risingOnlyLines(for:)` 为 nil
5. `visibleCount>0`：`.ready`，无仅上涨空态行
6. 双清纯函数：任意脏 `filter` / `risingOnly==true` → `""` + `false`；`selectedPid==nil` 保持 nil；已有 pid 保持同一 pid（OFF 身份）
7. 先模拟 ON 把无徽标 pid 清成 nil，再双清：仍 nil（不复活）
8. `CPUPageCopy` / 资源 phase：名称空态相与锁词不因本刀改变
9. 禁词：新锁词不含泄漏 / 危险

**接线（刀②；Linux 至多源码结构检查，且必须标明不是实例行为）：**

10. VM 存在单一同步方法写 `filter` 与 `risingOnlyFilter`，方法内无 `sample()` / `retrySampling()` / `setTableSort` / `setMemoryPageSort`
11. 内存过滤空态按钮接到该方法；资源页按钮仍只写 `filter`
12. 工具栏 Toggle / `AppFilterField` 布局不改为双清入口

明确不做（本包出现即不合格）：

- [ ] 无 GPU / 新 Tab / 全表 ring / 新 cadence
- [ ] 无把纯仅上涨副文案改成统一清空句（否决的 A）
- [ ] 无组合标题「Top5 暂无上涨」
- [ ] 无工具栏常驻双清、无空态消失后残留按钮
- [ ] 无 CPU / 网络 / 磁盘双清或换内存页副句
- [ ] 无 Sampler / 十四期 publication / 十三期重试改写
- [ ] 无新过滤状态机 / 新空态框架
- [ ] 无恐吓文案、无「泄漏」
- [ ] 无「源码匹配 = 已验双清实例」

共性：

- [ ] 一二三四五六七八九十十一十二十三十四期验收不回退
- [ ] 冷启动仍默认内存页
- [ ] Linux：`swift test` 跑 phase 分流 + B 锁词 + clear 投影 + 既有 `selectedPid` / 资源页测试
- [ ] 不改公证脚本与 entitlements

### Linux 可测 vs Mac 剩余

已核 `Package.swift`：SamplingCore **列入** `Models/MemoryTablePhase.swift`、`Models/MemoryGrowthRisingFilter.swift`、`Models/CPUPage.swift`、`Models/ProcessSelection.swift`。**排除** `ViewModels/`、`Views/`、`Sampling/MemorySampler.swift`。因此：

- resolver 优先级、B 锁词、clear 纯函数、`selectedPid` 身份 / 不复活：Darwin-free，Linux CI 可实跑。
- `MemoryDashboardVM.clearMemoryPageFilters()`、SwiftUI 点按钮、工具栏 x 与空态按钮分工、Xcode 主窗：**不能**在 Linux 声称已测。
- 若刀②加 VM 源码结构检查：必须写明「不是 VM 行为测试 / 不是 GUI」。

本 docs PR **不跑**、也不声称：

- `MemoryDashboardVM` 实例测试
- Xcode GUI / 点空态按钮 / 触控
- 实机 Sampler 帧

Mac 冒烟（**仅**本设计已合并且实现合并后；不挡本文档审阅）：

- 纯仅上涨：两行原句 +「清空过滤」；点一下回全表，排序不变，无新采样闪烁
- 名称无匹配：新副句 + 同按钮；即使开关已 OFF 也是双清（写 `false` 为幂等）
- 名称把全部 rising 行藏掉：标题「没有匹配的 App」，不是 Top5 句；点按钮名称与开关一起清
- 有命中行时没有空态按钮；失败空态仍是「重试」
- CPU Tab 名称空态副句仍是「换个名称试试，或清空过滤。」，只清名称，回来内存页开关可仍 ON
- 仅上涨曾清掉的选中，双清后侧栏仍空，不复活

## 工期

小：两刀都是现成 phase / 两枚 `@Published` / 现成空态 VStack，不是重采样、不是新 UI 体系。① Darwin-free clear / phase + Linux `swift test`；② VM / 空态同源接线。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并 + Grok merge gate 后再写 Swift。Mark 在技术设计合入后才可开工程。本 PR 不写 Swift、不合并。
