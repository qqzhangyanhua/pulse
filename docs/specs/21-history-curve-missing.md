# Pulse 二十一期技术设计（首包：主机总览五条曲线在当前值缺失时附静态说明）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 21 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。
>
> 已被取代：「历史曲线 · 当前值暂不可用」不再只用于主机总览五条曲线，本机页总览曲线也用同一句。

> 一期至二十期正文不改写。本节只覆盖主机总览 **ready** 里已经存在的五条曲线：CPU 一条，网络下行 / 上行各一条，磁盘读取 / 写入各一条。当前值是 `nil` 且**这一条**序列的 `samples.count >= 2` 时，在原有 `SparklineChart` 上附一句静态说明。真实 `0` 和任何非 `nil` 都不附。一侧 `nil`、另一侧 `0` 或正值，互不连带。当前值恢复成非 `nil`（含 `0`）时，这句说明撤掉。0 点或 1 点仍走原来的采集 placeholder，不画假线。

**技术候选**（已交本 PR 的产品范围评审；不是实现，也不是已跑过的技术 PASS）。图内边距锁 5pt。父级 label 的方向归属见「无障碍候选」。

- 新增无状态纯函数 `HistoryCurvePresentation`。唯一文案是 `历史曲线 · 当前值暂不可用`。`annotation(current:sampleCount:)` 只在 `current == nil && sampleCount >= 2` 时返回这句，其余返回 `nil`。
- 视图只加一个最小 wrapper `HistoryAnnotatedChart`。`annotation == nil` 时就是原来的图表；非 `nil` 时只在原图上 overlay 这句。不给 `SparklineChart` 增加参数，也不给它默认值。
- 五条曲线各自用自己的 current 和同方向 samples。没有「一张总览卡统一开门」。
- 不新增 `@Published`。二十期已经合入的 VM 字面量保持 `@Published` 23、`didSet` 2、`@MainActor` 1。

来源：二十一期技术候选，范围已交本 PR 的产品范围评审。对照 `c28923f42ae67db7ad8395a4b75e5fa79d501e09`（`origin/main`，二十期实现 #64）。本节开写前读过的是这份树上的源码。这不是实现授权，也不是 Mac 上的视觉终验。

本 PR 只追加本节。不改 `README.md`，不写 Swift，不改 `Package.swift` / `project.pbxproj`，不写测试，不跑 `swift test`，不合并。下面的红绿步骤是实现 PR 的设计，不是本 PR 的执行结果。

## 已读源码（本 SHA）

