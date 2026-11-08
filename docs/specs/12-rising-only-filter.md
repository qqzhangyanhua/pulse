# Pulse 十二期技术设计（首包：内存进程列表「仅上涨」过滤）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 12 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。
>
> 已被取代：「仅上涨」空态十五期起有「清空过滤」按钮；名称过滤同时开着时，名称空态优先，显示「没有匹配的 App」。
>
> 已被取代：过滤顺序已扩展为：名称 → 仅上涨 → 仅窗口 App（#80）→ 按 App 合并（#81）→ 表头排序。
>
> 已被取代：工具栏不再只有「仅上涨」，还有「仅窗口 App」「按 App」，都改成了带标题的胶囊按钮。

> 一期至十一期正文不改写。九期把列表「上涨」徽标锁在当前排序 Top N=5 ∩ `.rising`，并写死禁止无界全表 ring——**本文只覆盖那条扫描延期**：在内存 Tab 工具栏右侧加一枚轻量开关「仅上涨」，打开后进程表只留下**现有可用**的 `.rising` 行。不新开增长算法、不扫全表、不扩 Sampler ring、不改采样周期。GPU Tab、进程级 GPU、无界全表成长环、恐吓文案 / 「泄漏」、自动杀、菜单栏改动、新徽标样式、新 Tab、Helper / XPC、新 entitlements、Electron 仍不做。

**已锁定**：十二期 = **C（内存列表「仅上涨」过滤）**。谁：在长进程表里扫嫌疑的人。情境：Top5 「上涨」徽标不够用，要把表收成「当前已被现有增长信号标成 `.rising`」的行。成功：打开一枚轻量开关，内存进程表只剩 `.rising` 行；行仍可点选，现成 Quit / Force Quit 可用。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。开关只出现在**内存 Tab 工具栏右侧**，文案 **仅上涨**；ON = 只留现有 `.rising`（当前排序 Top N=5 series / 徽标，最多 **0–5 行**，有界子集，**不是**全机判决）；OFF = 恢复完整表。过滤空态两行：主句 **Top5 暂无上涨**，下一行次要字 **其他进程未做趋势判断**。算法仍是三期 `MemoryGrowthSignal.evaluate`，文案仍用现成「上涨」；**禁止**第二套斜率 / 泄漏算法、禁止 rss 两点差、禁止新徽标样式。名称过滤、表头排序、点行选中、侧栏退出**不得回退**。被本开关滤掉的选中行**不得**留下可操作的陈旧侧栏目标。采样周期不变（前台约 1.5s，后台约 2–3s）；**零新 Sampler period / cadence**，**零新 VM / Mach 轮询**。不新开 entitlements、不拆 Helper / XPC。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：用户 + 产品锁定的十二期 Must（十一期 Top3 点选已合 #35–#37；九期密度已合 #29–#31）；对照现实现（`MemoryGrowthSignal.evaluate` 三态；`MemoryGrowthList.badge` 只认 `topMemorySeries` 上的 `.rising`；Sampler 只为当前内存页排序 Top N=5 维护 `MemoryGrowthTopStore`，`pidLimit = 5`，`seriesLimit = 90`；选中 pid 另有 `selectedMemorySeries` / `ProcessDetail.memorySeries` 服务详情三态，不在 Top 5 时列表不亮；`ProcessRow` 无增长字段；管线是 `rows` → `ProcessNameFilter.apply` → `visibleRows` → `ProcessTableSort.ordered` → `ProcessTablePane.sortedRows`；`List(..., selection: $vm.selectedPid)`；`selectedRow` / `quitSelected` / `forceQuitSelected` 对照完整 `rows`，名称过滤藏行**不**清选中；工具栏右侧已是 `AppFilterField`）。

## 范围（相对一二三四五六七八九十十一期）

