# Pulse 二十二期技术设计（首包：Top5 近期上涨趋势的同一份短说明）

> 归档：这是第 22 期落地前的设计稿，写完后不再修改。当前实现以 [TECH.md](../TECH.md) 为准，后续期数可能已经改动这里的范围或口径。
>
> 已被取代：帮助句里的「驻留内存序列」已在二十八期 (#88) 改为「内存占用序列」。

> 一期至二十一期正文不改写。本节只把内存页「仅上涨」开关的 tooltip 与列表徽标 `help` 收成同一个 `MemoryGrowthListCopy.help`。`title` 仍是「上涨」。开关标签仍是「仅上涨」。六期 / 九期的 help「近期内存持续上涨」由下面这句替换。

**已锁帮助句**（完整替换 `MemoryGrowthListCopy.help`，不得改字、拆句或另写第二句）：

> 完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期驻留内存序列判断趋势。

来源：产品 COMMENT [PRR 5798959320](https://github.com/qqzhangyanhua/pulse/pull/68#pullrequestreview-5798959320)。该评论是 scope / design + copy 的 final PASS，**只对应** head `b91c98b7d7ee6df93b16e5ff7315ecfe893adc3a`。它不覆盖本次文档修订后的新 head。新 head 要产品独立复核，并过主控 full gate。把该 PASS 复述成新 head 已审，或当成运行 PASS，都不成立。

**结论：** 生产文案只有这一处静态属性。`MemoryGrowthListBadge` 仍是 `title: String` 与 `help: String`。徽标工厂继续 `help: MemoryGrowthListCopy.help`。开关只在现有 `Toggle` 上追加 `.help(MemoryGrowthListCopy.help)`。行内 `.help(badge.help)` 和父行 `parts.append(growthBadge.help)` 继续读徽标字段。算法说明不是这句文案。Top5、表头、采样、排序、过滤、退出、二十一期曲线说明都不改。

代码事实对照 `f374478d465b21763e0cf08e9e9896ce0e6b9c4d`（`origin/main`，二十一期实现 #67）。本节开写前读过的是那份树上的源码。这不是实现授权，也不是 Mac 上的 tooltip / VoiceOver 终验。

产品对旧 head 的 scope / design + copy PASS 已经发生。实现仍须等本设计合并，以及用户后续明确的实现委托或主控 gate。本 PR 不改 `README.md`，不写 Swift，不改 `Package.swift` / `project.pbxproj`，不写测试，不跑 `swift test`，不合并，不开实现。下面的红绿步骤是实现 PR 的设计，不是本 PR 的执行结果。

## 已读源码（本 SHA）

行号是 `f374478d` 上的位置。实现以符号为准，行号漂移不构成第二份设计。

| 位置 | 今天的事实 |
| --- | --- |
| `MemoryGrowthTopSeries.pids(from:sort:)` | `Array(sort.ordered(rows).prefix(pidLimit).map(\.pid))`（`MemoryGrowthTopSeries.swift` 26–28 行）。`pidLimit` 是 5（23 行）。`seriesLimit` 等于 `ChartSampleRing.limit`，后者是 90（同文件 5、24 行）。入参是调用方传入的完整 `rows`，函数体内不读过滤结果 |
| `MemoryGrowthTopStore` | `seriesByPid`（33 行）。`retain(only:)` 立刻丢掉不在前 5 里的 pid（46–50 行）。`advance` 先 `prefix(pidLimit)` 再 `retain`，每个留下的 pid 从已有序列追加一点；超过 `seriesLimit`（90）才丢掉最旧点（54–77 行）。点数从 1 累积，不要求先攒满 90。离开 Top5 的 pid 本拍没有序列；新进入的 pid 没有上一套序列 |
| `MemorySampler.sample` | 先拼出本次枚举的完整 `rows`，写入 `lastRows`，再 `MemoryGrowthTopSeries.pids(from: rows, sort: memoryPageSort)`（143–144 行）。随后 `adopt`（仅当选中 pid 已在这份 topPids 里）和 `advance`，帧字段是 `topMemorySeries: topMemoryStore.seriesByPid`（145–170 行）。这里的 `rows` 是枚举结果，不经过名称过滤，也不经过「仅上涨」 |
| `MemorySampler.setMemoryPageSort` | 写入 `memoryPageSort` 后立刻 `retain(only: MemoryGrowthTopSeries.pids(from: lastRows, sort: sort))`（31–34 行）。`lastRows` 仍是上一拍完整枚举 |
| VM 排序交接 | `tableSort` 是 `navigation.sort`（`MemoryDashboardVM.swift` 110 行）。`publishMemoryPageSort()` 只在 `selectedPage == .memory` 时把**这一份** `tableSort` 交给 `sampler.setMemoryPageSort(sort)`（355–361 行）。资源页的当场 `tableSort` 走 `.skip`，不改 Top5。已有源码测试锁的是 `await sampler.setMemoryPageSort(sort)`，并禁止 `setMemoryPageSort(tableSort)` 与 `setMemoryPageSort(publication.sort)` 这两种字面调用 |
| VM 列表数据 | 接受且成功的帧里 `rows = frame.rows`、`topMemorySeries = frame.topMemorySeries`（467–469 行）。`visibleRows` 是 `MemoryGrowthRisingFilter.apply(rows:nameQuery:page:risingOnly:seriesByPid:)`（72–79 行）。`sortedRows` 是 `tableSort.ordered(visibleRows)`（82–85 行），无 `@Published`。Top5 **不**读 `visibleRows` / `sortedRows` |
| `memoryGrowthListBadge(for:)` | 调用 `MemoryGrowthList.badge(page: selectedPage, rowPid:, seriesByPid: topMemorySeries)`（135–140 行）。选中不是门控 |
| `MemoryGrowthSignal.evaluate` | `count < minSamples`（80）→ `.insufficient`（31–33 行）。`count >= 80` 就用**当前序列整段**：首尾 `netIncrease > deltaThreshold`（`8 * 1024 * 1024`，相等为 `.none`），相邻步严格 `>`，比较是 `positiveSteps * 5 >= stepCount * 3`（22、28–29、36–48 行），`riseFloor` 常量是 `0.6`。两道都过才 `.rising`。结果只有 `.insufficient` / `.rising` / `.none`。90 只是环上限，不是第二道门；已有 90 点也不从下标 90 再等下一点。这些是算法事实，不是帮助句 |
| `MemoryGrowthListCopy` | `title` 为「上涨」，`help` 为「近期内存持续上涨」（114–117 行）。这是今天徽标 help 的**唯一**生产字面量 |
| `MemoryGrowthListBadge` / `MemoryGrowthList.badge` | 结构体只有 `title`、`help`（120–123 行）。`page == .memory` 且 `seriesByPid[rowPid]` 存在且 `evaluate == .rising` 才返回 `MemoryGrowthListBadge(title: MemoryGrowthListCopy.title, help: MemoryGrowthListCopy.help)`（130–138 行）。缺 pid、不足、`.none`、其它页都是 `nil` |
| 开关 | `MemoryRisingOnlyChrome.toggleTitle` 为「仅上涨」；`showsToggle` 仅 `page == .memory`（`MemoryTablePhase.swift` 4–10 行）。`MemoryDashboardView` 36–39 行：`Toggle(MemoryRisingOnlyChrome.toggleTitle, isOn: $vm.risingOnlyFilter).toggleStyle(.switch).controlSize(.small)`。这条链上**没有** `.help`。开关在 `if showsToggle` 内，位于 `AppFilterField` 之前 |
| 行内徽标 | `ProcessTablePane.processList` 把 `vm.memoryGrowthListBadge(for: row.pid)` 传给 `ProcessLine`（249–255 行）。`MemoryGrowthRisingBadge` 是 `Text(badge.title)` 然后 `.help(badge.help)`、`.accessibilityHidden(true)`（418–429 行）。父行 `.accessibilityElement(children: .ignore)`，label 在 `if let growthBadge { parts.append(growthBadge.help) }`（376–397 行）。徽标为 `nil` 时父行 label 不含这句 |
| 包与工程 | `MemoryGrowthSignal.swift` 已在 `Package.swift` 的 SamplingCore `sources`（38 行）。`Views/`、`ViewModels/`、`Sampling/MemorySampler.swift` 被 exclude（21–22、28 行）。`Pulse.xcodeproj/project.pbxproj` 已有该文件的 PBXBuildFile（15 行）、PBXFileReference（69 行）、Models group（154 行）、Sources（337 行）。本期不新增 Swift 文件 |
| VM 表面 | `@Published` 23 处，`didSet` 两处（`risingOnlyFilter`、`selectedPid`），`@MainActor` 一处（第 4 行）。本期不新增发布属性 |
| 侧栏与空态（本期不改） | `MemoryGrowthCopy.rising` 是「近期驻留内存上涨」。`MemoryGrowthRisingFilterCopy.emptyTitle` / `emptyMessage` 是「Top5 暂无上涨」/「其他进程未做趋势判断」。过滤管道是名称过滤在前，内存页且开关 ON 时才按 `badge != nil` 保留；`ordered` 在保留之后做表头排序，**不再** `prefix(5)`（`MemoryGrowthRisingFilter.swift` 12–15、18–53 行） |

`MemoryDashboardVM` 自己不调用 `MemoryGrowthTopSeries.pids`。Top5 的纯函数入口在采样器，吃的是完整枚举行和已交接的内存页 `ProcessTableSort`。实现不要在 VM 里用 `visibleRows` 或 `sortedRows` 再算一套前 5。

## 今天的缺口

徽标 help 仍是「近期内存持续上涨」。开关只有标签「仅上涨」，没有 `.help`。终稿整句替换这一个 help 字面量，开关改为引用同一个静态属性。

`MemoryGrowthList.badge` 只对传入的那个 `rowPid` 调用 `evaluate`。表的「仅上涨」是 `MemoryGrowthRisingFilter.apply`：名称过滤之后留下 `badge != nil` 的行，不再 `prefix(5)`。两处界面读同一句，不各写一份字面量。

## 范围

| 项 | 今天 | 二十二期首包 |
| --- | --- | --- |
| 共享说明的生产来源 | `MemoryGrowthListCopy.help` 只喂徽标 | **仍是这一个静态属性**。开关改为引用它。不新命名，不新建 copy 类型 |
| 徽标 `title` / 开关标签 | 「上涨」/「仅上涨」 | **字面量保持** |
| 开关修饰 | `Toggle` + `.switch` + `.controlSize(.small)`，绑定 `$vm.risingOnlyFilter` | **只追加** `.help(MemoryGrowthListCopy.help)` |
| 行内 tooltip 与父行 label | `.help(badge.help)`；有徽标时 `parts.append(growthBadge.help)`；徽标 `.accessibilityHidden(true)`；父行 `children: .ignore` | **保持这些读法**。句子换掉之后，父行 label 自然带上同一句。这不是新的无障碍结构 |
| `evaluate` / 环 / Top5 | `count >= 80` 才对当前序列做首尾与相邻步；环上限 90，不是必须收满的门槛；严格大于 8MiB、3/5、N=5 | **数值与调用顺序保持**。不把 90 收成第二道门，已满 90 也不另等下一点 |
| 名称过滤、「仅上涨」谓词、空态两行、双清 | 十二 / 十五期 | **不改** |
| 表头切换、采样、选中定位、退出、侧栏上涨句 | 既有 | **不改** |
| 二十一期五条曲线说明 | 已合入 | **不重开** |
| `Package.swift` / `project.pbxproj` | 模型文件已登记 | **零 diff**。若实现发现必须改 pbx，停下交审，不要顺手登记 |

一二至二十一期验收不因本文重开。帮助句已由产品在 `b91c98b` 上锁死。实现还要等本设计合并，以及用户后续明确的实现委托或主控 gate。产品的 scope PASS 不代替这道门，也不代替运行 PASS。缺一就不要改 `static let help`。

## 共享字段

复核后选用已有的 `MemoryGrowthListCopy.help`，不另起名字。

徽标工厂已经只从这里取 help。父行和徽标 tooltip 读的是 `MemoryGrowthListBadge.help`，而这个字段的赋值来自同一个静态属性。开关今天没有帮助文本，直接引用这个静态属性。`MemoryRisingOnlyChrome` 只负责标签「仅上涨」和「哪一页画开关」。不把终稿搬到新静态属性上。

同源指下面这一条，而不是两处字符串碰巧相等：

1. 生产 Swift 里，说明句的字面量只出现在 `MemoryGrowthListCopy.help` 的右值，全文一次。
2. `MemoryGrowthList.badge` 的返回保持 `help: MemoryGrowthListCopy.help`。
3. 开关的修饰是 `.help(MemoryGrowthListCopy.help)`，视图文件里不出现这句的字面量。
4. `MemoryGrowthRisingBadge` 保持 `.help(badge.help)`。`ProcessLine.accessibilityLabel` 保持 `parts.append(growthBadge.help)`。这两处读实例字段，不读第二份字面量。

`MemoryGrowthListBadge` 不加第三字段。`title` 继续是 `MemoryGrowthListCopy.title`。

## 已锁帮助句

`MemoryGrowthListCopy.help` 的右值就是这一整句，开关和徽标共用它：

> 完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期驻留内存序列判断趋势。

生产 Swift 里这句字面量只出现这一次。视图不再写一遍。不得改字，不得拆成两句，不得为开关和徽标各写一句。80、8MiB、60%、90、百分比不进入这句。上面「已读源码」里的 `evaluate` 是算法，不是这句文案。

`MemoryGrowthList.badge` 只对传入的那个 `rowPid` 调用 `evaluate`。同一张 Top5 图里可以同时有 `.rising`、`.none` 和不足。表的「仅上涨」是 `MemoryGrowthRisingFilter.apply` 留下 `badge != nil` 的行。这是调用关系，不是第二句文案。

三处禁词测试原样保留，不改断言，不把 help 从 blob 拆出，不加豁免：

- `MemoryGrowthListBadgeTests.testCopyDoesNotClaimALeakOrDanger`
- `MemoryGrowthTopSeriesTests.testCopyDoesNotClaimALeakOrDanger`
- `MemoryDetailPresentationTests.testNewDetailCopyOmitsBannedWords`

前两处仍要求 `title` 与 `help` 的 blob 不含「泄漏」「泄露」「危险」「告警」，也不含大小写不敏感的 `leak`。第三处把 `MemoryGrowthListCopy.help` 留在原 blob 里，禁词表保持「泄漏」「泄露」「leak」「危险」，以及「异常」「独占」「可释放」「活动监视器」「真实占用」「footprint」「分钟」「稳定」「正常」「每点都在涨」。终稿不含这些子串，所以这些地板继续覆盖 help。十七期 Disclosure 的精确文案，以及该文案里已有的否定字串，不在本期重开。

`help` 仍不等于 `MemoryGrowthCopy.rising`（「近期驻留内存上涨」），也不等于徽标 `title`（「上涨」）。现有 `XCTAssertNotEqual(MemoryGrowthListCopy.help, "近期驻留内存上涨")` 与侧栏 caption 不等于 list help 的断言保持，不改期望。

## 视图接线

`MemoryDashboardView` 里现有开关改为：

```swift
Toggle(MemoryRisingOnlyChrome.toggleTitle, isOn: $vm.risingOnlyFilter)
    .toggleStyle(.switch)
    .controlSize(.small)
    .help(MemoryGrowthListCopy.help)
```

仍放在 `if MemoryRisingOnlyChrome.showsToggle(page: vm.selectedPage)` 里面，仍在 `AppFilterField` 之前，`ToolbarItemGroup(placement: .primaryAction)` 不变。不在**该 Toggle 的修饰链**上添加 `.disabled`。不改 `isOn`、`.switch`、`.controlSize(.small)`、`showsToggle`。CPU / 网络 / 磁盘 / GPU 不画这个开关，因此也没有这句 help。不要把 `.help` 加到 `AppFilterField` 或其它页。

`ProcessTablePane` 的徽标与父行结构不改。有徽标时，父行 VoiceOver 用的 label 会带上 `growthBadge.help`，也就是这份静态属性的值。徽标自身保持 `.accessibilityHidden(true)`。徽标为 `nil` 时（不在 Top5 序列、不足、`.none`、其它页）父行不追加这句；pid 离开 Top5 后序列被丢掉，下一次 `badge` 返回 `nil`，行 label 里不再有旧 help。开关上的 help 跟随着开关本身，只在内存页出现，不跟着某一行的徽标消失。

这些是源码上的数据关系。本设计没有跑 tooltip，也没有跑 VoiceOver。

## 数据路径（实现必须保持）

内存页上，一条 pid 要出现上涨徽标，顺序是：

1. `vm.tableSort` 在内存页经 `publishMemoryPageSort` 交给 `sampler.setMemoryPageSort`。
2. 采样器对**完整** `rows` 调用 `MemoryGrowthTopSeries.pids(from:sort:)`，`sort` 是 `memoryPageSort`。
3. `MemoryGrowthTopStore.advance` / `retain` 维护 `seriesByPid`，离开前 5 的 pid 当拍删除。
4. 成功帧写入 VM 的 `topMemorySeries`。
5. `MemoryGrowthList.badge` 只在内存页、该 pid 的序列存在、且 `MemoryGrowthSignal.evaluate` 为 `.rising` 时返回徽标。

`MemoryGrowthList.badge` 与表投影是两件事。徽标只看这一个 pid 的当前序列。`visibleRows` / `sortedRows` 是表的投影：名称过滤在前；「仅上涨」ON 时再留下 `badge != nil` 的行；表头排序作用在这个结果上，并且不再截前 5。因此「仅上涨」的输出不是另一套 Top5，也不是「前 5 名全都上涨」。帮助文本只说明这条已有路径，不改变它。

Linux 上可执行的证明用下面已有测试，调用真实的 `pids` / `evaluate` / `badge`。不要为了文案重写一套排序或趋势。本设计 PR 没有运行它们。

**前 5 的两座现成夹具**（`MemoryGrowthTopSeriesTests`）：

- `testPidsTakeTheCurrentMemorySortTopFive`：7 行，内存字节 `[10, 90, 80, 70, 60, 50, 40]`，pid 从 1 起。内存页默认排序（内存降序，pid 升序次键）的前 5 是 `[2, 3, 4, 5, 6]`。
- `testPidsFollowNameSortNotTheViewportOrAFilter`：6 行。名称升序的前 5 是 `[2, 4, 5, 6, 3]`。同一批完整行按内存降序的前 5 是 `[1, 4, 6, 3, 5]`。`ProcessNameFilter` 查询 `"Zebra"` 只剩 pid 1；`pids(from:)` 仍吃完整行，结果不是 `[1]`。

**过滤不改写成过滤后的前 5**（`MemoryGrowthRisingFilterTests.testTopFiveAndMenuBarStillEatTheUnfilteredRows`）：6 行夹具上，`risingOnly: true` 的 `apply` 结果是 pid `[1, 2]`。`pids(from: rows, sort: 内存默认序)` 是 `[1, 6, 2, 3, 4]`。对过滤结果再调用 `pids(from:)` 与对完整 `rows` 调用的结果不相等。这条测试保持，用来防止有人把「仅上涨」的输出当成 Top5 输入。

**进入序列之后才 `evaluate`。** `MemoryGrowthList.badge` 对这一个 `rowPid` 的当前序列调用 `MemoryGrowthSignal.evaluate`。徽标不是「选中的那一个 pid 就算」，也不是「完整列表里任意一行」，也不是「前 5 名全体上涨」。表的「仅上涨」不在这里重算。

进入判断的条件是 `count >= 80`。达到至少 80 点后，用当前序列的首点、末点和全部相邻步。环上限 90 不是必须收满的门槛；序列已经 90 点时，也不从下标 90 再等下一点。夹具里的 80 点、81 点、90 点是现有样例长度，不升成新门槛。已有断言保持：

- `MemoryDetailPresentationTests.testEightyPointBoundariesStayOnEvaluate`：80 点、步长 1MiB（`step: 1_048_576`）为 `.rising`；80 点且首尾净增恰好等于 8MiB 为 `.none`；同一长度净增 `deltaThreshold + 1` 为 `.rising`；79 点、步长 8MiB 为 `.insufficient`。80 点已经可以判断。
- 序列不足 80 点，即使每步都在涨，也是 `.insufficient`，徽标 `nil`（`MemoryGrowthSignalTests.testShortSeriesStaysInsufficientEvenWhenEveryStepClimbs`；`MemoryGrowthListBadgeTests.testInsufficientAndNoneOmitTheBadge`）。两点大增量同样不足，不得点亮徽标（`MemoryGrowthTopSeriesTests.testBadgeUsesEvaluateAndDoesNotInventASecondRise`）。
- `testFullFlatWindowIsNone` 用 90 点、步长 0，得到 `.none`，徽标 `nil`。90 是这条夹具的点数，也是环上限，不是「必须 90 点才判断」。净增不够在 80 点时同样是 `.none`：`testNetIncreaseMustBeStrictlyAboveTheThreshold` 的夹具长度就是 `minSamples`（80），首尾净增**等于** 8MiB 为 `.none`，严格大于才可能上涨。
- 达到 80 点的当前序列里向上步只有 1、末点抬高 64MiB，是 `.none`（`testEndHighWithFewUpStepsIsNone`）。这仍是现有三态里的 `.none`，不新加信号。
- 相邻向上步按 3/5 取整比较。`testRiseFloorBoundaryIsExact` 的夹具是 80 **步**（81 点）：48 步向上为 `.rising`，47 步向上且净增已超过 8MiB 为 `.none`。81 是为了让步数成 80，方便和 3/5 对齐，不是把门槛从 80 点改成 81 点。
- 达到至少 80 点的当前序列里可以有真实下降步；净增与 3/5 都成立时仍是 `.rising`（`testWindowWithRealDownticksStillRisesWhenThresholdsHold`，长度是 `minSamples`）。近期上涨不是「每一步都上升」。
- Top5 图里同时有上涨、平坦、不足时，只有上涨 pid 有徽标；图外 pid 即使被选中也是 `nil`（`MemoryGrowthListBadgeTests.testListWiringLightsEachTopFiveRisingRowNotOnlyTheSelection`、`testSelectionAloneIsNotEnoughForTheBadge`）。离开 Top5 后 `retain` 丢掉序列，徽标变为 `nil`（`MemoryGrowthTopSeriesTests.testSortChurnDropsTheFallenPidSeriesImmediately`）。
- 其它页 `badge` 为 `nil`（`testNonMemoryPagesNeverShowTheBadge`）。

`minSamples`、`deltaThreshold`、`riseFloor`、`pidLimit`、`seriesLimit` 的相等断言保持原数值。`seriesLimit` 仍是 90 的保存上限。说明句不把这些数写进 UI。

## 明确不做

- 不改 `minSamples = 80`、8MiB、60% / 3/5、`seriesLimit = 90`、Top5。80 仍是 `>=` 才对当前序列判断；90 仍只是环上限。不把 `evaluate` 改成必须收满 90，也不在已有 90 点时从下标 90 再等。不改比较式，不把上升改成「每一步都升」，不新增第四种信号。
- 不把名称过滤或「仅上涨」的输出送进 `pids(from:)`。不在 `MemoryGrowthRisingFilter` 上再 `prefix(5)`。不改 `apply` 的「名称在前、上涨保留在后」。
- 不改表头点击、`ProcessTableSort`、`MemoryPageSortPublication`、采样器 `sample()` / `setMemoryPageSort`、环、`adopt`、选中定位、退出、侧栏 `MemoryGrowthCopy`。
- 不改开关的开关行为：不在该 Toggle 的修饰链上加 `.disabled`，不改 `isOn`、样式、尺寸和位置。不改 `risingOnlyFilter` 的默认值和 `didSet`。
- 不改空态「Top5 暂无上涨」/「其他进程未做趋势判断」，不把帮助句塞进空态。
- 不改徽标的隐藏方式、胶囊样式和父行 `children: .ignore`。不给不足 / `.none` 补一行「样本不足」。
- 不加页面、图表、常驻警报、新曲线。不重开二十一期历史曲线说明，不改 `HistoryCurvePresentation`。
- 不新增模型文件、VM 发布属性、`Package.swift` 或 `project.pbxproj` 登记。SamplingCore 继续 exclude `Views/`、`ViewModels/` 和 `MemorySampler.swift`。
- 不改根 `README.md` 的期次索引。
- 本设计 PR 不写 Swift、不写测试、不跑 `swift test`、不合并。

## 实施时的文件

实现 PR 才动这些文件，而且要在本设计合并、以及用户后续明确的实现委托或主控 gate 之后。本设计 PR 不动。

| 文件 | 改动 |
| --- | --- |
| `Pulse/Models/MemoryGrowthSignal.swift` | 只把 `MemoryGrowthListCopy.help` 的右值改成终稿整句。`title`、`badge` 的返回行、`evaluate` 不动 |
| `Pulse/Views/MemoryDashboardView.swift` | 现有 `Toggle` 链追加 `.help(MemoryGrowthListCopy.help)` |
| `Tests/SamplingCoreTests/MemoryGrowthListBadgeTests.swift` | 红步把 `testLockedCopyIsShortBadgeAndCalmHelp` 的 help 期望改成终稿整句，先跑失败并保留 stdout。`testCopyDoesNotClaimALeakOrDanger` 不改 |
| `Tests/SamplingCoreTests/MemoryDetailPresentationTests.swift` | 红步把 `testListBadgeCopyAndIndependentRingStayPut` 里两处「近期内存持续上涨」都改成同一终稿整句，先跑失败并保留 stdout。`testNewDetailCopyOmitsBannedWords` 不改 |
| `Tests/SamplingCoreTests/MemoryGrowthTopSeriesTests.swift` | 排序、环、阈值、`testCopyDoesNotClaimALeakOrDanger` 都不改 |
| 新的源码接线测试 | 见下节。放在已有 `Tests/SamplingCoreTests/`，不进 App target，不改 `Package.swift` |

`ProcessTablePane.swift`、`MemoryDashboardVM.swift`、`MemorySampler.swift`、`MemoryGrowthTopSeries.swift`、`MemoryGrowthRisingFilter.swift`、`MemoryTablePhase.swift` 不改。

## 测试矩阵（设计；本 PR 不写、不跑）

实现 PR 的红必须是改生产代码之前、针对当前源码真实跑出来的失败。保存该次命令的完整 stdout。本环境没有这些日志。源码阅读断言通过，也不等于 tooltip、SwiftUI 或 VoiceOver 已经跑过。

**红（先于任何生产改动）：** 把帮助句期望改成终稿整句，并断言开关引用 `MemoryGrowthListCopy.help`。然后跑 focused，保留失败的完整 stdout。期望改动只在：

- `MemoryGrowthListBadgeTests.testLockedCopyIsShortBadgeAndCalmHelp`：`MemoryGrowthListCopy.help` 等于「完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期驻留内存序列判断趋势。」
- `MemoryDetailPresentationTests.testListBadgeCopyAndIndependentRingStayPut`：该测试里两处「近期内存持续上涨」都改成同一整句。一处是 `MemoryGrowthListCopy.help` 的相等断言，一处是 `MemoryGrowthListBadge(title: "上涨", help:)` 的字面量。

此时生产 `help` 仍是「近期内存持续上涨」，所以这两处失败。`MemoryGrowthListHelpWiringSourceTests` 读仓库文件，风格与 `TopAppLocationWiringSourceTests` 的 `repoText` 相同，断言 `MemoryDashboardView.swift` 含 `.help(MemoryGrowthListCopy.help)`。今天的开关没有这句，这一处也失败。禁止在测试里复制一份 `MemoryGrowthListCopy`，禁止 `XCTFail` 占位。

三处禁词测试不进入这刀，不改、不拆。`MemoryGrowthSignalTests` 与其它阈值断言不改。

**绿：** 把 `MemoryGrowthListCopy.help` 的右值改成终稿整句，并在现有 `Toggle` 上追加 `.help(MemoryGrowthListCopy.help)`。然后同一组 focused 通过，再跑不带 `--filter` 的 `swift test`。实现 PR 贴每条命令、exit code，以及 stdout 里的测试计数。不要手写一个看起来像通过的数字。本设计 PR 没有这些日志。

建议的 focused 过滤器（实现按实际 `swift test --filter` 的正则写进 PR，原样贴出）：

- `testLockedCopyIsShortBadgeAndCalmHelp`
- `testListBadgeCopyAndIndependentRingStayPut`
- `MemoryGrowthListHelpWiringSourceTests`

全量 `swift test` 必须仍然跑过，用来保住 Top5、阈值和过滤夹具。不要只跑文案测试就声称行为没变。

接线测试只读文本，并且要证明**标识符同源**，而不是两段字面量相等：

- `MemoryGrowthSignal.swift` 里，终稿整句出现一次，位置是 `static let help` 的右值。`badge` 函数体仍含 `help: MemoryGrowthListCopy.help`，且含 `title: MemoryGrowthListCopy.title`。`title` 的右值仍是「上涨」。
- `MemoryDashboardView.swift` 含 `.help(MemoryGrowthListCopy.help)` 一次。`Toggle(MemoryRisingOnlyChrome.toggleTitle, isOn: $vm.risingOnlyFilter)`、`.toggleStyle(.switch)`、`.controlSize(.small)`、`showsToggle(page: vm.selectedPage)` 仍在。该文件不含终稿整句，不含 `risingOnlyFilter = false`。`.disabled` 只查**该 Toggle 的修饰链**：从这一次 `Toggle(MemoryRisingOnlyChrome.toggleTitle, isOn: $vm.risingOnlyFilter)` 到它的 `.help(...)`，链上有 `.toggleStyle(.switch)` 和 `.controlSize(.small)`，链上没有 `.disabled`。不要对整个文件断言不存在 `.disabled`，以免文件里别的 `Toggle` 撞上。开关的 `range` 仍在 `AppFilterField(text: $vm.filter)` 之前（现有 `MemoryPageFilterClearWiringSourceTests.testToolbarAndAppFilterFieldStayNameOnlyClear` 继续成立）。
- `ProcessTablePane.swift` 的 `MemoryGrowthRisingBadge` 正文仍含 `.help(badge.help)` 与 `.accessibilityHidden(true)`。`accessibilityLabel` 仍含 `parts.append(growthBadge.help)`。父行仍含 `.accessibilityElement(children: .ignore)`。该文件不含终稿整句，不含 `MemoryGrowthListCopy.help`。
- `MemoryDashboardVM.swift` 不含终稿整句，不含 `MemoryGrowthListCopy`。`@Published` 仍是 23，`didSet` 仍是 2，`@MainActor` 仍是 1。`memoryGrowthListBadge` 仍把 `topMemorySeries` 传给 `MemoryGrowthList.badge`。`sortedRows` 仍是 `tableSort.ordered(visibleRows)`。
- `Package.swift` 与 `project.pbxproj` 相对基线无 diff。`MemoryGrowthSignal.swift` 原有的四处登记还在。没有新的 `PBXBuildFile`。
- 视图文件里的 `.help(badge.help)` 不得被改成 `.help("完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期驻留内存序列判断趋势。")`。父行继续读 `growthBadge.help`。开关的实参是标识符 `MemoryGrowthListCopy.help`，不是第二份字面量。

下列断言保持原样，包括数字和 pid 数组：`MemoryGrowthSignalTests` 的阈值与边界、`MemoryGrowthTopSeriesTests` 的 `[2, 3, 4, 5, 6]` 与 `[2, 4, 5, 6, 3]`、`MemoryGrowthRisingFilterTests.testTopFiveAndMenuBarStillEatTheUnfilteredRows` 的 `[1, 2]` 对 `[1, 6, 2, 3, 4]`、`MemoryGrowthListBadgeTests` 里不足 / `.none` / 缺 pid / 其它页为 `nil`。不要求新的 Sampling VM 测试。`MemorySampler` 不在 Linux 目标里；VM 交接沿用已有源码测试，本期不重写。

## 风险

| 风险 | 应对 |
| --- | --- |
| 开关和徽标各写一遍终稿 | 视图不含字面量。生产字面量只有 `static let help` |
| 用「两段文字相等」代替同源 | 接线测试断言标识符 `MemoryGrowthListCopy.help` 与 `badge.help` / `growthBadge.help` |
| 改字、拆句，或把算法说明写成帮助句 | 右值与两处测试期望都是终稿整句。`evaluate` 的 80 / 90 不写进这句 |
| 改禁词测试，或把 help 从 blob 拆出 | 三处禁词测试保持原断言。终稿不含那些子串 |
| 把「仅上涨」的可见行再截成前 5，或让 `pids` 改吃 `visibleRows` | 现有 pid 数组测试不改期望。VM 与采样器文件本期不改 |
| 给开关加 `.disabled`，或改 `isOn` / 样式 / 尺寸 | 接线测试只锁该 Toggle 的修饰链：原有三件修饰仍在，这条链没有 `.disabled`。不扫整个文件 |
| 为了 tooltip 去改父行结构，或让不足也读出 help | `children: .ignore`、`accessibilityHidden(true)`、`badge == nil` 不追加，都保持 |
| 顺手改侧栏句或空态句 | 那些字面量的测试不改期望。list help 仍不等于「近期驻留内存上涨」 |
| 新模型文件带出 `Package.swift` 或 pbx | 不新文件。若必须改 pbx，停下交审 |
| 把旧 head 的 scope PASS 当成新 head 已审，或当成运行 PASS | 下节。本 PR 不跑测试，不开实现 |

## 验收

- [ ] `MemoryGrowthListBadge` 仍只有 `title` 与 `help`。`title` 仍是「上涨」。开关标签仍是「仅上涨」
- [ ] `MemoryGrowthListCopy.help` 的生产字面量只有「完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期驻留内存序列判断趋势。」开关、徽标工厂、徽标 tooltip、父行 label 都从这一处来到界面上。徽标工厂与开关写的是标识符；tooltip 与父行写的是徽标字段
- [ ] 开关只多了 `.help(MemoryGrowthListCopy.help)`。`isOn`、`.switch`、`.small`、位置、`showsToggle` 不变。其它页没有这个开关，也没有这句 help
- [ ] 有徽标的父行 label 仍追加 `growthBadge.help`；无徽标不追加。离开 Top5 后序列被丢掉，该行徽标回到 `nil`
- [ ] 内存降序前 5 的现成期望仍是 `[2, 3, 4, 5, 6]`；名称升序前 5 仍是 `[2, 4, 5, 6, 3]`；名称过滤与「仅上涨」都不把 Top5 输入换成过滤后的前 5。`badge` 仍只对对应 pid 的当前序列 `evaluate`。不足、平坦、大净增但向上步不够，仍是现有 `.insufficient` 或 `.none`
- [ ] `count >= 80` 仍对当前序列做首尾与相邻步判断；`seriesLimit` 仍是 90 的环上限，不是必须收满的门槛，已满 90 也不另等下一点。8MiB、3/5、N=5、过滤顺序、表头、采样、环、选中定位、退出、侧栏句、空态句、二十一期曲线说明无行为变化。样例里的 80 / 81 / 90 点不升成新门槛
- [ ] 无新模型、无 `Package.swift` / pbx diff、无新的 `@Published`
- [ ] 实现 PR 有改生产代码之前的 focused 失败全文，以及之后的 focused 与全量 `swift test` 的命令、exit code 和计数。这些日志不是 Mac tooltip，也不是 VoiceOver

## Linux 已测与未验

本 PR 不跑测试。实现 PR 在 Linux 上能执行的是 SamplingCore 里的 `MemoryGrowthListCopy`、`MemoryGrowthList.badge`、`MemoryGrowthTopSeries.pids`、`MemoryGrowthTopStore`、`MemoryGrowthSignal.evaluate`、`MemoryGrowthRisingFilter`。`Toggle`、`.help`、`ProcessLine` 和 `MemoryDashboardVM` 不在这个目标里。开关是否引用静态属性、父行是否仍读 `growthBadge.help`，用源码阅读断言。那份阅读不证明 SwiftUI 画过 tooltip，不证明 VoiceOver 读过标签，也不证明 MainActor 上跑过 VM。

未验，不挡本设计合并。实现 PR 在 Linux 上也不能把它们勾成已过。若产品要把其中某一项当成合并门槛，另开单列，不写进本期 Linux 绿：

- 内存页开关的悬停、焦点和键盘是否出现这句 help；窄工具栏里 tooltip 的宽度与换行
- 行内徽标 tooltip 是否出现同一句；徽标 `.accessibilityHidden(true)` 之后，真实 VoiceOver 在有徽标和无徽标时如何朗读父行
- 真实 VoiceOver 是否朗读「仅上涨」开关的 help
- pid 离开 Top5 后，行上旧 help 是否从朗读里消失
- 切到 CPU / 网络 / 磁盘之后，开关与这句 help 是否都不在
- Xcode 编译 App，以及本机烟测、公证

本设计 PR 没有 Mac 日志，也没有 Linux `swift test` 日志。

实现等本设计合并，以及用户后续明确的实现委托或主控 gate，之后再写 Swift。产品对 `b91c98b` 的 scope / design + copy PASS 不授权实现，也不是运行 PASS。本 PR 不写 Swift、不写测试、不合并。

## 产品锁、本 head、技术 PASS

| | 状态 |
| --- | --- |
| 帮助句 | 已锁。整句是「完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期驻留内存序列判断趋势。」来源是 PRR 5798959320，只审过 `b91c98b7d7ee6df93b16e5ff7315ecfe893adc3a` |
| 本 head | 尚未经产品独立复核，也尚未过主控 full gate。不得把旧 head 的 PASS 复述到本 head |
| 技术 / 运行 PASS | 未发生。没有 `swift test` 计数，没有 Xcode 构建，没有 tooltip 或 VoiceOver 记录 |
| 实现 | 未委托。等本设计合并，以及用户后续明确的实现委托或主控 gate |

## 未决

帮助句没有第二句，禁词测试也不再拆分。还没发生的是：产品对本 head 的独立复核、主控 full gate、实现委托。Mac 上的 tooltip 与 VoiceOver 仍未验。

已经定下来的是：一个静态属性、两字段徽标、`title` 仍为「上涨」、开关行为不改、Top5 仍是完整列表按当前内存页表头排序后取前 5、`badge` 按该 pid 的当前序列 `evaluate`、表的「仅上涨」只是 `badge != nil` 的投影。`count >= 80` 就判断，90 只是环上限。三处禁词测试保持原断言。根 `README.md` 不加二十二期。