| 位置 | 今天的事实 |
| --- | --- |
| `CPUOverviewSection` | `loadState` 分 `sampling` / `failed` / `ready`（7–15 行）。ready 左栏大数是 `CPUPercentText.string(vm.systemCpuPercent)`，副行是 `overviewLine`（59–75 行）。`chart`：`vm.cpuHistory.samples.count < 2` 时 `ChartPlaceholder(text: "曲线采集中")`，否则 `SparklineChart(samples: vm.cpuHistory.samples, …)`（101–113 行）。ready 无障碍是 `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(overviewLine)`（82–83 行）。sampling 是 `.combine`，标签为 `overviewLine` 加 `CPUPageCopy.sampling`（39–40 行）。failed 是 `AppEmptyState`，没有这条曲线 |
| `CPUPageCopy.overviewLine` | `"CPU · \(CPUPercentText.string(systemCpuPercent))"`（`CPUPage.swift` 29–32 行）。`CPUPercentText`：`nil` → `—`，有值走 `%.1f%%`（4–11 行） |
| `NetworkOverviewSection.readyBody` | 两张 `NetworkRateCard`。下行：`rate: vm.hostNetworkRates.inboundBytesPerSecond`，`samples: vm.networkHistory.inbound.samples`。上行：`outboundBytesPerSecond` 与 `networkHistory.outbound.samples`（49–63 行）。父级 `HStack` 是 `.ignore` + `.accessibilityLabel(overviewLine)`（65–66 行）。两张卡自己没有无障碍修饰 |
| `NetworkRateCard` | 文件内 `private struct`（102–165 行）。大数 `NetworkRateText.string(rate)`，副行 `"\(title) · \(NetworkRateText.string(rate))"`。`chart`：`samples.count < 2` 时 `ChartPlaceholder(text: NetworkPageCopy.chartCollecting)`，否则 `SparklineChart(samples: samples, …)`（147–159 行）。`chartCollecting` 是 `"曲线采集中"`（`NetworkPage.swift` 53 行） |
| `NetworkPageCopy.overviewLine` | 下行、上行各拼一次 `NetworkRateText`（55–58 行）。`NetworkRateText`：`nil` → `—`；`0` → `"0 字节/秒"`（4–13 行） |
| `DiskOverviewSection` / `DiskRateCard` | 与网络同形（49–67、102–165 行）。读取：`vm.hostDiskRates.readBytesPerSecond` + `vm.diskHistory.read.samples`。写入：`writeBytesPerSecond` + `diskHistory.write.samples`。placeholder 文案是 `DiskPageCopy.chartCollecting`，而它等于 `sampling`，即 `"正在采样…"`（`DiskPage.swift` 15、24 行）。ready 无障碍同样在父级 `HStack`（65–66 行） |
| `HostNetworkRates` | 只有 `inboundBytesPerSecond` 与 `outboundBytesPerSecond`（`HostNetwork.swift` 19–23 行）。没有名为 `inbound` / `outbound` 的速率字段 |
| `HostDiskRates` | 只有 `readBytesPerSecond` 与 `writeBytesPerSecond`（`HostDisk.swift` 11–15 行）。没有名为 `read` / `write` 的速率字段 |
| `SystemCPUHistory.record` | `guard let percent, let date else { return }`。`samples.last?.date == date` 则 return。否则 append，超过 `limit` 则 `removeFirst`。`init(limit:)` 默认 `90`（`CPUPage.swift` 173–197 行）。`nil` 不写入，也不把已有点清掉，也不写成 `0` |
| `SystemNetworkHistory` / `SystemDiskHistory` | 两个方向各持有一份 `SystemCPUHistory`。`record(rates:at:)` 把该方向的 `*BytesPerSecond` 传给对应环的 `record(percent:at:)`（`NetworkPage.swift` 61–80 行，`DiskPage.swift` 37–56 行） |
| `MemoryDashboardVM.applySample` | 接受且成功的帧里，先写 `systemCpuPercent` / `hostNetworkRates` / `hostDiskRates`，再对三份 history `record`，日期都是 `frame.snapshot.capturedAt`（444–466 行）。失败分支（483–494 行）和未接受的 flight（440–441 行）不调用这三份 `record`。VM 里找不到对这三份 history 的 `reset()`；存储属性只在 26–28 行构造一次 |
| `SparklineChart` | `SharedUI.swift` 329–388 行。参数是 `samples`、`tint`、`domain`、`formatY`，没有默认值，没有 annotation。轴在 `chartXAxis` / `chartYAxis` 里 |
| 其它 `SparklineChart` 调用 | 内存用量卡（`OverviewCards.swift` 90–100 行）、压力卡（262–270 行）、进程侧栏 `seriesBlock`（`ProcessDetailSidebar.swift` 442–446 行）。侧栏内存页与 CPU 资源页用 `memoryChart` / `cpuChart`；网络资源页是 `processNetworkUnavailable` 文案加内存曲线（214–228 行）；磁盘资源页是读/写数字加内存曲线（230–241 行） |
| 页切换 | `MemoryDashboardView` 9–18 行：`.cpu` / `.network` / `.disk` 各走自己的总览，`default` 才是内存 `OverviewSection` |
| `cpuPhase` | `ProcessTablePane` 28–36 行，类型是 `CPUPagePhase`，本体调用 `CPUPagePhaseResolver.resolve`。CPU / 网络 / 磁盘三页都进 `resourceTableBody`，186 行 `switch cpuPhase`（调用点 75、84、93 行）。这是进程表空态 / 采样 / 失败 / 就绪，不是主机 CPU 火花线。进程网络格渲染 `row.networkAvailability.label`（360 行），该 label 在 `MemoryModels.swift` 135 行已是 `"暂不可用"` |
| VM 表面 | `@MainActor` 在第 4 行，全文只这一处。第 40 行注释写 “on the MainActor”，没有 `@`。`@Published` 23 处（6–43 行，含二十期 `topAppLocateReveal`）。`didSet` 两处：`risingOnlyFilter`（32 行）、`selectedPid`（44 行）。`sortedRows` 是 `tableSort.ordered(visibleRows)`（82–85 行），无 `@Published`。`locateMemoryTopApp` 在 160–176 行 |
| 包与工程 | `Package.swift` 的 SamplingCore `sources` 是显式清单（35–60 行），并 `exclude` `Views/` 与 `ViewModels/`（21–22 行）。`TopAppLocation.swift` 在 `project.pbxproj` 有 PBXBuildFile（23 行）、PBXFileReference（76 行）、Models group（160 行）、Sources（342 行）。`SharedUI.swift` 已经在 Views group（231 行）和 Sources（56、373 行），文件引用在 109 行 |
| 已有 history 测试 | `CPUPageTests.testSystemCPUHistorySkipsNilAndDoesNotPlotZero`（181–199 行）、`NetworkPageTests.testSystemNetworkHistorySkipsNilAndDoesNotPlotFakeZero`（139–172 行）、`DiskPageTests.testSystemDiskHistorySkipsNilAndDoesNotPlotFakeZero`（151–184 行）。另有 `testReadyFrameWithNilHostRatesIsNotAFailure`：整份缺失时总览行是「下行 · — · 上行 · —」或「读取 · — · 写入 · —」，`CPUPagePhaseResolver.resolve` 在传入 `loadState: .ready` 时仍返回 `.ready`（网络 125–137 行，磁盘 137–148 行） |
| `@Published == 23` 的现有源码测试 | `MemoryPageFilterClearWiringSourceTests`（同时锁 `didSet` 2、`@MainActor` 1）、`MemoryDashboardVMSortWiringSourceTests`、`MemoryDetailSidebarWiringSourceTests`、`ProcessQuitSessionWiringSourceTests`、`ResourceDetailPageSourceTests`、`TopAppLocationWiringSourceTests`（70–72 行同时锁三个数） |

`UsageHistory.record`（`MemoryModels.swift` 50–53 行）在快照为 `nil` 时会 `removeAll`。主机 CPU / 网络 / 磁盘的环不是这条语义：`nil` 只是跳过。二十一期不把清环搬到这三条曲线上，也不给用量曲线或压力曲线加这句说明。

## 今天的缺口

ready 且当前值变成 `nil` 时，大数已经是「—」，副行里对应位置也已经是「—」。样本数仍 `>= 2` 时，右侧仍是此前留下的 `SparklineChart`，图上没有「这是历史线、当前值暂不可用」的说明。0 点或 1 点则是 placeholder，本来就没有线。

失败页和采样页不画这五条火花线。`nil` 主机速率在现有测试里不是失败。本节不把说明塞进 `samplingBody` / `failureBody`，也不改 `LoadState`。

## 范围