| 项 | 一二三四五六七八九十十一期 | 十二期首包 |
| --- | --- | --- |
| 定位 | 九期：列表徽标 = 当前排序 Top N=5 ∩ `.rising`；十一期：菜单栏 Top3 点选开主窗 | **过滤（C）**：内存表加「仅上涨」开关，ON 只投影现有 `.rising` 行 |
| 增长算法 | 三期 `MemoryGrowthSignal.evaluate`；六 / 九期禁止第二套 | **仍只调用这一份**。无 rss 两点差、无新阈值 |
| Sampler series | 九期有界 Top N=5 + 三期选中 pid 详情 ring。禁止无界全表 | **零 Sampler 改动**。不扩 ring、不加第 6 条 series、不改 tick |
| 列表徽标 | 九期：pid ∈ Top 5 且 `.rising` 画「上涨」 | **样式 / 出现条件不改**。过滤不发明第二枚芯片 |
| 详情「内存趋势」 | 三期三态（上涨 / 不足可见 / none 不占位） | **不改** |
| 进程表投影 | `rows` → 名称过滤 → 表头排序 | **做（本刀）**：内存页、开关 ON 时，在名称过滤之后再留 `.rising` |
| 工具栏 | 右侧 `AppFilterField`（「过滤 App」） | **做**：内存 Tab 右侧加轻量开关「仅上涨」。名称过滤保留 |
| 过滤空态 | 名称无匹配：「没有匹配的 App」 | **做**：开关 ON 且无 `.rising` 行 → 主句「Top5 暂无上涨」，下一行次要字「其他进程未做趋势判断」 |
| 选中 / 退出 | `selectedPid`；侧栏读完整 `rows`；名称过滤藏行不清选中 | **名称过滤这条不回退**。本开关把选中行滤掉 → **必须**清 `selectedPid`，侧栏不得留下可点退出 |
| 菜单栏 A / B | 十一期 Top3 可点；十期已用内存行不可点 | **本刀不碰菜单栏** |
| GPU Tab / 进程级 GPU | 灰置 / 不做 | **仍灰置、仍不做** |
| 无界全表 ring | 九期只允许 Top N=5 有界 series | **仍不做**。本刀不碰 series / ring |
| 新 Sampler 周期 | 前台 ~1.5s，后台 ~2–3s | **零新 period / cadence** |
| 新 Tab / 新徽标样式 | 无 | **仍无** |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 / 恐吓文案 | 不做 / 禁止 | **仍禁止**。永不写「泄漏」 |

一二三四五六七八九十十一期验收与公证路径不因本文重开。九期 Top5 徽标、三期详情三态、名称过滤、十一期菜单栏点选不重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

优先**延长**现成列表投影，不要另起 Sampler、不要给 `ProcessRow` 加 `isRising`，也不要第二套增长数学。

- `SwiftUI Views`（内存页 `ProcessTablePane` / 工具栏）←观察→ 同一 `MemoryDashboardVM`
- 开关是 VM 上的一枚轻量布尔（例如 `risingOnlyFilter`），**只在** `selectedPage == .memory` 时参与投影
- 现成管线延长为：`rows` → `ProcessNameFilter.apply` →（内存页且 ON 时）只留现有 `.rising` → `ProcessTableSort.ordered`
- `.rising` 谓词复用 `MemoryGrowthList.badge` / `MemoryGrowthSignal.evaluate(topMemorySeries[pid]) == .rising`——与列表徽标**同一份**输入
- 详情侧栏继续走 `memoryGrowthSlot` / `MemoryGrowthSidebar`——**本刀不改详情三态**
- Sampler 同一 `sample()` tick、同一周期、同一 `MemoryGrowthTopStore`（N=5 硬封顶）
- VM ←订阅快照→ `MemorySampler`（同一 Actor）；过滤**不**调 `sample()`

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询。
- 过滤是只读投影，不是第二条判定，也不是新时序源。
- 不改 `Pulse.entitlements`、不改公证脚本、不改菜单栏 A / B。
- 自身占用仍优先：禁止借「仅上涨」做成无界全表 ring。
- `ProcessLine` 跨 Tab 复用——开关与投影必须按页门控，禁止 CPU / 网络 / 磁盘表被顺手收成「上涨」。
- 增长信号仍不进 `ProcessRow` 采样字段。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `MemoryGrowthSignal.swift`、`MemoryGrowthList`、`MemoryGrowthTopSeries`、`MemoryDashboardVM`、`ProcessTablePane`、`MemorySampler`、`ProcessNameFilter`、九 / 三期 TECH。本刀必须按「已有 / 没有」落笔，**禁止**为了让空态在全表意义上成立再发明一套 series，也**禁止**把「没有 series」标成「非上涨」。

