# 内存详情大数在代表变化后仍匹配当前可见同名组（未实现）

> 落地前的技术约定。它不是实现授权，也不是 `main` 上已经显示的界面。当前界面仍以 [TECH.md](../TECH.md) 里标成「当前界面」的句子为准。
>
> 产品验收已锁定。本文只把该锁定收成可实现的查找。对照提交 `4313d5cbf2a86ee83fd23db294cc71c95e386ac7`。开写前核对过该提交仍是 `origin/main`。文件号 `33` 只用来接在 `32` 之后，不是期次立项。
>
> 落地后改写 TECH.md 的现状句。本文到那时停改。冒烟清单的勾选状态这次不动。

## 锁定的行为

只改内存页详情的内存大数从哪一行取数。曲线、最近值、峰值、上涨趋势、退出目标、列表高亮、滚动和 `⌘C` 都不改。

共享的 `displayedMemoryRow` 继续按选中 pid 是否等于合并行 pid 查找。CPU 页、网络页、磁盘页、本机页和 GPU 仍只走它。内存页的内存大数在「按 App」生效时改走下面的纯函数；函数返回空时，内存页也退回原来的单进程行。

### 纯函数

建议放在 `Pulse/Models/`，名称实现时再定。无存储，不读采样器，不写 `selectedPid`。

输入：

- `page`
- `grouping`：与 `sortedRows` 使用的是不是同一次判断，即 `groupedByApp && AppGroupChrome.applies(on: page)`
- `selectedPid`
- `visibleUngrouped`：这一帧的 `MemoryDashboardVM.visibleRows`

`visibleRows` 已是现成计算属性，不是新的发布字段。它的顺序是 `rows` 先经 `ProcessNameFilter`，内存页再经「仅上涨」，再经「仅窗口 App」。分组在它之后，由 `AppGroupProjection.apply` 完成。函数复用这个数组，不另做一套过滤，也不把结果存到下一帧。

输出：`ProcessRow?`。有值才替换内存大数那一行。空表示调用方继续用原来的单进程行。

规则：

1. `page != .memory`，或 `grouping` 为假，或 `selectedPid` 为空：返回空。
2. 在 `visibleUngrouped` 里找 `pid == selectedPid` 的那一行。找不到：返回空。不使用同名的其它行。
3. 名字只用这一行的 `name`。不读 `detail.row.name`，不读上一帧留下的名字。
4. 用 `AppGroupProjection.combine` 合并 `visibleUngrouped` 里 `name` 与它完全相同的行。这就是现成的合并规则。返回这一行。

`combine` 的 pid 仍是该组内存最大的代表，并列时仍是较小 pid。这个 pid 只存在于返回值里，不得写回 `selectedPid`，也不得拿去换曲线或退出目标。

同一次界面刷新里，`visibleUngrouped` 必须就是算出 `sortedRows` 的那份 `visibleRows`。不要先分组再按名字去另一份列表里找。

### 命中之后

内存大数的字节、占比句、`memorySource`、`residentMemoryIsPartial` 和 `groupedMemberCount` 都来自这同一返回行。占比句仍走 `MemoryDetailPresentation.field`。归属句仍走已落地的 `MemoryDetailAttribution`：有 `groupedMemberCount` 就写「当前可见的 N 个同名进程合计」，N 含 1。不写整个 App、全部成员或完整 App 内存。

对不上时不得沿用上一帧的合计。函数没有缓存；这一帧返回空，大数就是这一帧的单进程行。

### 代表变了，原 pid 仍可见

内存大数用上面的合计。`selectedPid` 不变，不调用 `setSelectedPid`。曲线点、点数不足 2 时的空摘要、「正在采集内存曲线」、不少于 2 点时的「PID … · 最近 … · 峰值 …」，以及实际上涨时的「这条趋势属于 PID …」，都仍按 [32-memory-detail-attribution.md](32-memory-detail-attribution.md) 用 `detail.row`。曲线口径仍是 `detail.row.memorySource`，不借合并行。

退出仍以 `selectedPid` 为唯一目标。普通退出没有确认框。强制退出确认句仍是「立即退出“显示名”？」。显示名仍来自完整 `rows` 里这个 pid 的 `name`（`ProcessQuitSession.requestForce`），不是合并行的代表 pid。本期不改退出流程、确认文案和目标。

### 原 pid 不在可见集合，或缺席

不借其它同名成员。

既有路径还提供这个 pid 的详情时，大数退回该进程自己，归属句是「当前进程（PID …）」。既有路径已经清掉选中、或不再显示详情时，保持那个结果。不新增保留、恢复或重选。