| 项 | 今天 | 二十一期首包 |
| --- | --- | --- |
| ready 且该条 `current == nil` 且该条 `samples.count >= 2` | 只留旧火花线、大数「—」、副行 | **做**：该条图表 overlay 一句静态说明 |
| 该条 current 为 `0` 或其它非 `nil` | 大数格式化该值，无额外说明 | **保持无说明** |
| 一侧 `nil`、另一侧 `0` 或正值 | 两张卡各画各的 | **保持独立**。只有 `nil` 且样本 `>= 2` 的那条附说明 |
| `current` 从 `nil` 回到非 `nil`，含 `0` | 大数离开「—」 | **撤说明**。不写退场动画 |
| 样本数 0 或 1 | 原 placeholder | **保持**。说明函数也返回 `nil`，不包一层假线 |
| sampling / failed | 骨架或 `AppEmptyState` | **不附**这句。不改重试、不改 `loadState` |
| `SparklineChart` | 四参数，无默认 annotation | **不增加参数** |
| 内存用量、压力、进程内存 / CPU 曲线、资源侧栏、菜单栏 | 现有图或文案 | **不接**新类型 |
| VM `@Published` / `didSet` / `@MainActor` | 23 / 2 / 1 | **三个数都不变**。不新增发布属性 |
| 二十期定位 | `sortedRows`、`locateMemoryTopApp`、`topAppLocateReveal` | **不改** |

一二至二十期验收不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 五条映射

说明函数不读 VM，不读另一方向。调用点把下面的值传进去。

| 曲线 | current | samples | 图表上的调用点 |
| --- | --- | --- | --- |
| CPU | `vm.systemCpuPercent` | `vm.cpuHistory.samples` | `CPUOverviewSection.chart` 的 `else` |
| 下行 | 这张 `NetworkRateCard` 的 `rate`。父级传入 `vm.hostNetworkRates.inboundBytesPerSecond` | 这张卡的 `samples`。父级传入 `vm.networkHistory.inbound.samples` | `NetworkRateCard.chart` 的 `else` |
| 上行 | 该卡 `rate` ← `outboundBytesPerSecond` | 该卡 `samples` ← `networkHistory.outbound.samples` | 同一个 `NetworkRateCard.chart`，另一次实例 |
| 读取 | 该卡 `rate` ← `vm.hostDiskRates.readBytesPerSecond` | 该卡 `samples` ← `vm.diskHistory.read.samples` | `DiskRateCard.chart` 的 `else` |
| 写入 | 该卡 `rate` ← `writeBytesPerSecond` | 该卡 `samples` ← `diskHistory.write.samples` | 同一个 `DiskRateCard.chart`，另一次实例 |

`HostNetworkRates` 上不存在 `.inbound`。`inbound` / `outbound` 是 `SystemNetworkHistory` 里那两份环的属性名，点在 `.samples`。磁盘的 `read` / `write` 同理，是 `SystemDiskHistory` 的环，不是 `HostDiskRates` 的字段名。

父级 `readyBody` 只负责把上表的实参传进卡，不在 `HStack` 上再包一层 `HistoryAnnotatedChart`。一张卡的 `chart` 只 overlay 一次。网络两张卡、磁盘两张卡不是「一张共享图上叠两句」。

`samples.count < 2` 的分支保持今天的 `ChartPlaceholder` 文案，不包 wrapper。`else` 里先算 `HistoryCurvePresentation.annotation(current:sampleCount:)`，再交给 wrapper，wrapper 的 content 仍是原来的 `SparklineChart`，`samples` 实参不变。`domain` 与 `formatY` 不改。

## 纯函数

新文件 `Pulse/Models/HistoryCurvePresentation.swift`。无 `import SwiftUI`。不放进 `Views/` 或 `ViewModels/`。

```swift
enum HistoryCurvePresentation {
    static let unavailable = "历史曲线 · 当前值暂不可用"

    static func annotation(current: Double?, sampleCount: Int) -> String? {
        guard current == nil, sampleCount >= 2 else { return nil }
        return unavailable
    }
}
```

没有其它方法，也不增加 `title` 参数。不接收 `Date`，不读 `lastUpdated`、`lastDateNow`、TTL、stale、`risingOnly`，不 append，不沿用上一笔非 `nil`。`sampleCount` 由调用方传入当前这条 `samples.count`。函数不修改序列。方向标题不进这个类型；`unavailable` 仍是上面这一句。

`Package.swift` 的 SamplingCore `sources` 加入 `"Models/HistoryCurvePresentation.swift"`。`exclude` 里的 `Views/`、`ViewModels/` 保持，这样 wrapper 和总览视图不会进 Linux 包。

Xcode 另登记这一个新模型文件，沿 `TopAppLocation.swift` 的四处：PBXBuildFile、PBXFileReference、Models group、Sources。`SharedUI.swift` 已在目标里，wrapper 写进该文件，不为 wrapper 再加一个 Swift 文件，也不为它新增 pbxproj 行。

## 视图候选

`SharedUI.swift` 在 `SparklineChart` 之外新增：

```swift
struct HistoryAnnotatedChart<Content: View>: View {
    let annotation: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .topLeading) {
                if let annotation {
                    Text(annotation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 5)
                        .padding(.leading, 5)
                }
            }
    }
}
```

`annotation == nil` 时没有 `Text`，content 就是原来的图。非 `nil` 时只多这一行字。

已锁的视觉候选是：原图帧里面的一行小字。供实现期照抄进源码。Mac 上的实际 overlay 没有跑过，因此不承诺这行字不会挡住轴、刻度或曲线。

- 字在图表帧内部左上，上、左各 5pt。5pt 是锁死的字面量。
- 一行「历史曲线 · 当前值暂不可用」，`.caption2`，`.secondary`，`.lineLimit(1)`，`.truncationMode(.tail)`。窄窗可以截断。完整方向和完整句在父级 accessibility label 里，不为截断加展开或跳转。
- 左侧大数和副行不在这张图的 frame 里。CPU ready 里它们在宽 200 的左栏（64–75 行），`chart` 是旁边的 `.frame(maxWidth: .infinity, maxHeight: .infinity)`（77–78 行）。网络卡和磁盘卡的左栏宽 168（113–124 行），`chart` 同样是 `.frame(maxWidth: .infinity, maxHeight: .infinity)`（126–127 行）。overlay 只挂在包住 `SparklineChart` 的那一层，不挪火花线，也不改 `chartXAxis`、`chartYAxis`、`formatY`、`domain`。
- 不加胶囊、底条、警示色、额外空行、`animation`、`transition`。不为说明预留一块新布局，也不改轴来腾地方。
- wrapper 不给 content 设 `opacity`，也不加 `allowsHitTesting` 或其它本文没写的交互。`SparklineChart` 正文里已有的面积和轴透明度保持原样。