| 现字段 / 调用 | 文件 | 十二期怎么用 |
| --- | --- | --- |
| `MemoryGrowthSignal.evaluate` | `Models/MemoryGrowthSignal.swift` | **原样调用**。`minSamples = 80` / `deltaThreshold = 8 MiB` / `riseFloor = 0.6` 不改。三态：`.insufficient` / `.rising` / `.none` |
| `MemoryGrowthList.badge` | 同上 | **过滤谓词就复用它**（非 nil ⟺ 该行当前是列表「上涨」）。`seriesByPid` 仍是 `topMemorySeries` |
| `MemoryGrowthListCopy` / `MemoryGrowthRisingBadge` | 同上 + `ProcessTablePane` | 文案「上涨」/「近期内存持续上涨」、次要色胶囊 **原样**。不新开样式 |
| `MemoryDashboardVM.topMemorySeries` | `ViewModels/MemoryDashboardVM.swift` + `SampledFrame.topMemorySeries` | **过滤的唯一 per-row 输入**。来自九期有界 Top 5 |
| `MemoryGrowthTopSeries` / `MemoryGrowthTopStore` | `Models/MemoryGrowthTopSeries.swift` + `Sampling/MemorySampler.swift` | **不改**。`pidLimit = 5`；跌出即 drop；不吃名称过滤、不吃本开关 |
| `ProcessDetail.memorySeries` / `selectedMemorySeries` | Sampler 选中 pid ring | **详情唯一输入**。选中但不在 Top 5 时列表本来就不亮——**不要**拿它当第二路过滤源 |
| `ProcessNameFilter` / `visibleRows` / `filter` | `Models/CPUPage.swift` + VM | **保留、先于**上涨投影。名称过滤语义不回退 |
| `ProcessTableSort.ordered` | `Models/CPUPage.swift` | 过滤之后仍走现成表头排序（内存页默认内存降序） |
| `ProcessTablePane.sortedRows` / 空态 | `Views/ProcessTablePane.swift` | 接线吃新投影。开关 ON 且结果空 → 锁定空态句；名称过滤空态句不删 |
| `selectedPid` / `selectedRow` / `quitSelected` | VM + `ProcessDetailSidebar` | 点行仍写 `selectedPid`。`selectedRow` 今日对照完整 `rows`——本开关滤掉选中行时**必须先清选中**，否则侧栏仍可退出已藏行 |
| `AppFilterField` | `Views/SharedUI.swift` + `MemoryDashboardView` 工具栏 `primaryAction` | **保留**。开关另挂内存 Tab 右侧，不要替换搜索框 |
| Sampler `sample()` / `SamplingPace` | `Sampling/MemorySampler.swift`、`SamplingPace.swift` | **不改**。无新字段、不改 tick、不第二路 Mach |

**缺口**：全表绝大多数行**没有** series。九期故意只给当前排序 Top N=5 攒短 ring；`evaluate([])` 是 `.insufficient`，不是 `.none`。这**不是**算法缺口，也**不是**本刀扩采样的理由。

因此本刀：

1. **零 Sampler 改动**（无新字段、不改 tick、不第二路 Mach、**零新 period / cadence**、不把 N 从 5 放开）。
2. **只过滤现有可用的 `.rising`**。ON 表进入的行 = 内存页 + `MemoryGrowthList.badge(...) != nil`，也就是 `pid ∈ topMemorySeries` 且 `evaluate == .rising`。上限 **0–5 行**（九期硬封顶），不是「全机所有正在涨的进程」。
3. **不足 / 无 series / `.none` 都不得标成「非上涨」**。它们只是「当前没有可用的上涨标记」，不进入 ON 表，角标位也不写「—」。
4. 选中但不在 Top 5：详情三态仍可单独评出 `.rising`（三期 ring），列表今日不亮。ON 后该行**不进入**过滤结果——这是九期「选中但不在 Top 5 → 列表不亮」的同一条，不是漏做。此时必须清 `selectedPid`，避免侧栏对已藏行仍可退出。
5. **不要**给 `ProcessRow` 加 `isRising`。**不要**用相邻两帧 `memoryBytes` 冒充上涨。
6. 名称过滤、表头排序、CPU / 网络 / 磁盘投影、菜单栏 Top3（吃完整 `rows`）都不改语义。
7. Top 5 集合**不**跟本开关走（与九期「不吃 `visibleRows`」同一精神）。开关只决定画不画那一行。