下面是 `4313d5c` 上已经存在的选中路径，本文不改它们，也不把它们写成新规则：

- 名称过滤不参与清选中。`MemoryGrowthRisingFilter.selectedPid` 不读名称查询。pid 仍在 `rows` 里时，采样器仍会给详情。
- 「仅上涨」打开且该 pid 没有列表徽标时，同一拍把选中清掉。
- 「仅窗口 App」打开且该 pid 不在窗口集合里时，同一拍把选中清掉。
- pid 不在 `rows` 里时，`legalListSelection` 把列表选中清成空，实时详情不再是这个 pid。

名称过滤的谓词只看 `name.localizedCaseInsensitiveContains`。两个 `name` 完全相同的行会一起留下或一起去掉。所以「名称过滤藏住原 pid，同时另一个完全同名的行仍可见」不是当前名称过滤的输出。纯函数仍必须在输入被这样构造时返回空，这不要求去改过滤器。仅上涨和仅窗口可以按 pid 去掉一个人、留下另一个同名进程；那两条既有清选中会先发生，清掉之后不再做这次查找。

### 本帧改名和成员进出

选中进程这一帧的 `name` 变了，就用可见集合里这一行的新名字找组。找不到组则退回它自己。成员进出只影响这一帧 `combine` 的结果。不记录稳定的 App 身份，不保留组历史。

## 明确不做

- 不改采样、`ChartSample`、分组键、`combine` 的加减、过滤、排序、上涨判断、清选中。
- 不改 pid 复用时曲线是否切断。
- 不改列表高亮、滚动和 `⌘C`。这三项另开。
- 不加组曲线、组历史、整组退出。
- 不改 CPU 页和其它页的大数查找。`displayedMemoryRow` 保持 `sortedRows.first { $0.pid == row.pid }`。
- 不把内存页 CPU 卡片改成组合计。它今天就是 `detail.row.cpuPercent`。
- 不把强制退出确认改成带 pid 的句子。

## 和当前源码的接法

`4313d5c` 上，内存大数在 `ProcessDetailSidebar.metrics` 里用 `displayedMemoryRow(detail.row)`。代表 pid 一变，合并行的 id 不再是选中 pid，查找失败，字节和归属都回到单进程。这就是要换掉的内存页路径。

落地时只让内存页内存大数在函数有值时用返回行，无值时仍用 `displayedMemoryRow` 的结果。`memoryChart` 和趋势继续传 `detail.row`。`displayedProjection` 继续传 `displayedMemoryRow`，CPU 页因此不变。

`ProcessEnergyWiringSourceTests` 锁着 `displayedMemoryRow` 里的 pid 查找字符串。落地不得为了内存页去改这一函数，否则 CPU 页的能耗和唤醒大数会跟着变。

## 测试

行为测试是纯函数，接线测试只读源码。二者都不是 Mac 点击，也不是 VoiceOver。本文档 PR 没有跑本机冒烟。

先写会编译失败的纯函数测试，再补函数，然后改内存页接线并更新对应的源码断言。一个实现 PR。

纯函数至少覆盖：

- 代表 pid 已变，原 pid 仍在 `visibleUngrouped`：返回行的字节、`memorySource`、`residentMemoryIsPartial`、`groupedMemberCount` 与 `combine` 该名字的可见成员相同。调用不产生新的选中 pid。
- 可见成员只有原 pid：`groupedMemberCount == 1`，字节等于它自己。归属句仍由现成逻辑写成合计，不在本函数里另写文案。
- `grouping` 为假：返回空。
- 原 pid 不在可见集合，集合里另有完全同名的行：返回空。
- 原 pid 缺失、`selectedPid` 为空：返回空。
- 可见行里该 pid 的 `name` 已是新名字：按新名字合并；新名字没有其它成员时得到 N 为 1 的合并行。
- 合并行是驻留且部分回退，同时另有一个曲线行是内存占用：本函数只返回合并行；曲线口径不在这里改，仍由现成归因用曲线行。
- `page` 不是内存：即使 `grouping` 为真也返回空。
- 非内存页、以及内存页但函数返回空：不把上一组的字节留在返回值里。

接线只证明：内存页大数在函数有值时用它；`displayedMemoryRow` 的 pid 查找字符串还在；`memoryChart` 的曲线行仍是 `detail.row`；CPU 详情函数体不调用这个新函数；`requestForce` 仍用 `rows` 里该 pid 的 `name`。`applySample` 不因此调用 `setSelectedPid`。

过滤的清选中和保留详情用现有测试，不在本函数里重写一遍规则。