`SparklineChart` 的类型定义不出现 `annotation`，也不调用 `HistoryCurvePresentation`。内存用量、压力、侧栏 `seriesBlock` 继续直接调用四参数的 `SparklineChart`。

## 无障碍候选

三处 ready 的 `.accessibilityElement(children: .ignore)` 留在原地：CPU 在单卡上（82 行），网络和磁盘在两张卡的父级 `HStack` 上（65 行）。不拆成两张卡各自的 accessibility 元素，也不在被 ignore 的子卡上再挂一套 label。sampling 仍是 `.combine` 加原来的采样标签。failed 不改。overlay 上的 `Text` 不加自己的 `accessibilityLabel`。图上的字仍是裸的 `HistoryCurvePresentation.unavailable`，不加方向标题，也不为截断加展开或跳转。

屏幕上的 overlay 可以单行截断。VoiceOver 用的是**现有**那条父级 label，里面要有方向和完整句，不能只重复无方向的 note，也不能只靠 `overviewLine` 里的「—」让人反推是哪一路。

`note` 就是该侧 `annotation(current:sampleCount:)` 的返回值，字面量仍是「历史曲线 · 当前值暂不可用」。方向标题用已经存在的常量：`NetworkPageCopy.inboundTitle` / `outboundTitle`（「下行」/「上行」，`NetworkPage.swift` 49–50 行），`DiskPageCopy.readTitle` / `writeTitle`（「读取」/「写入」，`DiskPage.swift` 22–23 行）。

总览文件里可以有一个不持久的私有投影，只服务这条 label。它不进 SamplingCore，不是 VM 状态，也不拿去喂 `HistoryAnnotatedChart`：

```swift
private func directedHistoryNote(title: String, current: Double?, sampleCount: Int) -> String? {
    guard let note = HistoryCurvePresentation.annotation(current: current, sampleCount: sampleCount) else {
        return nil
    }
    return "\(title) · \(note)"
}
```

谓词仍是这一次调用自己的 `current == nil && sampleCount >= 2`。父级不用「任一侧 nil」去决定视觉 overlay。

- CPU 不用这个投影。`annotation(current: vm.systemCpuPercent, sampleCount: vm.cpuHistory.samples.count)` 为 `nil` 时，标签仍等于 `overviewLine`。非 `nil` 时为 `"\(overviewLine)，\(note)"`。
- 网络父级按下行、上行各算一次。下行的 current 是 `vm.hostNetworkRates.inboundBytesPerSecond`，sampleCount 是 `vm.networkHistory.inbound.samples.count`，标题是 `inboundTitle`。上行的 current 是 `outboundBytesPerSecond`，sampleCount 是 `networkHistory.outbound.samples.count`，标题是 `outboundTitle`。命中才得到「下行 · \(note)」或「上行 · \(note)」。一次都没有命中时，标签仍是 `overviewLine`。只有一侧命中时只追加该侧这一条。两侧都命中时按下行然后上行追加两条，片段之间以及和 `overviewLine` 之间用 `，`。
- 磁盘同样，顺序是读取然后写入。读取的 current 是 `vm.hostDiskRates.readBytesPerSecond`，sampleCount 是 `vm.diskHistory.read.samples.count`，标题是 `readTitle`。写入的 current 是 `writeBytesPerSecond`，sampleCount 是 `diskHistory.write.samples.count`，标题是 `writeTitle`。

因此：

- 该侧 current 为真实 `0` 或其它非 `nil`，或该侧样本数是 0 或 1：该侧 `annotation` 为 `nil`，label 里不出现该侧的「标题 · note」。另一侧是否命中不影响这一侧。
- 仅下行命中：label 含「下行 · 历史曲线 · 当前值暂不可用」，不含「上行 · 历史曲线 · 当前值暂不可用」。仅读取命中时同理，只有读取那一条。
- 仅上行或仅写入命中：只有该侧这一条。
- 两侧都命中：按下行然后上行（读取然后写入）各追加一条带标题的片段，例如「下行 · 历史曲线 · 当前值暂不可用」然后「上行 · 历史曲线 · 当前值暂不可用」。方向已经写在标题里。这不是未决项，也不是把无方向的 note 原样重复两遍。
- 图表 overlay 仍是每张卡自己的裸 note。父级 `HStack` 不另画字。

分隔符用现有 sampling 标签里的全角逗号 `，`。

## 采样与环（不改）

标注不写样本。append 仍只发生在现有 `record`：

- 值与 `date` 都非 `nil`，且 `date` 不等于 `samples.last?.date` 时，这次 `record` append。
- 值是 `nil`，或 `date` 是 `nil`：不 append，已有点还在。
- 日期与末点相同：不 append，不替换末点。当前值赋值在 `applySample` 里位于 `record` 之前，所以同一 `capturedAt` 可以已经把大数写成新的非 `nil`，而序列长度不变。标注只看这次传入的 Optional 和 count，不把这种情况再标成暂不可用。
- 默认 `limit` 仍是 90。`count > limit` 时仍 `removeFirst(count - limit)`。

接受且成功的帧在同一次 `applySample` 里写当前值并 `record`。不是标注层再延迟一帧，也不新造时钟。失败与未接受的 flight 仍不 `record`、不 `reset`。`UsageHistory` 的 `nil` 清环不改。