#### 覆盖决议（写死，不扩范围）

产品 / 设计已拍板：本刀只过滤**现有可用 `.rising`**——当前内存页排序 Top N=5 有界 series / 九期列表徽标。ON 表最多 **0–5 行**。这是**有界信号子集**，**不是**全机趋势判决。

- 开关标签保持 **仅上涨**。覆盖由空态两行说清，不靠改开关名。
- 过滤空态锁定为两行：主句 **Top5 暂无上涨**；下一行次要字 **其他进程未做趋势判断**。不要写成「当前排序前 5 暂无持续上涨…」整句，也不要用「当前没有持续上涨的进程」这类全机空态句。
- 不为此做全表 ring、第二套增长算法、新 Sampler cadence。若以后产品要「全表仅上涨」，那是另一期，必须先重开九期 N=5。

### 建议工程顺序

信号已经在、徽标已经在、全表 series **没有、也不做**。不需要先开采样 PR。

合并后工程顺序（本文只锁设计；**本 docs PR 不写 Swift**）：

1. **纯过滤 / 投影 + 单测**：`rows` → 名称过滤 →（内存页且 ON）只留 `badge != nil`。钉：ON / OFF；`.rising` 留下；`.insufficient` / `.none` / 无 series 不进且不标成「非上涨」；ON 空表；选中行被滤掉则 `selectedPid` 被清、侧栏不可退出；OFF 恢复全表且名称过滤 / 排序不回退；只走 `evaluate`、无第二套算法。能 `swift test`，不编 App。
2. **工具栏开关 + 空态接线**：内存 Tab 右侧轻量「仅上涨」；ON 空态两行（主句「Top5 暂无上涨」，下一行次要字「其他进程未做趋势判断」）；OFF 走现成名称空态 / 全表。名称过滤、排序、点选、侧栏、CPU / 网络 / 磁盘、菜单栏回归覆盖。
3. **没有硬伤就不开 polish PR**。有硬伤：一个行为一个最小 fix，不要和 GPU / 全表 ring / 新周期捆在一起。

能保持零 Sampler 改动时不要先开采样 PR。不要把本刀和 GPU / 自动杀 / Helper 捆在一起。合并不擅自写代码。

## UI 绑定

结论：只改内存 Tab 的表投影与工具栏右侧一枚开关。徽标视觉锁在六 / 九期，本刀不重开设计。菜单栏不改。

### 工具栏（内存 Tab）

| 表面 | 锁定 | 说明 |
| --- | --- | --- |
| 位置 | 内存 Tab 工具栏**右侧** | 与现成 `AppFilterField` 同侧；不要占 principal Tab 条 |
| 控件 | 轻量开关，标签 **仅上涨** | Toggle / 等价轻控件。不是新列、不是新 Tab |
| ON | 表只留现有 `.rising` 行 | 谓词 = 现成列表徽标非 nil |
| OFF | 完整表（仍受名称过滤 + 表头排序） | 今日行为 |
| 其它 Tab | **不画这枚开关**；投影不生效 | 切到 CPU / 网络 / 磁盘不得被收成「上涨」 |
| 开关状态 | 可随内存页会话保留 | 切走再回来仍 ON 可以；禁止写进 Sampler / 磁盘偏好 |

### 进程表

现成 `List(sortedRows, selection: $vm.selectedPid)` 继续用。ON 时 `sortedRows` 是名称过滤 ∩ 现有 `.rising` 再排序。行仍可点选；徽标仍是九期同一枚「上涨」，不是第二套样式。

| 条件 | 表上的行 |
| --- | --- |
| OFF | 今日：`ProcessNameFilter` + `ProcessTableSort` |
| ON + `evaluate(topMemorySeries[pid]) == .rising` | **留下**（最多 5） |
| ON + `.insufficient`（窗口未满、刚进 Top 5、冷启动） | **不进表**。不是写成「非上涨」 |
| ON + `.none`（窗口够但净增 / 正步不够） | **不进表**。不是写成「非上涨」 |
| ON + pid 不在 `topMemorySeries`（含选中但不在 Top 5） | **不进表**。详情三态不受影响；若该 pid 原是选中 → **清选中** |
| ON + 名称过滤把 rising 行藏掉 | 结果空则走本刀空态；名称过滤本身不改 |
| CPU / 网络 / 磁盘 / GPU | 本开关不存在、不投影 |

