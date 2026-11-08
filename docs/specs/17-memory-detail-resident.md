# Pulse 十七期技术设计（首包：内存详情驻留口径与采样依据）

> 归档：这是第 17 期落地前的设计稿，写完后不再修改。当前实现以 [TECH.md](../TECH.md) 为准，后续期数可能已经改动这里的范围或口径。
>
> 已被取代：本期把内存页详情定为「驻留内存」口径。二十八期 (#88) 改为「内存占用」，读不到才回退并标「按驻留内存」，上涨句改为「近期内存占用上涨」。见 [ADR-0001](../adr/0001-process-memory-footprint.md) 与 TECH「内存口径」。

> 一期至十六期正文不改写。三期至十二期正文里详情上涨句仍写着「近几分钟持续上涨」——那是当时的锁。**详情侧栏这一句的现行口径以本节为准**，旧节不回改。十六期 `ProcessQuitOutcome` / `ProcessQuitSession` / `ProcessActions` 与 VM 退出行为不重开。

**已锁定**：不造新趋势状态。内存 Tab 里**当前选中进程的详情**把内存字段标题和主曲线标题改成「驻留内存」；有物理内存总量时，占比句精确为「占物理内存的 X%（按驻留内存计算）」。无总量时占比标签仍是「占物理内存」，同处附近用静态帮助说明这是驻留内存、且不显示占比。详情里的上涨软信号改成「近期驻留内存上涨」，旁边静态说明「当前进程近期趋势 · 基于现有驻留采样序列」。样本不足仍是「样本不足，暂不判断」。没有上涨槽时不解释「稳定 / 正常」。原详情增加一个默认收起的 `DisclosureGroup`，summary「采样窗口与判断依据」，展开文案见下，且是纯视图状态。数值、`pti_resident_size`、现有 `ByteFormat.share`、CPU 那一格都不改。80 / 90 / 8 MiB / 60%、选中 pid 独立 ring、Top5 共 ring、增长判定都不改。

来源：十七期主控已锁文案与范围；对照现实现（仓库里**没有** `MemoryDetailView`。详情是各 Tab 共用的一个 `ProcessDetailSidebar`。列表行 `growthBadge` **不是** `memoryGrowthSlot`）。

本 PR 只追加本节并在 README 加索引。不写 Swift、不合并。

## 范围（相对一二三四五六七八九十十一十二十三十四十五十六期）

| 项 | 既有 | 十七期首包 |
| --- | --- | --- |
| 内存字段 / 主曲线标题 | 侧栏两处写死「内存」，各 Tab 共用 | **只**内存 Tab 的选中详情改成「驻留内存」。其它 Tab、总览、列表列头、菜单栏仍是「内存」 |
| 占比 | `memoryCaption`：有总量则「占 {GB} 的 {share}」，否则「占物理内存」 | 内存 Tab 有总量：精确句「占物理内存的 X%（按驻留内存计算）」，X% 仍是现成 `ByteFormat.share`。无总量：标签不变，附近静态帮助 |
| 详情上涨句 | `MemoryGrowthCopy.rising` = 「近几分钟持续上涨」 | **改成**「近期驻留内存上涨」+ 旁侧说明。不足句不动。`.none` 仍不占位 |
| 列表角标 | `MemoryGrowthListCopy`「上涨」/「近期内存持续上涨」，Top5 ∩ `.rising` | **不改**文案、不改门控、不改 ring |
| 采样窗口说明 | 无 | 内存 Tab **实时**详情一个默认收起的 `DisclosureGroup`。`@State`，不写 VM |
| 判定 / ring | `evaluate`：`count >= 80`，净增 **>** 8 MiB，相邻点 `value` 的 3/5；ring 上限 90 | **原样**。不新开、不重启采样，不改算法，不改独立 ring / Top5 共 ring |
| 冻结缺席 | 十六期整卡 + 「已不在列表／上次记录」；`showsLiveTrend == false` 时 `memoryGrowthSlot` 为 nil | **保持**。不追点、不在冻结卡上画实时上涨槽、不拿 `frozenDetail` 重算趋势 |
| 退出 | 十六期 per-pid 记录与原处重试 | **不改** `ProcessQuitOutcome` / `ProcessQuitSession` 的存贮与投影规则、不改 `ProcessActions`、不改 VM 退出函数 |
| CPU / 网络 / 磁盘读数与总量、其它 Tab、菜单栏 | 既有 | **不改** |
| 列表 Top5 / 仅上涨 / 过滤空态 / 内存曲线占位 | 既有 | **不改** |
| 新 Darwin 指标 / footprint / 「真实占用」/ 泄漏判定 / 历史库 / 身份采样 / 新 Tab | 禁止 | **仍禁止** |

一二至十六期验收与公证路径不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。本 PR 不写 Swift、不合并。开发不等待其它锁：无总量帮助句已在本节写死，不再退回产品。

## 架构（现实现，读仓库后的结论）

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

本刀是**文案与纯展示**。不新开趋势状态、不新 Timer、不新增 generation、不把展开状态写进 VM。

### 没有 MemoryDetailView；侧栏是一份，标题不是和列表共用的

`MemoryDashboardView` 的 `HSplitView` 右侧始终是**同一个** `ProcessDetailSidebar()`。内存 / CPU / 网络 / 磁盘都走它。仓库里没有 `MemoryDetailView` 这个类型。

这份侧栏里和「内存」有关的可见字是**两处独立字面量**，不是一个共享标题 token，也不是列表行的标题：

| 表面 | 现字面量 | 谁在用 | 十七期 |
| --- | --- | --- | --- |
| `metrics` 里 `SidebarMetric.title` | 「内存」 | 只要 `sidebar.detail` 非空就画，**不看页** | 内存 Tab 改为「驻留内存」；其它页保持「内存」 |
| `memoryChart` → `seriesBlock` 的 title | 「内存」 | 同上，主曲线 | 与字段标题用**同一个**页门控，改为「驻留内存」 |
| `cpuChart` 的 title | 「CPU」 | 同一 `seriesBlock` 的另一处调用 | 不动 |
| `ProcessColumnTitle.memory`、总览 `Label("内存")`、`OverviewCards` 的「内存」、`ResourceTab.memory` | 「内存」 | 列表列头 / 总览 / Tab | 不动 |
| `ProcessLine` 的内存格子 | `ByteFormat.memory(row.memoryBytes)`，无标题改名 | 各 Tab 列表行 | 不动。accessibility 里的「内存 …」也不改 |

CPU 与内存仍是 `metrics` 里那一对 `SidebarMetric`。只改内存这一格在内存 Tab 上的 title / caption。CPU 的值、`ByteFormat.cpu`、两帧 CPU 差值都不动。

**页门控复用现成参数，不复用「槽位是否非空」。** `MemoryGrowthSidebar.slot` 与 `MemoryGrowthList.badge` 已经用 `page == .memory`（视图侧就是 `vm.selectedPage`）。字段标题和主曲线标题用**这一条**：

```text
selectedPage == .memory ? "驻留内存" : "内存"
```

不要用 `memoryGrowthSlot != nil` 当标题开关。槽位在 `.none`、非内存页、以及冻结卡上都会是 nil，但内存 Tab 的字段和主曲线标题在「没有上涨槽」时仍然要显示「驻留内存」。

占位句「正在采集内存曲线」不是标题。`seriesBlock` 在 `samples.count < 2` 时仍画这个占位，`count >= 2` 仍画现成 `SparklineChart`。本期不改这个分支：0 点或 1 点是空曲线，2 点起是已有点。采样从第一个样本就往 ring 里 append，不等收满 90，也不为了这句话把折线改成 1 点就画。

### 占比：现成 fallback 已经避开 0% / 100%

`ProcessDetailSidebar.memoryCaption` 今日是：

```text
guard let total = vm.snapshot?.totalBytes, total > 0 else { return "占物理内存" }
return "占 \(ByteFormat.gibWhole(total)) 的 \(ByteFormat.share(part: row.memoryBytes, total: total))"
```

已核对：

- `snapshot == nil`，或 `totalBytes == 0`：直接返回「占物理内存」。**不会**调用 `share`。
- `ByteFormat.share` 在 `total == 0` 时返回 `"0%"`。`ByteFormat.wholePercent(part:total:)` 同样返回 `"0%"`。内存占比**不得**走这两条来填缺失总量。
- `HostMemoryReader.read` 在 `physicalMemory == 0` 时抛 `HostMemoryError.physicalMemoryUnknown`，成功快照的 `totalBytes` 因此大于 0。UI 守卫仍然要留着，因为第一帧成功之前 `snapshot` 可以是 nil。失败采样的 `applySample` **不**清 `snapshot`（只标 `samplingFailed`），所以失败后沿用上一份总量，而不是改成 0。
- 分母是物理内存总量 `totalBytes`，不是已用内存。不要换成 used，也不要在总量缺失时写成 0% 或 100%。

`row.memoryBytes` 来自 `ProcessEnumerator` 的 `pti_resident_size`。本期不改这个字段，不引入 footprint 或其它 Darwin 计数。`ByteFormat.memory` 与 `ByteFormat.share` 的格式化规则不改（含 `<0.1%`、一位小数、整数百分比）。X% 就是 `share` 已经带上百分号的那串字，整句是插值，不是第二套百分比。

内存 Tab 的四条展示（纯函数即可，便于 Linux 测；不要放进 VM 存贮）：

| `selectedPage` | 总量 | 标签 / 标题 | 占比 caption | 附近帮助 |
| --- | --- | --- | --- | --- |
| `.memory` | `total > 0` | 「驻留内存」（字段 + 主曲线） | `占物理内存的 \(share)（按驻留内存计算）` | 无额外帮助。句内已经写明口径 |
| `.memory` | nil 或 0 | 「驻留内存」 | 仍是「占物理内存」 | 静态「此数值为驻留内存。当前没有物理内存总量，不显示占比。」 |
| 其它页 | `total > 0` | 「内存」 | 今日「占 {GB} 的 {share}」 | 无 |
| 其它页 | nil 或 0 | 「内存」 | 今日「占物理内存」 | 无 |

帮助是静态常量，不从 `frozenDetail` 读，也不从序列算。放在占比 caption 旁边（同一格内的次级文字，或该 caption 的 `.help`）。沿用 `SidebarMetric` 现有间距与次级色，不加新颜色、不加大卡片。真实 0 字节且总量存在时，`share` 今日会格式出「0.0%」一类结果，句成「占物理内存的 0.0%（按驻留内存计算）」——这是部分为 0，不是缺失总量，保持 `share` 原样。

禁止在这些句子里写：独占、可释放、活动监视器、真实占用、footprint、泄漏、异常。不暗示与活动监视器相等。

冻结卡如果带着 `frozenDetail`，今日会进 `detailBody`，因此会走到同一套字段标题和 caption。那是同一份驻留字节的**静态标签**，分母仍是现有 `snapshot.totalBytes`（今日已经这样算，不是本期新公式）。冻结卡**不能**因此出现实时上涨槽。见下节。

### 列表 growthBadge 不来自 memoryGrowthSlot

假设「`growthBadge` 由 `memoryGrowthSlot` 来」与源码不符。两条投影分开，本期只改详情那条的文案。

**详情槽（本期改文案，不改算法）：**

`MemoryDashboardVM.memoryGrowthSlot`：

1. `guard sidebar.showsLiveTrend else { return nil }`
2. 再调用 `MemoryGrowthSidebar.slot(page: selectedPage, selectedPid:, detailSeries: sidebar.detail?.memorySeries)`

`MemoryGrowthSidebar.slot` 再要求 `page == .memory` 且 `selectedPid != nil`，然后 `MemoryGrowthSignal.evaluate(detailSeries ?? [])`。`.rising` / `.insufficient` 才有槽；`.none` 返回 nil，视图不画。输入是**侧栏这份** `memorySeries`，不是 `topMemorySeries`。

视图只有 `if let slot = vm.memoryGrowthSlot { memoryTrend(slot) }`。`memoryTrend` 是标题「内存趋势」+ caption，不是列表那种胶囊。本期保持这个文字栈和现有字号 / 次级色，不把详情槽改成新胶囊，也不新做颜色。

**列表角标（本期不改）：**

`ProcessTablePane` 把 `growthBadge: vm.memoryGrowthListBadge(for: row.pid)` 传给 `ProcessLine`。VM 方法调用 `MemoryGrowthList.badge(page: selectedPage, rowPid:, seriesByPid: topMemorySeries)`。只在内存页、且该 pid 落在 Top5 图里、且 `evaluate == .rising` 时非空。选中不是门控。不足和 `.none` 都是 nil，列表不写「样本不足」。主屏每行重算就是视图读当前 `topMemorySeries`；ring 来自 `MemorySampler` 的 `MemoryGrowthTopStore`（`SampledFrame.topMemorySeries`）。不要把这条改去读 `memoryGrowthSlot`，也不要让详情说明去改 `MemoryGrowthListCopy`。

详情上涨句替换后，`MemoryGrowthListCopy.title`（「上涨」）必须仍然不等于详情 rising 句。现有 `MemoryGrowthListBadgeTests` 的这条不等式保持成立。

### 上涨文案怎么挂（借读 evaluate，不改它）

`MemoryGrowthCopy`：

| 信号 | 现 caption | 十七期 |
| --- | --- | --- |
| `.rising` | 「近几分钟持续上涨」 | caption「近期驻留内存上涨」。另给旁侧说明「当前进程近期趋势 · 基于现有驻留采样序列」 |
| `.insufficient` | 「样本不足，暂不判断」 | **原句**。不附带旁侧说明，也不写成上涨 |
| `.none` | `caption` 为 nil，整槽不画 | **仍不画**。不解释「稳定」「正常」「无异常」 |

旁侧说明只在 `.rising` 出现。实现可以给 `MemoryGrowthSlot` 加一个默认 nil 的 `basis: String?`，由 `MemoryGrowthSidebar.slot` 在 `.rising` 时填上那句静态字。这是纯展示字段，不是新的趋势状态。VM 的 `memoryGrowthSlot` 仍只是返回这个槽；冻结时在调用 `slot` 之前就 return nil，不会去填 basis。标题「内存趋势」保持。禁止「分钟」「每点都在涨」这类说法。

`evaluate` 本体一行不改。现实现已是产品那句的算法，对照如下（写进 Disclosure 的是产品句，不是把算法改写成另一套）：

| 产品句 | 源码 | 边界（现测试已钉，勿改期望） |
| --- | --- | --- |
| 最多 90 点 | `ChartSampleRing.limit = 90`。`evaluate` 用**整段**传入数组，不另切最后 80 点 | 不要为了「窗口」再切片，否则判定变了 |
| 曲线从有样本开始，无需收满 | `detailFrame` / Top store 从第一笔 `memoryBytes` append。图表 `count < 2` 才占位 | 不改占位门槛 |
| 至少 80 点才判断上涨 | `samples.count >= minSamples`，`minSamples = 80`。少于 80 一律 `.insufficient` | **是 `>=`，不是 `>`**。`count == 80` 会进入净增和比例。`testSteadyClimbAcrossTheFullWindowIsRising` 用正好 80 点且期望 `.rising`。`count == 79` 即使每步都大涨也是 `.insufficient`（`testShortSeriesStaysInsufficientEvenWhenEveryStepClimbs`） |
| 首尾净增超过 8 MiB | `last - first > deltaThreshold`，`deltaThreshold = 8 * 1024 * 1024`。相等是 `.none` | `testNetIncreaseMustBeStrictlyAboveTheThreshold` |
| 至少 60% 的相邻采样间隔上涨 | 相邻**样本点**：`samples[i].value > samples[i - 1].value`。步数是 `count - 1`，不是两点的墙钟间隔。相等不算涨。比例是整数 `positiveSteps * 5 >= stepCount * 3`（`riseFloor = 0.6`） | 文案必须保留「相邻采样间隔」。不要改成「两点时间间隔」或按 `date` 相减。80 个点有 79 步：48 步上涨过线，47 步不过（现 `testRiseFloorBoundaryIsExact` 用的是 80 **步** / 81 点，后半是持平 `down == 0`，不是下降） |
| 中间可以有下降 | 下降步只是不算 positive。净增与 3/5 都过就可以 `.rising` | 现成 `testDipThenRecoverUsesFirstAndLastNotTheRange` 有下降，但净增只有 4 MiB，期望 `.none`。它**没有**覆盖「含下降仍上涨」。刀①可以**加**一条仍调用现有 `evaluate` 的序列；不得改阈值，也不得改掉上面已有期望 |

`> 80` 且无上涨槽，指的是窗口已经不少于 80、但净增或比例不够，结果 `.none`、槽为 nil。例如现成 90 点持平（`testFullFlatWindowIsNone`）。不是「超过 80 点就永远没有槽」。90 点若净增与比例都过，仍然 `.rising`。

### 切页、切 pid、两条 ring（行为保持）

**切 Tab。** `selectPage` 只改 `navigation` 并按页发布内存排序。它**不**调用 `sampler.setSelectedPid`，**不**清 `selectedMemorySeries`。侧栏进程还在。非内存页上 `MemoryGrowthSidebar.slot` 因 `page != .memory` 返回 nil，上涨槽消失；曲线数据还在。本期标题随 `selectedPage` 在「驻留内存」和「内存」之间切换，不因此重置 ring。

**切 `selectedPid`。** VM 的 `didSet` 把 `detail = nil`，再 `sampler.setSelectedPid`。Sampler 仅当 pid 真正变化时清空 `selectedMemorySeries` 与 `selectedCPUSeries`。`topMemoryStore` **不**在这里清空。下一帧成功 `detailFrame`：

- 新 pid 属于当前内存页 Top5，且 store 里已有序列：`selectedMemorySeries =` 那条已有序列（接上，不是把 Top5 整表重载或清掉）。
- 否则：在刚清空的选中序列上 append **一个**当前 `memoryBytes`。这是选中 pid 的独立 ring。

Top5 进入时另有 `adopt`：选中序列非空且 pid 在 Top5 里，会把选中序列抄进 store，避免截断。本期不改 `adopt`、`advance`、`setSelectedPid`、`seriesLimit`。禁止为了详情文案去全量加载历史或重置已有 ring。

选中 pid 在 Top5 内时，详情 `memorySeries` 与列表角标用的是同一条 store 序列（抄入 / 接上）。选中 pid 不在 Top5 时，详情用独立 ring，列表角标因 map 里没有该 pid 而为 nil。两条都保持。

**失败帧 / 少样本。** `applySample` 在采样失败时不替换 `rows` / `detail` / `topMemorySeries`。未接受的 flight（freshness 不足）只把 presence 观察标成 `freshnessInsufficient`，不改曲线。十六期已锁：这种帧不改 presence、不清失败。本期同样不得清历史曲线，不得把信号推成 `.none` 或「稳定」。

### 冻结卡不会因为退出闪出实时上涨槽

`ProcessQuitSession.sidebar` 里：

```text
frozen = projected.showsAbsentRecord
showsLiveTrend = !frozen && detail != nil && listSelectedPid == subject && legalSubject != nil
```

缺席时 `displayedDetail` 返回 `frozenDetail`（离开 `rows` 那一拍的整份 `ProcessDetail`），不再 append。`showsAbsentRecord` 为真时 `showsLiveTrend` 为假。`memoryGrowthSlot` 的第一行守卫因此直接 nil——**即使冻结曲线本身 `evaluate` 会得到 `.rising`，也不会画实时槽**。这就是挡住 offRows 冻结卡上实时上涨槽的展示条件。视图没有第二条路径去读 `growthBadge` 或再 `evaluate(frozenDetail.memorySeries)`。

同一拍里投影一起算完，没有单独的「退出事件」再发一个上涨槽。进程还在 `rows` 里、只是退出中：`showsLiveTrend` 仍可为真，槽继续反映**当时的实时序列**（原行为）。一旦成功进程帧确认缺席，槽关掉。

列表行只画仍在表里的 pid。人离开 `rows` 后没有行，角标无处闪。同 pid 无身份证据再现：十六期已是新进程、Sampler 新 ring 从空开始；`evaluate` 在满 80 点之前是 `.insufficient`（详情不足句），不是上涨槽。列表角标更要 `.rising` 才出现。退出本身不新造上涨槽。

本期禁止：

- 去掉或放宽 `showsLiveTrend` 守卫。
- 在冻结卡上用 `frozenDetail.memorySeries` 再跑 `evaluate` 来填上涨句或 basis。
- 把静态帮助或 Disclosure 接到「当前正在上涨」上。帮助与 Disclosure 是常量；实时上涨槽只走 `memoryGrowthSlot`。

`detail == nil` 且 `showsAbsentRecord` 时走 `absentRecordBody`（关闭按钮 + 页脚），没有指标和曲线。有 `frozenDetail` 时仍走 `detailBody`，页脚 `absentLabel` 仍是「已不在列表／上次记录」。按钮、失败句、「正在退出…」的十六期规则不动。

### DisclosureGroup（纯视图状态）

只在内存 Tab 且 `sidebar.showsLiveTrend` 的 `detailBody` 里放**一个**系统默认 `DisclosureGroup`。放在上涨槽（有则显示，无则跳过）和主曲线之间。`detailBody` 现有 `VStack(spacing: 14)` 继续用。默认收起。

- summary：`采样窗口与判断依据`
- 展开正文，逐字：

`使用当前选中进程已有的采样序列，最多90点；曲线从有样本开始，无需收满。至少80点才判断上涨：首尾净增超过8 MiB，且至少60%的相邻采样间隔上涨；中间可以有下降。仅表示近期窗口，不判断异常或泄漏。`

展开用侧栏视图自己的 `@State`（默认 false）。不写入 `MemoryDashboardVM`，不新增 `@Published` 趋势字段，不新增 Timer，不新增 generation。正文是常量，展开时不调用 `evaluate`。切换 pid 后这段字不变，所以不必为了换 pid 去改 VM；视图状态留在视图里即可。

冻结卡 `showsLiveTrend == false`，不放这个 Disclosure。避免把「判断上涨」的说明嵌进冻结卡，让人当成正在重算。无总量时的驻留帮助是另一句静态字，可以出现在内存 Tab 的字段 caption 上（包括仍走 `detailBody` 的冻结详情），因为它只描述字节口径，不描述趋势。两句不要拼成一个控件。

非内存页不放 Disclosure。空侧栏不放。

## 建议工程顺序（两刀，可合成一刀）

两刀都等本设计合并 + Grok merge gate 之后。本 PR 不写 Swift、不合并。没有第三刀。不与十六期退出、十五期双清、菜单栏、Sampler 捆在一起。

推荐拆开，因为刀①在 Linux 上能测完，刀②是 SwiftUI 接线、本环境没有 Mac GUI。合成一刀也可以：改动面就是文案纯函数 + `ProcessDetailSidebar`，没有第二套状态。不要为了拆而拆出算法 PR。

1. **文案 + 纯展示（Linux `swift test`）**  
   放在 SamplingCore 已收录的模型里（可继续写在 `MemoryGrowthSignal.swift` 的文案枚举上，或另加一个 Darwin-free 文案文件并列入 `Package.swift` 的 `sources`）。  
   - `MemoryGrowthCopy.rising` 改为「近期驻留内存上涨」。新增 basis 常量，以及「只对 `.rising` 非空」的纯函数。`insufficient` 与 `.none` 的 caption 规则不变。`evaluate` 函数体不改。  
   - 内存详情标题 / 占比四行表做成纯函数：输入页、`part`、`total?`，输出标题、caption、可选帮助。`total == nil || total == 0` 时不调用 `share` / `wholePercent`。其它页保持今日句子。  
   - Disclosure 的 summary 与正文常量。  
   - 单测见下。列表 `MemoryGrowthListCopy` 的字面量断言保持原句。`MemoryGrowthSidebarTests.testLockedCopy` 里把 rising 字面量从「近几分钟持续上涨」改成本节新句；凡是整槽相等、并且 `.rising` 现在带 basis 的断言一起改期望。不要改 `MemoryGrowthSignalTests` 里 `.rising` / `.insufficient` / `.none` 的既有期望。含下降仍上涨的新用例只追加。

2. **侧栏接线（Mac 才是界面；Linux 至多源码结构）**  
   只动 `ProcessDetailSidebar`（`SidebarMetric` 若要多一个可选帮助参数，仍在这个文件里）。  
   - 字段标题与 `memoryChart` 标题走刀①的页函数。`cpuChart`、占位句、`memorySummary` 不动。  
   - `memoryCaption` 改为刀①的占比函数，总量用现有 `vm.snapshot?.totalBytes`。  
   - `memoryTrend` 在 caption 下显示 `slot.basis`（仅非空）。  
   - Disclosure 的 `@State` 与 `showsLiveTrend && selectedPage == .memory` 门控。  
   - **不**改 `memoryGrowthSlot` 的 `showsLiveTrend` 守卫，**不**改 `MemoryDashboardVM` 的退出 / `selectedPid` / `applySample`，**不**改 Sampler、`ProcessQuitOutcome`、`ProcessQuitSession`、`ProcessActions`、列表、总览、菜单栏。

源码结构检查若要写，沿用现有 `ProcessQuitSessionWiringSourceTests` 那种读文件断言：侧栏标题门控看 `selectedPage`，Disclosure 是 `@State`，`memoryGrowthSlot` 仍先看 `showsLiveTrend`。这种检查**不是** SwiftUI 行为测试，**不是**截图或 snapshot 测试。本仓库今天没有内存详情的 snapshot / 分享测试，本期也不要写成已经有。

## 测试矩阵

**刀① Linux（必须实跑的是纯模型 / 文案；本文档 PR 没有跑它们）：**

1. 内存页 + `total > 0`：字段标题与主曲线标题都是「驻留内存」；caption 等于 `占物理内存的 \(ByteFormat.share(...))（按驻留内存计算）`。抽一档 `<0.1%`、一档一位小数、一档整数百分比，确认 X% 就是 `share` 原串。
2. 内存页 + `total == nil` 与 `total == 0`：caption 仍是「占物理内存」；帮助是本节那句；结果字符串里没有 `0%` 也没有 `100%`。断言实现没有为了这两支去调用会返回 `"0%"` 的格式化（用输出断言即可）。
3. 非内存页：标题「内存」；有总量仍是「占 {GB} 的 {share}」；无总量仍是「占物理内存」且帮助为空。
4. `.rising`：caption「近期驻留内存上涨」，basis 为「当前进程近期趋势 · 基于现有驻留采样序列」。两句都不含「分钟」。`.insufficient`：caption 仍是「样本不足，暂不判断」，basis 为空。`.none`：槽为 nil（没有 basis 单独出现）。
5. 空曲线 / 有点不是新算法。若纯函数不包含 `count < 2`，就不要假造一个图表测试。图表分支留在刀②的源码约束：`samples.count < 2` 仍是占位。
6. `count == 79` → `.insufficient`（既有）。`count == 80` 且爬升过两道线 → `.rising`（既有，证明不是 `> 80`）。`count == 80` 且净增等于 8 MiB → `.none`（既有）。90 点持平 → `.none`、无上涨槽（既有）。新加：一段含真实下降步、净增仍 `> 8 MiB`、上涨步仍过 3/5 的序列 → `.rising`。新加不得修改 `evaluate`。
7. 列表文案仍是「上涨」与「近期内存持续上涨」。内存页 Top5 `.rising` 仍有角标；不足 / `.none` / 非内存页仍为 nil（既有列表测试保持）。
8. 新文案搜不到：泄漏、泄露、leak、危险、异常、独占、可释放、活动监视器、真实占用、footprint、分钟。Disclosure 正文按上面逐字相等（正文里的「不判断异常或泄漏」是产品句，允许出现「异常」「泄漏」这两个词，因为句子是否定判断；其它新句子仍然不许）。
9. `showsLiveTrend == false` 时，调用方契约是不调用 `slot`。纯函数测的是 `slot` 本身不知道冻结。冻结守卫放在刀②源码约束，不在这里假装测了 VM。

**刀②：**

10. 源码：`memoryChart` 与内存 `SidebarMetric` 的标题都来自页门控；`memoryGrowthSlot` 仍含 `sidebar.showsLiveTrend` 与 `MemoryGrowthSidebar.slot`；Disclosure 使用 `@State`；侧栏源码不出现对 `quitOutcome` 的写入，也不出现 `evaluate(frozen`。  
11. 明确写出：上述源码断言 **不是** SwiftUI GUI，**不是**已在 Mac 上点选验证。

本环境没有 Mac，也没有被授权跑 GUI。不要把刀①的 `swift test` 写成「侧栏已验」或「快照已验」。

## 风险

| 风险 | 应对 |
| --- | --- |
| 用 `memoryGrowthSlot != nil` 控制「驻留内存」标题，`.none` 时标题掉回「内存」 | 标题只看 `selectedPage` |
| 把列表 `growthBadge` 和详情槽收成一条，Top5 文案被改成「近期驻留内存上涨」 | 范围表：列表 copy 与 `topMemorySeries` 不动 |
| 把 `>= 80` 写成 `> 80`，正好 80 点不再上涨 | 既有 80 点 `.rising` 测试不许改期望 |
| 把「相邻采样间隔」实现成 `date` 相减 | 文案与 `value` 相邻比较写在同一节；`evaluate` 不改 |
| 无总量时调用 `share` / `wholePercent` 得到 `0%` | 四行表 + 输出不得含伪造的 `0%` / `100%` |
| 冻结曲线仍 `.rising`，退出后槽闪一下或留在卡上 | 保持 `showsLiveTrend` 先决；禁止对 `frozenDetail` 再 `evaluate` |
| Disclosure 的 `@State` 写进 VM，或展开时重跑判定 | 纯视图状态；正文常量 |
| 帮助句被读成「等于活动监视器 / 可释放」 | 帮助句只陈述驻留与「不显示占比」 |
| 源码字符串测试被写成 GUI 已通过 | 测试矩阵第 11 条 |

## 验收（十七期首包）

产品 Must：

- [ ] Must1：仅内存 Tab 选中详情的内存字段标题与主曲线标题为「驻留内存」。有总量时占比精确为「占物理内存的 X%（按驻留内存计算）」，X% 为现成 `ByteFormat.share`。无总量时标签仍为「占物理内存」，附近帮助为「此数值为驻留内存。当前没有物理内存总量，不显示占比。」`snapshot == nil` 与 `totalBytes == 0` 都不显示 `0%` 或 `100%`。其它 Tab、列表列头、总览、菜单栏标题不改。`memoryBytes` 仍是 `pti_resident_size`。CPU 格不动
- [ ] Must2：实时详情 `.rising` 为「近期驻留内存上涨」，旁侧「当前进程近期趋势 · 基于现有驻留采样序列」。两句无固定分钟、无「每点都在涨」。`.insufficient` 仍为「样本不足，暂不判断」，且无旁侧说明。`.none` 不占位，也不解释稳定 / 正常。列表角标文案不改。不新开、不重启采样，不改 `evaluate`
- [ ] Must3：内存 Tab 实时详情有一个默认收起的默认样式 `DisclosureGroup`，summary「采样窗口与判断依据」，展开文案与本节逐字相同。80 是 `count >= 80`；相邻比较是相邻样本的 `value`，不是时间间隔。`count == 80` 仍可 `.rising`；`count == 79` 为不足；多于 80 点但条件不够则为 `.none`、无上涨槽；中间下降仍可 `.rising`（新测试只追加）。90 点上限、8 MiB 严格大于、3/5、选中 pid 独立 ring、Top5 共 ring 保持。切 pid 接上已有 Top5 序列，不整表重载、不清 `topMemoryStore`
- [ ] Must4：实时详情的数值、占比计算、曲线点数规则不改（只改内存 Tab 上的指定文案）。offRows 仍是原缺席冻结卡与「已不在列表／上次记录」。无追点、无实时上涨槽、不对冻结序列重跑判定。失败采样与 freshness 不足不清历史、不推成 `.none`。静态帮助可以说明驻留；不得把冻结卡画成实时上涨。退出存贮与 `ProcessActions` 不改。Disclosure 不进入冻结卡
- [ ] Must5：刀①覆盖详情文案四支、空总量、`.rising` / 不足 / `.none`、`== 80` / `== 79` / 长窗口无槽 / 含下降仍上涨。切 pid 接 ring 与冻结无实时槽以源码约束说明，并写明不是 SwiftUI GUI。无 Mac 验收不挡本文档。无 snapshot 测试宣称

明确不做（本包出现即不合格）：

- [ ] 无 CPU / 网络 / 磁盘读数或总量改动，无其它 Tab / 菜单栏文案改动
- [ ] 无列表 Top5、仅上涨、过滤空态、列头「内存」、图表 `count < 2` 占位的行为改动
- [ ] 无新 Darwin 指标、footprint、「真实占用」、泄漏 / 异常判定、可释放、历史库、身份采样、新 Tab
- [ ] 无 `ProcessQuitOutcome` / `ProcessQuitSession` 规则改动，无 `ProcessActions` 改动，无 VM 退出行为改动
- [ ] 无新趋势 `@Published`、无 Timer、无 generation、无第二套 `evaluate`
- [ ] 无「源码匹配 = 已验 SwiftUI」或「已有 snapshot / 分享测试」

共性：

- [ ] 一期至十六期验收不回退；十六期退出行为不回退
- [ ] 冷启动仍默认内存页
- [ ] Linux：`swift test` 跑刀①文案 / 既有 `MemoryGrowthSignal` 与列表角标
- [ ] 不改公证脚本与 entitlements

### Linux 可测 vs Mac 剩余

已核 `Package.swift`：SamplingCore 收录 `Models/MemoryGrowthSignal.swift`、`ByteFormat.swift`，**排除** `ViewModels/`、`Views/`、`Sampling/MemorySampler.swift`。因此：

- 文案、占比四支、`evaluate` 边界：Linux 可测。本文档 PR **尚未**跑这些测试，也不修改它们。
- `ProcessDetailSidebar` 的真实布局、Disclosure 点击、冻结卡外观、切 Tab 时标题切换：Mac 未验。不挡本设计审阅，也不是本 docs PR 的交付。
- 源码结构断言若在刀②出现：必须标明不是 GUI。

Mac 冒烟（**仅**设计与实现都合并之后；**不挡**本文档）：

- 内存 Tab 选中进程：字段与主曲线为「驻留内存」；有总量时为指定占比句；拔掉总量的展示支显示原标签和帮助，而不是 0% / 100%
- 满窗上涨：新上涨句与旁侧说明；不足仍是原句；持平没有槽，也没有「稳定」
- 展开「采样窗口与判断依据」为指定正文，收起为默认；换 pid 不写 VM
- 切到 CPU / 网络 / 磁盘：侧栏标题回到「内存」，无这段 Disclosure，无上涨槽；再切回内存，曲线还在
- 切到另一个已在 Top5 的 pid：曲线接上已有点，而不是从空重来；不在 Top5 的 pid 仍从自己的新 ring 长
- 退出后缺席：冻结卡与「已不在列表／上次记录」，没有实时上涨槽，没有 Disclosure

## 工期

小。刀①是文案纯函数和已有 `evaluate` 的追加用例。刀②是同一侧栏上的标题、caption、一行 basis 和默认 `DisclosureGroup`。没有硬伤就不要第三刀。本文只锁设计，不估日历人天。

## 依赖与未决

**产品行为与下列句子已锁，不再退回产品：** 字段与主曲线「驻留内存」；「占物理内存的 X%（按驻留内存计算）」；无总量仍用「占物理内存」；上涨「近期驻留内存上涨」；旁侧「当前进程近期趋势 · 基于现有驻留采样序列」；不足「样本不足，暂不判断」；Disclosure 的 summary 与展开正文。80 / 90 / 8 MiB / 60%、独立 ring、Top5 共 ring、不改退出，都已锁。

**无总量附近帮助的逐字稿，主控只要求「同处解释驻留口径、且不能伪造比例」。** 本节把它写成「此数值为驻留内存。当前没有物理内存总量，不显示占比。」这是呈现锁，好让工程开刀①，不是一条新的产品待决，也不改已经锁死的句子。

没有未决行为需要把十七期停成草稿。列表角标、其它 Tab 标题、图表占位、冻结卡结构都沿用现实现，不另开产品问题。

实现等本设计合并 + Grok merge gate 后再写 Swift。本 PR 不写 Swift、不合并。