## 明确不做

- 不改 `SystemCPUHistory`、`SystemNetworkHistory`、`SystemDiskHistory`、`UsageHistory`、`ChartSample`、`HostNetworkRates`、`HostDiskRates` 的存储和 `record`
- 不改 `MemorySampler`、主机 reader、`SamplingPace`、`SamplingRetryApply`、`LoadState`
- 不把 `nil` 当前值变成失败，不在 sampling / failed 画这句
- 不新增 `@Published`、`didSet`、`@MainActor`，不改 `sortedRows`、`locateMemoryTopApp`、`topAppLocateReveal`、`filter`、`menuBarPopover`
- 不改 `cpuPhase`、进程表、名称过滤、「仅上涨」、排序、退出、冻结详情
- 不改内存总览、压力曲线、进程内存曲线、进程 CPU 曲线、资源侧栏网络 / 磁盘详情
- 不给 `SparklineChart` 加 annotation 参数或默认值。视觉 overlay 不加方向标题。无障碍拼接留在总览视图的私有投影里，不放进 SamplingCore 或 VM，也不给 `HistoryCurvePresentation` 增加 `unavailableCaption` 或其它字段
- 不拆 ready 的无障碍元素，不去掉父级 `children: .ignore`，不在被 ignore 的子卡上再挂一套 label
- 不改环长度、采样周期、轴、`formatY`、placeholder 文案，也不新加 end marker、gap 标记、预留布局或 `allowsHitTesting`
- 标注函数只有 `current == nil` 与 `sampleCount >= 2` 这一道门，不另加数值分类
- 不改公证脚本与 entitlements
- 本设计 PR 不改根 `README.md` 的期次索引。十九、二十期设计曾在那里加半句；本期任务只改 `docs/TECH.md`

## 实施时的文件

实现 PR 才动这些文件。本设计 PR 不动。

| 文件 | 改动 |
| --- | --- |
| `Pulse/Models/HistoryCurvePresentation.swift` | 新的纯函数 |
| `Package.swift` | `sources` 加这一行。不把 `Views/` 放进包 |
| `project.pbxproj` | 只为这个新模型做与 `TopAppLocation.swift` 相同的四处登记 |
| `Pulse/Views/SharedUI.swift` | 新增 `HistoryAnnotatedChart`。`SparklineChart` 定义不改 |
| `Pulse/Views/CPUOverviewSection.swift` | 仅 `chart` 的 `else`，以及 ready 的 label 字符串 |
| `Pulse/Views/NetworkOverviewSection.swift` | `NetworkRateCard.chart` 的 `else` 仍把裸 `annotation(current: rate, sampleCount: samples.count)` 交给 wrapper。ready 父级 label 只在该侧命中时追加 `inboundTitle` / `outboundTitle` 加 ` · ` 加同一次 note |
| `Pulse/Views/DiskOverviewSection.swift` | 与网络同形。视觉仍用该卡 `rate` / `samples` 的裸 note。label 用 `readTitle` / `writeTitle` |
| 新测试 | 纯模型与源码接线分开，见下节 |

`MemoryDashboardVM.swift`、`OverviewSection.swift`、`OverviewCards.swift`、`ProcessTablePane.swift`、`ProcessDetailSidebar.swift`、`TopAppLocation.swift` 不改。

## 测试矩阵（设计；本 PR 不写、不跑）

实现 PR 的红必须是真的失败。本环境没有执行 `swift test`。不要把本节写成已经绿了。

**红：** 生产还没有 `HistoryCurvePresentation` 时，`HistoryCurvePresentationTests` 直接调用 `annotation`。失败应是编译错误。禁止在测试里复制一份同名 enum，禁止 `XCTFail` 占位，禁止改松旧断言。类型进 SamplingCore 之后，`HistoryCurveWiringSourceTests` 在调用点、wrapper、`Package.swift` sources、pbxproj 四处还没齐时断言失败。

**绿：** 补上纯函数、包清单、Xcode 四处、wrapper 和五条 `else`，使这些测试通过，再跑全量 `swift test`。实现 PR 留下真实日志。本设计 PR 没有这些数字。

纯模型测试调用真实的 `SystemCPUHistory` / `SystemNetworkHistory` / `SystemDiskHistory.record`，再把**这次**的 current 和 `samples.count` 交给 `annotation`。日期只用 `Date(timeIntervalSince1970:)`。不调用 `Date()` 或 `Date.now`，不新增时钟类型。不实例化 `MemoryDashboardVM`。

CPU（默认 `limit` 90，除非某条要显式写另一个 limit；下面的 90 用默认值）：

1. `record(nil)` 在空环上：count 仍是 0，`annotation(nil, 0) == nil`。
2. 一个非 `nil` 之后再 `record(nil)`：count 仍是 1，`annotation(nil, 1) == nil`。
3. 两个不同日期的非 `nil`，再 `record(nil)`：count 仍是 2，`annotation` 等于 `unavailable`。
4. 90 个不同日期的非 `nil`，再在新日期 `record(nil)`：count 仍是 90，`annotation` 等于 `unavailable`。序列没有被 `nil` 截短。
5. 真实 `0` 且 count `>= 2`：`annotation` 为 `nil`。一个正值且 count `>= 2`：同样为 `nil`。
6. 先走到 3 的「nil 且 count 为 2」，再在新日期 `record(0)`：count 增加，把 current 传 `0` 时 `annotation` 为 `nil`。再 `record` 一个正值，同样为 `nil`。然后再 `record(nil)`：count 不变且仍 `>= 2`，说明回到 `unavailable`。
7. 同一 `date` 连续 `record` 两个不同的非 `nil`：count 不增加，末点仍是第一次的值。`annotation` 不负责 append。随后同日期 `record(nil)`：count 仍不变。
8. `record(percent:at:)` 的 `date` 为 `nil`：count 不变。
9. 91 个不同日期的非 `nil`：count 仍是 90，最旧的点被去掉。最后这个非 `nil` current 的 `annotation` 为 `nil`。这是原环，不是新规则。