切排序 / 名次 churn：跌出 Top 5 的 pid 九期已 drop series，本刀 ON 表同步少那一行，不得残留。新进 Top 5 在不足期间不得因「看起来在涨」混进 ON 表。

### 空态（内存表，采样 / 失败空态仍优先）

| 条件 | 文案 |
| --- | --- |
| 采样中 / 列表失败 / 无进程 | 现成句子，不改 |
| 开关 OFF + 名称无匹配 | **没有匹配的 App**（现成） |
| 开关 ON +（名称过滤 ∩ 现有 `.rising`）为空 | 两行：主句 **Top5 暂无上涨**；下一行次要字 **其他进程未做趋势判断** |
| 两侧栏无选中 | 现成「选择一个进程查看详情」 |

ON 空态主句用默认字重，次要字用次要色。不要复用「没有匹配的 App」，不要写成「当前排序前 5 暂无持续上涨…」整句，也不要写「当前没有持续上涨的进程」（全机误读），也不要在空态上写「泄漏 / 没有泄漏」。不强制加第二颗「关闭仅上涨」按钮；关掉开关就是恢复全表。

### 选中与侧栏

- 留下的行：点选、侧栏、Quit / Force Quit 与今日相同。
- 本开关把当前 `selectedPid` 滤掉（含「选中但不在 Top 5」）：**同一拍** `selectedPid = nil`，`detail` 清掉，侧栏回空态，**禁止**对已藏行 `terminate` / `forceTerminate`。
- 名称过滤把选中行藏掉：今日对照完整 `rows`、侧栏仍可退出——**本刀不改这条**（不回退）。
- 进程离开 `rows`：现成 `tick()` 清选中，不重开。
- 关掉开关：不自动恢复已被本开关清掉的选中。

### 文案默认（可改词不改义）

| 表面 | 锁定用词 | 说明 |
| --- | --- | --- |
| 开关 | **仅上涨** | 产品锁词；与徽标「上涨」同一词根 |
| 徽标本体（不改） | **上涨** | 六 / 九期原词 |
| Hover / accessibility（不改） | **近期内存持续上涨** | 六 / 九期原句 |
| 详情上涨（不改） | **近几分钟持续上涨** | 三期原句 |
| ON 空态 · 主句 | **Top5 暂无上涨** | 默认字重。有界子集，不是全机判决 |
| ON 空态 · 次要字 | **其他进程未做趋势判断** | 主句下一行，次要文字色。见上文覆盖决议 |

禁止出现：泄漏、泄露、leak、危险、告警、异常、中招、需要完全磁盘访问。验收对锁定字符串与实现字符串搜这些词。

### 明确不做（相对本刀）

- GPU Tab；进程级 GPU；新 Tab。
- 无界全表 series / ring；滚动视口「可见行」扫描；把 N 从 5 放开。
- 新徽标样式；第二套斜率；rss 两点差。
- **新 Sampler 采样周期 / cadence**（前台 1.5s、后台 2–3s 不动）。
- 任何菜单栏改动（栏上 A、弹出条 B、Top3 点选）。
- Helper / XPC / 登录项；新 entitlements / TCC 全盘。
- 恐吓文案、「泄漏」、假权限墙、自动杀。
- Electron / App Store 沙盒。
- 给不足 / 无 series 画「非上涨」或「—」。
- 用「当前没有持续上涨的进程」或「当前排序前 5 暂无持续上涨…」整句当空态。
- 用详情 `selectedMemorySeries` 当第二路全表过滤源。
- 名称过滤藏行时顺手改掉今日「侧栏仍可退出」行为。

## 风险

