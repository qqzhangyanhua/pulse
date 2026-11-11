# 样本不足槽补当前采样对象 PID（未实现）

> 落地前的技术约定。它不是实现授权，也不是 `main` 上已经改变的界面。当前详情仍以 [TECH.md](../TECH.md) 为准：样本不足仍是「样本不足，暂不判断」，不追加 PID。
>
> 产品验收已锁定。本文只约定：现有不足槽补一句「当前采样对象：PID …」。对照提交 `1fddb1cadc9197475f2365e8b2f6a3d39c8775c5`。开写前核对过该提交仍是 `origin/main`，父提交 `e2344a5fd5c2d76ef13785552dec0d0b29f45be9`。没有更晚提交。文件号 `39` 只用来接在 `38` 之后，不是期次立项。
>
> 这是显式解开规格 32「样本不足不追加 PID」。那是当时的产品决定，不是现有实现写错。上涨句、曲线摘要和 `.none` 不占位仍保持规格 32。
>
> 落地后改写 TECH.md 的现状句。本文到那时停改。本机冒烟清单的勾选这次不动。本文档 PR 没有跑 Mac 悬停，也没有跑 VoiceOver。静态测试不能代替这两项。

## 今天的槽

采样器 `detailFrame`（`MemorySampler.swift` 256–277 行）只用采样器里的 `selectedPid` 在未合并 `rows` 里找行。调用在 203 行，这些 `rows` 是采样器刚从枚举拼出来的进程行，还没有按 App 合并。找到才把该 pid 的 `selectedMemorySeries` 放进 `ProcessDetail`（272–276 行）。`setSelectedPid`（25–30 行）一换 pid 就清空这条环，连带清空 CPU 环。`ChartSample`（`MemoryModels.swift` 24–28 行）只有 `id`、`date`、`value`，没有 pid。

`ProcessQuitSession.displayedDetail`（`ProcessQuitSession.swift` 324–338 行）在主体还在时，优先用 `live.row.pid == subject` 的实时详情；对不上就造一份该主体行的空序列。缺席记录返回冻结详情，不走这条空序列。`showsLiveTrend`（100–103 行）还要求未冻结、详情非空、`listSelectedPid == subject` 且主体仍在列表里（`legalListSelection`，`ProcessQuitOutcome.swift` 28–30 行）。`frozen` 就是 `projected.showsAbsentRecord`（85 行）。缺席冻结卡没有趋势槽。

`MemoryDashboardVM.memoryGrowthSlot`（`MemoryDashboardVM.swift` 161–168 行）只在 `showsLiveTrend` 时调用 `MemoryGrowthSidebar.slot`，序列是 `sidebar.detail?.memorySeries`。

`slot`（`MemoryGrowthSignal.swift` 97–110 行）用 `selectedPid != nil` 当门闩，然后 `evaluate` 这段序列。`selectedPid` 的值不写进槽。序列数组本身对不上号。不足 80 点或序列为空时 caption 是「样本不足，暂不判断」，`basis` 为 `nil`（`basis(for: .insufficient)`，73–79 行）。`.none` 的 caption 为 `nil`（67–68 行），整个槽返回 `nil`。

侧栏 `body`（`ProcessDetailSidebar.swift` 15–16 行）有 `sidebar.detail` 才画 `detailBody`。`detailBody`（167–177 行）画的就是这份 `sidebar.detail`，在内存页槽非空时调用 `memoryTrend(slot, curveRow: detail.row)`。

`memoryTrend`（`ProcessDetailSidebar+MemoryAttribution.swift` 30–55 行）只在 `slot.caption == MemoryGrowthCopy.rising` 时向 `MemoryDetailAttribution.make` 要「这条趋势属于 PID …」，并放进同一个 `.accessibilityElement(children: .combine)`。不足时 `trendIsRising` 为 false。`make`（`MemoryDetailAttribution.swift` 37 行）在 false 时 `.trend` 为 `nil`。界面只剩标题和「样本不足，暂不判断」。旁注只在 `slot.basis` 非空时出现，不足没有旁注。这次调用把同一个 `curveRow` 传给 `magnitudeRow` 和 `curveRow`，`memoryPointCount` 传的是 `0`。点数不决定这句。

`memoryMagnitudeRow`（`ProcessDetailSidebar+MemoryAttribution.swift` 6–16 行）和 `MemoryMagnitudeVisibleGroup` 只供大数。`metrics`（`ProcessDetailSidebar.swift` 353 行）用它。可见组代表是 `AppGroupProjection.combine` 里更重的那个 pid（`AppGroupProjection.swift` 42–55 行），可以是另一个 pid。受评序列仍是 `detail.row` 那个 pid 的环。组代表不进入趋势槽。

## 锁定的行为

只给现有不足槽补一句。上涨原句不改，仍是「这条趋势属于 PID …」。`.none` 不占位，不为新句造槽。曲线与判断规则不改，沿原合并读屏。

PID 必须取这次传进 `memoryTrend` 的那个 `curveRow`，也就是侧栏这份 `sidebar.detail.row`。不借 `memoryMagnitudeRow` / `MemoryMagnitudeVisibleGroup` 可见组代表，也不要在句里再读一遍 `selectedPid`。`MemoryGrowthSidebar.slot` 的 `selectedPid != nil` 只决定有没有槽，序列数组本身对不上号；再读选中值写进的是门闩，不是点列主人。