网络，用 `SystemNetworkHistory.record(rates:at:)`。磁盘用 `SystemDiskHistory`，读/写对偶。每组都做正反两套，断言两侧的 count 和 `annotation`：

- 先让两侧都有样本，再一帧「本侧 `nil`、对侧 `0`」：`nil` 侧 count 不变，对侧因为 `0` 非 `nil` 且日期是新的而增加。`annotation(nil, nil侧count)` 在 count `>= 2` 时为 `unavailable`。`annotation(0, 对侧count)` 为 `nil`。对侧样本值不被写成 `nil`。
- 反过来：本侧 `0`、对侧 `nil`。只有 `nil` 侧可以出现说明。
- 本侧 `nil` 且 count 已 `>= 2`，对侧为正值：只有 `nil` 侧返回文案。
- 本侧从 `nil` 恢复为 `0`，以及另一次恢复为正值：该侧 `annotation` 变为 `nil`，对侧序列不被这次恢复改写其已有策略（对侧该帧若也是非 `nil` 且日期新，只按原 `record` append；对侧若是 `nil`，对侧 count 不变）。

已有的三条 `SkipsNil` 测试和两条「ready 的 nil 主机速率不是失败」保持原断言，不放宽，也不把它们改成标注测试。

源码接线测试只读文本，风格与 `TopAppLocationWiringSourceTests` 相同。通过不等于 SwiftUI 跑过，也不等于 `@MainActor` 上跑过 VM。

- `Package.swift` 的 `sources` 含 `"Models/HistoryCurvePresentation.swift"`，且不含 `HistoryAnnotatedChart`、不含 `SharedUI.swift`。`exclude` 仍含 `Views` 与 `ViewModels`。
- `project.pbxproj` 里 `HistoryCurvePresentation.swift` 出现在 PBXBuildFile、PBXFileReference、Models group、Sources。不为 `HistoryAnnotatedChart.swift` 新增文件引用。
- 源码断言分开取 `struct HistoryAnnotatedChart` 的类型正文和 `struct SparklineChart` 的类型正文。禁止对整个 `SharedUI.swift` 断言「没有 `opacity`」：`PulsePalette.hairline`（22 行）和 `ResourceTabs`（86 行）等处已经有 `Color.white.opacity`。`SparklineChart` 正文保持现有的 `tint.opacity(0.42)`、`tint.opacity(0.02)`、轴标签 `Color.white.opacity(0.42)`、网格 `Color.white.opacity(0.06)`，轴标记 `chartXAxis` / `chartYAxis` 仍留在这个正文里，并且这个正文不含 `annotation` 与 `HistoryCurvePresentation`。`HistoryAnnotatedChart` 正文含 `overlay(alignment: .topLeading)`、`.font(.caption2)`、`.foregroundStyle(.secondary)`、`.lineLimit(1)`、`.truncationMode(.tail)`、`.padding(.top, 5)`、`.padding(.leading, 5)`。这个正文不含 `chartXAxis`、`chartYAxis`、`accessibilityLabel`、`allowsHitTesting`、`animation`、`transition`，也不给 content 加 `.opacity`。`disabledTab` 已有 `.allowsHitTesting(false)`（123 行），`ResourceTabs` 也已有 `accessibilityLabel`（114、124 行），这两条缺失断言同样不能扫整个文件。
- CPU 文件：`HistoryAnnotatedChart` 一处，位于 `chart` 的 `else`。该处 `annotation(current: vm.systemCpuPercent, sampleCount: vm.cpuHistory.samples.count)`，其内 `SparklineChart` 的 `samples` 仍是 `vm.cpuHistory.samples`。`count < 2` 分支仍是 `ChartPlaceholder(text: "曲线采集中")`，且该分支不含 wrapper。`samplingBody` 与 `failureBody` 不含这两个新类型。ready 仍是 `children: .ignore`。ready 标签在 note 为 `nil` 时走 `overviewLine`，非 `nil` 时拼接 `，` 与这条 note，不加第二套方向前缀。
- 网络文件：`readyBody` 仍把 `inboundBytesPerSecond` 配 `networkHistory.inbound.samples`、`outboundBytesPerSecond` 配 `networkHistory.outbound.samples`。`NetworkRateCard` 正文不含 `hostNetworkRates` 与 `networkHistory`；它的 `else` 只有一处裸的 `annotation(current: rate, sampleCount: samples.count)` 和一处 `HistoryAnnotatedChart`，overlay 不加 `inboundTitle`。`readyBody` 不含 `HistoryAnnotatedChart`。placeholder 仍是 `NetworkPageCopy.chartCollecting`。父级 label 的投影按下行、上行各调用一次：`annotation(current: vm.hostNetworkRates.inboundBytesPerSecond, sampleCount: vm.networkHistory.inbound.samples.count)` 配 `inboundTitle`，然后才是 `annotation(current: vm.hostNetworkRates.outboundBytesPerSecond, sampleCount: vm.networkHistory.outbound.samples.count)` 配 `outboundTitle`。命中片段是 `"\(title) · \(note)"`。没有命中则标签等于 `overviewLine`。禁止用「历史曲线 · 当前值暂不可用」出现 1 次或 2 次代替方向验收，也不要把「双 nil 是否重复无方向的同一句」留成开放断言。单侧只有该侧标题接在 note 前；双侧是「下行 · note」然后「上行 · note」。sampling / failed 不含新类型。`children: .ignore` 仍在父级。
- 磁盘文件：`DiskRateCard` 的 `else` 仍是裸的 `annotation(current: rate, sampleCount: samples.count)`，`readyBody` 不含 `HistoryAnnotatedChart`。父级传入仍是 `readBytesPerSecond` 配 `diskHistory.read.samples`、`writeBytesPerSecond` 配 `diskHistory.write.samples`。placeholder 仍是 `DiskPageCopy.chartCollecting`。父级 label 先 `annotation(current: vm.hostDiskRates.readBytesPerSecond, sampleCount: vm.diskHistory.read.samples.count)` 配 `readTitle`，再 `annotation(current: vm.hostDiskRates.writeBytesPerSecond, sampleCount: vm.diskHistory.write.samples.count)` 配 `writeTitle`。命中片段同样是 `"\(title) · \(note)"`。单侧只有「读取 · note」或「写入 · note」；双侧是读取然后写入。禁止用 note 的出现次数代替方向，也不把双 nil 留成无方向重复。`children: .ignore` 仍在父级。
- `OverviewCards.swift`、`ProcessDetailSidebar.swift`、`OverviewSection.swift`、`ProcessTablePane.swift`、`MemoryDashboardVM.swift`、`TopAppLocation.swift`、`ResourceDetailPageProjection.swift` 不含 `HistoryCurvePresentation`、`HistoryAnnotatedChart` 和完整句 `历史曲线 · 当前值暂不可用`。侧栏 `seriesBlock` 里的调用仍是 `SparklineChart(samples: samples, tint: tint, domain: domain, formatY: formatY)`。
- `MemoryDashboardVM.swift` 的 `@Published` 仍是 23，`didSet` 仍是 2，`@MainActor` 仍是 1。`sortedRows` 那一行无 `@Published`，函数体仍是 `tableSort.ordered(visibleRows)`。`locateMemoryTopApp` 仍在 `guard let plan` 之后写 filter（仅 replace）、`risingOnlyFilter = false`、`selectPidIfPresent`、`topAppLocateReveal`。上述六份已经写着 23 的源码测试不要改期望值。
- `ProcessTablePane` 仍有 `cpuPhase`，其函数体仍含 `CPUPagePhaseResolver.resolve`，`resourceTableBody` 仍 `switch cpuPhase`。不要用「出现 `cpuPhase`」或子串「暂不可用」判定二十一期漏标或误标。进程表的判据是类型名 `HistoryCurvePresentation` 不出现。`row.networkAvailability.label` 保持原样。
- `HistoryCurvePresentation` 只有 `unavailable` 与 `annotation(current:sampleCount:)`。没有 `unavailableCaption`，也没有 `title` 参数。`Package.swift` 的 sources 不收录总览视图。