| 风险 | 应对 |
| --- | --- |
| 忍不住做成无界全表 ring / 新周期，好让空态「全机为真」 | 覆盖决议写死：有界子集，最多 0–5 行；空态两行自己说明其他进程未判断；范围表写死零 Sampler |
| 把无 series / `.insufficient` 标成「非上涨」 | 谓词只认 `evaluate == .rising`；不足与缺失都是「无可用标记」 |
| 第二套算法（两点 rss 差） | 只允许 `MemoryGrowthSignal.evaluate`；单测钉无第二套、阈值不改 |
| 选中行被滤掉后侧栏仍可退出 | ON 滤掉 `selectedPid` 必须清选中；单测钉 `quitSelected` 无目标 |
| 用详情 ring 给 Top 5 外的选中行开后门 | 过滤只吃 `topMemorySeries` / `MemoryGrowthList.badge` |
| 名称过滤 / 排序 / 其它 Tab 回退 | 上涨投影按页门控；名称过滤语义不改；回归覆盖 |
| Top 5 集合被开关改写 | 与九期相同：Top 5 吃内存页排序 + 完整 `rows`，不吃本开关 |
| 开关画到 CPU / 网络 / 磁盘或改菜单栏 | UI 绑定写死：仅内存 Tab；菜单栏本刀不碰 |
| 空态复用「没有匹配的 App」或写成全机一句 | ON 空态锁两行：主句「Top5 暂无上涨」+ 次要字「其他进程未做趋势判断」 |
| 恐吓红 / 「泄漏」 | 次要色；验收搜禁词 |
| Helper / 新 entitlement / GPU / 新 Tab | 范围表写死不加 |

## 验收（十二期首包）

产品 Must：

- [ ] 内存 Tab 工具栏右侧有轻量开关 **仅上涨**；其它 Tab 无此开关
- [ ] ON：内存进程表只留当前 `topMemorySeries` 上 `MemoryGrowthSignal == .rising` 的行（与九期「上涨」徽标同一谓词）；行可点选，侧栏现成「退出 / 强制退出」可用
- [ ] OFF：完整表（仍走名称过滤 + 表头排序），与今日一致
- [ ] ON 且无此类行：空态两行，主句恰为 **Top5 暂无上涨**，下一行次要字恰为 **其他进程未做趋势判断**。不得写「当前没有持续上涨的进程」，也不得写成「当前排序前 5 暂无持续上涨…」整句
- [ ] `.insufficient` / `.none` / 无 series：**不进** ON 表，也不标成「非上涨」；角标位不写「—」
- [ ] 选中行被本开关滤掉（含选中但不在 Top 5）：`selectedPid` 已清，侧栏空态，不可对已藏行退出 / 强退
- [ ] 名称过滤、表头排序、点选、侧栏退出、九期最多 5 枚「上涨」徽标不回退
- [ ] 算法仍是三期 `MemoryGrowthSignal.evaluate`；无第二套增长数学、无 rss 两点差、无新徽标样式
- [ ] 无新 Sampler 周期 / 字段 / 第二路 Mach；N=5 硬封顶不放开
- [ ] 永不写「泄漏」/ leak / 「危险」；无自动杀；无假权限墙
- [ ] 菜单栏 A / B / Top3 点选不因本刀改动

明确不做（本包出现即不合格）：

- [ ] 无 GPU Tab、无进程级 GPU、无新 Tab
- [ ] 无无界全表 series / ring；无新 Sampler cadence
- [ ] 无新徽标样式、无第二套算法
- [ ] 无菜单栏改动
- [ ] 无 Helper / XPC / 登录项、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 无恐吓文案、无「泄漏」、无自动杀
- [ ] 无把不足 / 无信号误标成非上涨

共性：

- [ ] 一二三四五六七八九十十一期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏 A / 七期 B / 十期已用内存 / 十一期 Top3 点选、详情增长软信号、九期 Top5∩rising 徽标、退出链路、名称过滤）
- [ ] 冷启动仍默认内存页
- [ ] UI / 单测：ON / OFF；`.rising` 留下；不足 / none / 无 series 不进；ON 空态两行（主句「Top5 暂无上涨」+ 次要字「其他进程未做趋势判断」）；选中被滤掉则清选中；无第二套算法；拷贝无「泄漏」
- [ ] 不改公证脚本与 entitlements

## 工期

小：约 **0.5–1 天**——按「纯过滤 / 投影 + 单测 → 开关 + 空态接线」拆，**不是**更大的采样功能，不要按 Sampler 改造估。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。本 docs 分支**不写 Swift**。