新句是「当前采样对象：PID 123」。123 是这个 `curveRow.pid`。`MemoryGrowthCopy.insufficient` 保持原字「样本不足，暂不判断」。上涨那句保持原字「这条趋势属于 PID …」，pid 仍是同一个 `curveRow.pid`。两条句子不同时出现。新句单独一条 `Text`，留在现有 `combine` 里。今天这条 `Text` 就是 `if let trend`。不足时它显示新句，上涨时它仍显示上涨句。不把 pid 拼进 caption 常量，也不拼进 `MemoryGrowthCopy.rising` 或 `basis`。不另设和可见文字不同的 `accessibilityLabel`。CPU 页不调用 `memoryTrend`。

### nil 和错配

槽能画出来时，`detail.row.pid`、列表 `selectedPid` 和侧栏主体是同一个数。句子仍应使用已经传进 `memoryTrend` 的 `curveRow`。可见组代表和这个 pid 可以不同。大数用代表行，曲线和趋势用 `detail.row`。新句若去读 `memoryMagnitudeRow`，就会把代表 pid 说成这段不足序列的主人。

`.none`、`selectedPid == nil`、详情为空、缺席冻结，槽都是 `nil`，`memoryTrend` 不会被调用，不能为了新句把槽造出来。

实时详情对不上主体时，评估的是那一行的空序列，不是上一个进程留下的点。空序列仍是样本不足。新句写的是这个空详情的 `detail.row.pid`。

点数在 2 到 79 之间时，曲线摘要里已有同一 pid。曲线占位和摘要规则不动。0 点或 1 点仍是「正在采集内存曲线」，摘要为空，不写 PID。不足槽里的新句不代替这条曲线规则。

## 明确不做

- 不改上涨句「这条趋势属于 PID …」。不把 PID 写进 `MemoryGrowthCopy.insufficient`、`rising` 或 `basis`。
- 不改曲线占位、摘要、标题和口径。不改 80 点、8 MiB、60% 间隔，不改 `evaluate`。
- `.none` 不占位。不为新句在 `selectedPid == nil`、详情为空或缺席冻结时把槽造出来。
- 不读 `memoryMagnitudeRow`、可见组代表，也不在句里再读 `selectedPid`。
- 不改已落地的组行上涨徽标 help。不做组曲线、算法调整、侧栏新布局或其它缺口。
- CPU 页不调用 `memoryTrend`，不加这句。
- 不改本机冒烟清单的勾选文案。清单仍写「样本不足不加 PID」。

## 测试

能编译的红是现有符号上的值不等。缺一个新符号导致的编译失败，不能当成这句话已经复现。

在当前 `main` 上能编译、并且应当失败的断言：`MemoryDetailAttribution.make` 在内存页、`trendIsRising: false`、曲线行 pid 为 4、大数行 pid 为 9 时，今天 `.trend` 为 `nil`。断言它等于「当前采样对象：PID 4」会失败。失败原因是 `nil` 和这句不相等，不是找不到类型。这句里不出现大数行的 pid 9。

同一调用在 `trendIsRising: true` 时仍应等于「这条趋势属于 PID 4」。这条今天就是绿的，保持。

现有 `XCTAssertNil(insufficient.trend)`（`MemoryDetailAttributionTests.testTrendLineOnlyForARisingMemorySlotAndUsesTheCurvePid`）是规格 32 的锁。产品要解开的就是它。实现后改成新句，不能两句断言并存。

今天 `trendIsRising: false` 时 `.trend` 一律是 `nil`。同一条 false 分支上还有 `XCTAssertNil(quiet.trend)`，以及 0 点和 1 点的 `XCTAssertNil(attribution.trend)`（`testZeroAndOnePointLeaveThePidOffAndKeepThePlaceholder`）。模型把 false 改成新句之后，这两处不能再要求 `nil`，否则和「false 时等于新句」不能同时成立。它们不是第二句产品文案。曲线占位「正在采集内存曲线」、0 点和 1 点摘要为空，这些断言保持。非内存页即使 `trendIsRising: true`，`.trend` 仍是 `nil`。`.none` 不靠 `make` 返回 `nil` 来藏句子：槽本身是 `nil`，`memoryTrend` 不会被调用。

不要把 pid 拼进 caption 常量。`MemoryGrowthSidebarTests` 的 `testLockedCopy` 仍锁着 `MemoryGrowthCopy.insufficient` 等于「样本不足，暂不判断」全文。`MemoryGrowthCopy.rising` 仍是「近期内存占用上涨」。

平坦满窗和 `selectedPid == nil` 时 `slot` 仍为 `nil`。这是 `testNoneAndNoSelectionOmitTheSlot`：满窗步长 0 的平坦序列，以及 `selectedPid == nil` 时即使传入上涨序列，槽都是 `nil`。空序列或 `detailSeries == nil` 仍是「样本不足，暂不判断」，不是 `nil` 槽。

接线只读源码：不足时新句是单独一条 `Text`，位于现有那一个 `.accessibilityElement(children: .combine)` 之内。`memoryTrend(slot, curveRow: detail.row)` 仍把 `detail.row` 传进去。`memoryTrend` 不出现 `memoryMagnitudeRow`、`MemoryMagnitudeVisibleGroup`，也不在句里再读 `selectedPid`。CPU 详情函数体仍不调用 `memoryTrend`。

这些测试不是 Mac 悬停验收，也不是 VoiceOver 验收。