## 风险

| 风险 | 应对 |
| --- | --- |
| 给 `SparklineChart` 加一个默认 `annotation: nil`，内存和进程曲线被静默接上 | 不改该类型的参数。只有五条 `else` 显式包 wrapper |
| 在父级 `HStack` 上按「任一侧 nil」画一句，或两句叠在同一张图上 | 图的 overlay 在每张卡自己的 `chart` `else`，文字是裸 note。父级仍是原来那一个 `children: .ignore`，label 里命中侧才追加「标题 · note」 |
| 父级 label 只重复无方向的 note，或把「双 nil 是否重复同一句」留成未决 | 每一侧先独立 `annotation(current:sampleCount:)`，只收集非 nil 的方向。一侧是「下行 · note」或「读取 · note」。双侧按下行→上行或读取→写入各一条，标题不同。真实 `0` 不进入 |
| 拆掉父级 ignore，或给 presenter 加 `unavailableCaption` | 不拆无障碍结构。方向只在视图私有投影里拼。`annotation` 的返回值不变 |
| 一侧 `nil` 把对侧 `0` 也标上，或对侧 `0` 把本侧说明吃掉 | 两次独立的 `annotation` 调用。`0` 不是 `nil` |
| 样本 0/1 仍画火花线，或在 placeholder 上写这句 | `count < 2` 分支不改。函数在 count `< 2` 时返回 `nil` |
| 用时钟、上一笔非 `nil`、或新 `@Published` 做「过期」 | 函数只有 current 与 sampleCount |
| 恢复非 `nil` 留着说明，或加退场动画 | 非 `nil` 返回 `nil`，`if let` 不生成 `Text`。不加 `animation` / `transition` |
| 把曲线透明度降下来给字让位 | `HistoryAnnotatedChart` 正文不给 content 加 `.opacity`。`SparklineChart` 正文里原有的 opacity 保留。不断言整个 `SharedUI.swift` 没有 `opacity` |
| 为小字改轴、挪火花线，或预留一块新布局 | overlay 留在原图帧内。轴、`formatY`、`domain` 不改。不加 `allowsHitTesting` |
| 失败页也画这句，或把 `nil` 收成 `loadState == .failed` | sampling / failed 不含新类型。现有「nil 速率仍是 ready」测试不放宽 |
| 为接线去改 `record`、清环或补 0 | `record` 函数体不改。`nil` 仍不 append |
| 二十一期把 `@Published` 加到 24，或去改二十期的 23 | 不新增发布属性。六份现有计数测试保持 23 |
| 顺手改 `cpuPhase`，或用子串「暂不可用」、note 的出现次数扫进程表 | 进程表不改。判据是 `HistoryCurvePresentation` 不出现 |
| 把源码接线或方向字符串说成 Mac 已看过 overlay，或 VoiceOver 已读出 | 下节。方向结构可以在 Linux 上读源码核对 |

## 验收

- [ ] 五条映射与上表一致。`NetworkRateCard` / `DiskRateCard` 的图表 `else` 只把自己的 `rate` 和 `samples` 交给 `annotation`。父级传入的字段是 `*BytesPerSecond` 与同方向 `.samples`。没有总览级的统一门
- [ ] `annotation` 仅在 `current == nil && sampleCount >= 2` 时返回 `历史曲线 · 当前值暂不可用`，否则 `nil`。真实 `0` 与正值不返回文案。一侧的结果不写入另一侧
- [ ] 样本 0/1 仍是原来的 `ChartPlaceholder` 文案（CPU 与网络是「曲线采集中」，磁盘是「正在采样…」）。不画假线
- [ ] wrapper 只包这五条曲线的 ready 图表 `else`：CPU 一处源码，`NetworkRateCard.chart` 一处源码（下行、上行各实例化一次），`DiskRateCard.chart` 一处源码（读取、写入同样）。父级 `HStack` 不再包一层图。`SparklineChart` 仍是原来的四参数，samples 实参不变。`domain`、轴、`formatY`、大数和副行不改
- [ ] 视觉是原图帧内的小字：左上 5pt、`.caption2`、`.secondary`、`.lineLimit(1)`、`.truncationMode(.tail)`。左侧读数在另一栏，不在图 frame 里。overlay 不挪火花线，轴与 `domain` 不变。不预留新布局，不加 `allowsHitTesting`。不承诺小字不会挡住轴或曲线。Mac 上的 overlay 未验
- [ ] ready 的 `children: .ignore` 仍在原处，不拆子卡 label。CPU 在 annotation 非 nil 时仍是 `overviewLine` 加一条 note。网络和磁盘先对每一侧独立 `annotation(current: 该侧 rate, sampleCount: 该侧 samples.count)`，只把非 nil 的方向写入父级 label：一侧是「下行 · 历史曲线 · 当前值暂不可用」或「读取 · 历史曲线 · 当前值暂不可用」；双侧按下行→上行或读取→写入各一条，标题不同。真实 `0` 和其它非 nil 不进入。不靠 `overviewLine` 的「—」推断，也不因任一侧 nil 就把两侧都标上。0/1 点不追加。sampling / failed 不追加。视觉 overlay 仍是无方向的 note
- [ ] `record` 的 nil 跳过、同日期跳过、默认 90 环不改。标注不 append。失败与未接受的 flight 仍不 `record`、不 `reset`
- [ ] `@Published` 仍是 23，`didSet` 仍是 2，`@MainActor` 仍是 1。`sortedRows`、`locateMemoryTopApp`、过滤、菜单栏、`cpuPhase`、退出、冻结、资源侧栏和其它火花线无新注解、无新参数
- [ ] 实现 PR 先有编译失败的模型红，再有源码接线红，然后有 Linux 上这两类测试和全量 `swift test` 的真实日志。这些日志不是 SwiftUI 运行，也不是 Xcode 已编译

## Linux 已测与未验

本 PR 不跑测试。实现 PR 在 Linux 上能执行的是 SamplingCore 里的 `HistoryCurvePresentation.annotation`，以及三份 history 的 `record`。`HistoryAnnotatedChart`、三份总览和 `MemoryDashboardVM` 不在这个目标里。wrapper 文案、五处实参和无障碍字符串用源码阅读断言。那份阅读不证明 MainActor 上跑过 VM，也不证明 SwiftUI 画过 overlay。

未验，不挡本设计合并，实现 PR 在 Linux 上也不能把它们勾成已过：

- Mac 上当前值真实为 `nil` 时，旧线是否仍在；图内小字是否挡住轴、刻度或曲线。本文不把「不遮挡」写成已成立
- 单行截断、大字体、对比度。VoiceOver 是否真的读出「方向标题 + 历史曲线 · 当前值暂不可用」。方向对不对可以在 Linux 上用源码接线核对调用顺序和 `"\(title) · \(note)"`，这不等于 VoiceOver 已经读过
- 恢复非 `nil`（含 `0`）时是否无闪跳、无动画
- 切换 CPU / 网络 / 磁盘 / 内存 Tab 之后说明是否随 ready 视图离开
- Xcode 编译 App，以及 `project.pbxproj` 下的实际运行
- 本设计 PR 没有 Mac 日志

实现等本设计合并 + Grok merge gate 后再写 Swift。本 PR 不写 Swift、不写测试、不合并。

## 设计候选、产品锁、技术 PASS

三件事分开，本文只完成第一件的书面候选：

| | 本文 | 还没发生 |
| --- | --- | --- |
| 设计候选 | 上文的谓词、裸文案、图内 5pt 小字、`.truncationMode(.tail)`、五条独立映射、父级 label 的「方向标题 · 同一条 annotation」 | — |
| 产品范围 | 已交产品范围评审。5pt 与父级 label 的方向片段按本文写死。整节仍不是 Mac 视觉终验 | 实现仍未开 |
| 技术 PASS | 未发生。没有 `swift test` 计数，没有 Xcode 构建，没有 Mac 截图或 VoiceOver 记录 | 实现 PR 的 Linux 日志，以及未验清单里的 Mac 项 |

## 未决

5pt 与父级 label 的方向都已经写死，不在这里再选。

方向的做法是：网络、磁盘每一侧先独立调用同一个 `annotation(current: 该侧 rate, sampleCount: 该侧 samples.count)`，只收集返回非 nil 的方向。一侧命中写成「下行 · 历史曲线 · 当前值暂不可用」（磁盘是「读取 · 历史曲线 · 当前值暂不可用」）。双侧命中按下行然后上行（读取然后写入）各写一条，标题不同。真实 `0` 和其它非 nil 不进入这份列表。不读取 `overviewLine` 里的「—」来决定，也不因为任一侧是 nil 就把两侧都标上。CPU 仍是 `overviewLine` 加一条 note。ready 父级保持 `children: .ignore`，不拆成子卡。没有新的发布属性，也没有时间语义。

仍不在本期改口的是：同一 `capturedAt` 只更新当前值、`record` 不 append 时，不为这个状态另写文案。根 `README.md` 的期次索引不加二十一期。Mac 上小字是否压住轴或曲线、VoiceOver 是否真读出这些带方向的句子，是未验，不是文案还没选定。
