# 保存当前快照：技术设计（未实现）

> 评审中的技术设计。不是产品 PASS，不是实现授权，也不是 `main` 上的行为。
>
> 对照提交 `930bac1eeab468bc9de677581c233199b6f1f9c9`（`origin/main`）。开写前读过 PRD、TECH、ADR-0001、ADR-0002、当时的 open PR（没有），以及下面点名的源码。open PR 和现有规格里没有另一份「保存当前快照」设计。规格里已有的「快照」是采样帧 `MemorySnapshot` / `SampledFrame`，不是用户保存的现场。
>
> 文件名的 `31` 只用来接在 `00`–`22` 之后，并避开已经落地、没有单独设计稿的二十三至三十期。这不是三十一期立项。
>
> 本文件不改采样、过滤、排序、退出或其它页的现有行为。预览、隐藏进程名只在讨论里出现过，不是已锁定的 Must，本文不把它们收进范围。

## 讨论已经限定

这些来自方向讨论，技术设计照此收口。产品没有另发 PASS。

- 做的是手动「保存当前快照」：把点击时已经发布的采样留在本机，并能重新打开这一份现场。用来看当时的资源读数和主要进程。
- 不做能追溯卡顿之前的录制器。不新增事前历史缓存，不连续录制，不做自动归因或泄漏判断，不上传，不做跨快照比较，不做历史列表或历史库。
- 不改采样节奏（前台约 1.5 秒、后台约 3 秒）、过滤、排序、退出，以及各页既有行为。
- 只用点击时已经发布的数据。不为保存再跑 `MemorySampler.sample()`，也不另开 `proc_listpids`、IOKit、本机页那次读取。
- 缺失保持缺失。不把缺失写成 0。真实 0 仍是 0。
- 多个读取时刻不能写成「同一瞬间」。文件要带上真实的采样时间；没有采样时间的数据不要并进那个时间。
- 进程名和可执行路径是隐私数据。字段从现有发布值里取最小集合。路径、包标识这类非必要敏感字段不进默认文件。尚未选定的身份字段交给产品，不在这里定死。
- 不新建历史存储框架，也不做版本迁移框架。读不懂的版本直接拒绝。

## 还要产品或设计锁定

下面几项会改变保存内容和界面。本文只列候选，不替产品选定，也不把建议写成范围。

| 编号 | 候选 | 说明 |
| --- | --- | --- |
| P1 | 未过滤的全部 `rows`，元素含显示名 | 集合是采样器发布的完整进程表 |
| P2 | 与 P1 相同的行，但不写 `name` | 回看只能看见 pid。这是「隐藏进程名」的一种做法，讨论里提过，不是 Must |
| P3 | 按已发布顺序取前 N 行，元素含显示名 | N 未定。菜单栏 Top3 的 `MenuBarPopoverShell.maxProcessRows`（3）只是现成常数，不是这个 N |
| Q1 | 进程元素只有 pid、内存、内存来源、CPU%、线程，以及 P1/P3 的名称 | 建议中的最小列，仍等确认 |
| Q2 | 在 Q1 上加上该行已有的磁盘读/写速率、能耗瓦特、唤醒 | 值已经在 `ProcessRow` 上，保存时不用再读。`nil` 继续是 `nil` |
| R0 | schema 1 不写任何曲线 | 技术建议。避免把最多 90 点的窗口写成一份「当时」 |
| R1 | 另立 schema 2，只整份拷贝屏幕上已经有的环 | 不补点、不新采样。选定 R1 之前不要实现；选定后本文的 schema 1 不能偷偷加可选大数组 |
| I1 | 「文件」菜单打开系统保存面板 | 捕获发生在点菜单时，面板只负责路径 |
| I2 | 工具栏按钮，面板相同 | 与 I1 二选一。不用同时做两个入口 |
| V1 | 主窗上的只读 sheet | 不替换正在采样的页面 |
| V2 | 单独的只读窗口 | 同样不写入唯一 VM |
| E1 | 还没有 `snapshot` 时拒绝保存 | 技术建议。没有可标明的采样时间 |
| E2 | 写成一份主机块为空的文件 | 只在产品明确要求「把这次没有采样也留下」时才做 |

不设「保存当前屏幕这张已过滤、已按 App 合并的表」这个候选。`sortedRows` 会把名称过滤、仅上涨、仅窗口 App 和 `AppGroupProjection` 烤进文件，合并行只留下内存最大的那个 pid。那不是一帧采样。

权限脚注也不进 schema 1。VM 上只有已经拼好的 `processPermissionFootnote` 句子，没有单独的拒绝计数。要保留 N，得另做产品决定，不能从句子里反解。

按钮、面板默认文件名、回看标题、失败句和「这是较早一次采样」的说明都还没有文案锁定。实现时沿用现有冷静语气：缺失用「—」或「暂时读不到」，不写「危险 / 泄漏」。本文不提供可直接粘贴的终稿句子。

## 今天数据在谁手里

`930bac1` 上只有一条采样通路。

```
MemorySampler.sample()（actor）
        │ 一次调用产出不可变 SampledFrame
        ▼
MemoryDashboardVM.applySample（@MainActor，唯一 VM）
        │ 只有被 SamplingRequestGate.accept 的成功帧才改下面这些发布值
        ├─ snapshot / systemCpuPercent / busiestCorePercent
        ├─ hostNetworkRates / hostDiskRates / rows
        ├─ processListFailed / processPermissionFootnote / topMemorySeries
        └─ usageHistory、cpuHistory、networkHistory、diskHistory 各 append 一次
失败的已接受帧只把 samplingFailed 设为 true，不改上面的数，也不清曲线。
未接受的 flight 不写这些字段。
```

保存要读的是这份已经发布的 VM 状态，不是 actor 里面的私有缓存。`MemorySampler` 的 `cpuTicks`、`diskTicks`、`energyTicks`、`previousHostCPU`、`previousHostNetwork`、`previousHostDisk`、`selectedMemorySeries`、`selectedCPUSeries` 都没有公开 getter。保存路径不 `await sampler`。

`detail` 只在有选中 pid 且该 pid 仍在本帧 `rows` 里时出现，序列也只属于这个 pid。`topMemorySeries` 最多 5 个 pid 的内存点。二者都不是「全部进程的曲线」。

另外两条时钟不在这一帧里：

- `thermalNotice`：`ProcessInfo.thermalStateDidChangeNotification` 到达时改写，没有 `capturedAt`。总览在读它，菜单栏不读。
- `machineFacts`：只有本机页开着才由 `HostMachineReader.read()` 填写，之后每 30 秒一次。类型上没有采样时间。从未打开本机页时是 `nil`。本机页上的 CPU、内存、交换和曲线仍然来自采样器，不来自这次读取。

菜单栏轻量条是 `MenuBarPopoverSnapshot.project` 的只读投影。`samplingFailed == true` 时，它把压力和已用内存收成 `nil`，进程行却仍可能留着上一帧。保存不能走这个投影，否则会把「上一帧还在，本轮失败」写成「主机数缺失」。

## 为什么不是同一瞬间

`MemorySampler.sample()` 在主机内存读取成功之后才取 `capturedAt = Date()`（`MemorySampler.swift`）。随后仍在同一次调用里顺序发生：

1. 把压力点追加进 `pressureSeries`，标签是这个 `capturedAt`。
2. `SwapUsageReader.read()`。失败则 `swapUsedBytes == nil`，成功的 `0` 是空交换文件。
3. 整机 CPU、最忙一核。两帧 tick 求差。第一帧、读失败、核数变化都是 `nil`。这次读取自己没有单独的 `Date`。
4. 主机网络、主机磁盘。传进 reader 的时间是上面的 `capturedAt`，不是读到计数器时再取的钟。速率是相邻两帧计数差除以两个 `capturedAt` 的间隔。第一帧、失败、回绕是 `nil`。真实 0 速率可以出现。
5. `proc_listpids`，再对每个 pid 做 `proc_pidinfo`、`proc_pidpath` 和一次 `proc_pid_rusage`（`rusage_info_v6`）。进程 CPU、磁盘、能耗、唤醒的速率分母用的也是这个 `capturedAt`，计数器是在这之后读的。

因此一帧 `SampledFrame` 是一次已接受采样的发布单位，不是一个物理瞬间。速率是以 `capturedAt` 为末端标签的区间值。进程表比 `capturedAt` 更晚才读完。交换和内存共用这个标签，但交换是下一次 sysctl，可以单独缺失。

失败时 VM 继续显示上一份成功帧，`snapshot.capturedAt` 不变，`samplingFailed == true`。点击时刻的 `Date()` 只表示用户何时要求保存，不能拿来替换 `capturedAt`。

进程列表整帧失败时，这一帧仍是成功：主机块是新的，`rows` 被换成空数组，`processListFailed == true`。保存必须沿用这个空表，不能把上一帧的进程补回来。

`rows` 只在 `applySample` 的成功分支被赋值为 `frame.rows`。采样器在返回前按内存占用降序、pid 升序排好。过滤和按 App 合并不改这份数组。

## 已有的环不能当成现场

| 环 | 所有者 | 今天怎么长 | 和单次现场的关系 |
| --- | --- | --- | --- |
| `snapshot.pressureSeries` | 采样器，随快照发布 | 每次主机内存成功追加 `pressureMetric`（已用比例），最多 90 点 | 多时刻。schema 1 不写 |
| `usageHistory` | VM | 已接受成功帧用 `snapshot.capturedAt` 追加已用字节。`record(nil)` 会清空，但失败分支不调用它 | 同上 |
| `cpuHistory` / `networkHistory` / `diskHistory` | VM | 同一 `capturedAt`。`nil` 跳过，不写成 0，也不删旧点 | 缺口是「没追加」，不是 0。末端时间可以早于当前 `capturedAt` |
| 选中 pid 的 `memorySeries` / `cpuSeries` | 采样器，经 `detail` 发布 | 换 pid 时两条都清空。内存点每次都追加（字节总是有值）。CPU 只在 `cpuPercent != nil` 时追加 | 只有当前选中的一个 pid |
| `topMemorySeries` | 采样器里的 `MemoryGrowthTopStore` | 内存页排序下最多 5 个 pid，掉出前 5 当轮丢弃。可以 `adopt` 选中 pid 的内存环 | 不是按 App，也没有 CPU 点 |

`ChartSample.id` 是进程内递增号，换一次启动就无意义。就算将来做 R1，身份也只能是时间和值，不能是这个 id。

`MemoryGrowthSignal` 是对选中进程内存环的软判断（不足 / 上涨 / 无）。保存不调用 `evaluate`，不把判断结果写进文件。上涨不是泄漏结论，文件也不新增这种结论。

## 最小模型（schema 1）

新类型单独定义，例如 `SavedScene`。不要给 `MemorySnapshot`、`ProcessRow`、`SampledFrame` 加 `Codable`。那些类型带着路径、包标识、压力曲线、图表 id 和按 App 合并的派生旗标，直接编码会把 UI 结构冻结成文件格式。

编码结果是一份 JSON。`schemaVersion` 缺失或不等于 `1` 时，解码失败，不产生填 0 的对象，也不尝试迁移。

```json
{
  "schemaVersion": 1,
  "savedAt": "2026-11-09T04:40:00Z",
  "capturedAt": "2026-11-09T04:39:58Z",
  "samplingFailed": false,
  "processListFailed": false,
  "rateBasis": "intervalEndingAtCapturedAt",
  "memory": {
    "usedBytes": 0,
    "totalBytes": 0,
    "appBytes": 0,
    "wiredBytes": 0,
    "compressedBytes": 0,
    "cachedBytes": 0,
    "pressure": "normal",
    "swapUsedBytes": null
  },
  "cpuPercent": null,
  "busiestCorePercent": null,
  "network": { "inboundBytesPerSecond": null, "outboundBytesPerSecond": null },
  "disk": { "readBytesPerSecond": null, "writeBytesPerSecond": null },
  "processes": []
}
```

`rateBasis` 固定为这一个字符串，表示 CPU、最忙一核、网络、磁盘以及（若选了 Q2）进程速率都是结束于 `capturedAt` 的区间，不是瞬间值。它不是给用户看的句子。

内存块抄 `MemorySnapshot` 的已用、总量、四段分类、两档压力和 `swapUsedBytes`。不抄 `pressureMetric`，也不重算已用字节。发布值里的 `usedBytes` 已经对总量做过上限截断，分类之和可能更大；文件保留这两个已发布的数。压力只存已经判定的 `normal` / `elevated`，不在保存时重读 `kern.memorystatus_vm_pressure_level`，因此看不出当时是内核档还是启发式。

`processes` 的元素等 P/Q 选定后再定稿。在那之前，schema 1 只规定：数组来自同一次同步读取的 `rows`（P3 只取这个数组的前缀，不另排序）；每个对象只含选定的键；`executablePath` 和 `bundleIdentifier` 不出现；`cpuPercent` 用 `null` 表示缺失；`memoryBytes` 用整数，`0` 只有在来源行真是 0 时才出现；`memorySource` 只抄 `footprint` 或 `resident`，不把回退行改记成占用。

非有限浮点在编码前变成 `null`。日期用 UTC 的 ISO-8601。不把 JSON 数字的默认 `Date` 策略留成未指定。

schema 1 不包含：曲线、`machineFacts`、`thermalNotice`、过滤、排序、当前页、退出记录、上涨判断、菜单栏投影、权限脚注文案。本机页和降频若要进入文件，必须自带自己的读取时间；今天这两个类型都没有该字段，所以不能塞进 `capturedAt`。保存时禁止调用 `HostMachineReader.read()` 来补这个时间。

## 缺失和陈旧

| 情况 | 文件里 |
| --- | --- |
| 可选读数是 `nil`（CPU 第一帧、交换失败、速率失败或回绕） | JSON `null`。不用 0，不用空字符串顶上 |
| 交换、足迹、速率的真实 0 | 数字 0，并保留来源旗标 |
| `samplingFailed == true` 且仍有上一份 `snapshot` | 保留那份 `capturedAt` 和数字，`samplingFailed` 为 true。`savedAt` 可以更晚 |
| 进程列表失败 | 主机块仍在，`processes` 为 `[]`，`processListFailed` 为 true |
| 从未成功采到主机内存（`snapshot == nil`） | 按 E1 不写文件。不发明 `capturedAt` |
| 手动重试进行中（`isRetrying`） | 仍保存当前已发布值。不把「正在重试」写成新的采样时间 |
| 周期采样还在 actor 里、尚未 `accept` | VM 没有「在途」发布位（`SamplingRequestGate.currentFlight` 是私有的）。保存不读它，也不等待它 |

回看时，`null` 显示成缺失，`samplingFailed == true` 时必须能看出数字属于 `capturedAt` 而不是 `savedAt`。具体句子未锁定。

## 捕获、写入、失败和覆盖

捕获是 `@MainActor` 上的同步函数：开头把要用的发布值抄进局部常量，函数里没有 `await`。然后纯函数把这些常量收成 `SavedScene`。这个函数不调用 `sample()`、`HostMachineReader.read()`、`ProcessEnumerator`、`WindowedAppLookup`，也不改 `filter`、排序、`selectedPid`、采样门或时钟。

系统保存面板在捕获之后才出现。面板打开期间新的采样可以继续改 VM，但不再改已经冻结的这份值。用户取消面板：丢弃这份值，不写盘，不把它留成下一次的缓存。写入失败：不重新捕获。用户要再点一次保存，才会拿到下一次点击时的发布值。

写入顺序：

1. 先在内存里得到完整 JSON `Data`。编码失败则不碰目标路径。
2. 在目标的同一目录写临时文件，写完并关闭。
3. 用替换把临时文件换成目标。替换失败时删掉还留着的临时文件，目标原字节保持不变。
4. 不写 UserDefaults，不写一份应用自管的快照目录，不维护索引。

覆盖只发生在用户于保存面板里选定一个已存在的路径之后。没有面板确认就不得替换。文件由用户放在自己选的位置；应用不提供快照列表、重命名或批量删除。

不加密。非沙盒，不为这件事加 entitlement。文件可以含进程显示名（P1/P3），不能含可执行路径和包标识。

## 保存和重新打开的边界

重新打开只解码这一份文件，放进只读的展示值。展示值不是 `MemoryDashboardVM` 的 `snapshot`，也不调用 `setSelectedPid`。

回看里的 pid 不能送进 `quitSelected`、`NSRunningApplication.terminate`、`forceTerminate` 或 `ProcessActions` 的信号路径。保存之后 pid 可以被系统复用，拿旧 pid 去退会出现在场上的另一个进程。

打开文件不启动采样，不改变前后台节奏，不改主窗的页、过滤、排序和选中。关掉回看不删除用户的文件。

主窗在回看打开时继续按原来的 1.5 秒 / 3 秒采样。回看不跟随这些新帧更新。

## 现有 App 汇总和单 pid 曲线

「占用最多的 App」是 `TopConsumer.leading(in:)`（`Pulse/Views/OverviewCards.swift`）。它按显示名把未过滤 `rows` 的内存加总，再取合计最大的一组，没有自己的曲线。按 App 合并是 `AppGroupProjection.combine`：内存和线程相加；CPU 或磁盘任一成员缺失则合计缺失；能耗和唤醒可以是部分和，并带 `energyReadingIsPartial` / `wakeupReadingIsPartial`。这是展示投影，不写回采样器。

单 pid 曲线只有两条发布通路：侧栏当前选中 pid 的内存主曲线和 CPU 辅曲线，以及前 5 个 pid 的内存环。没有「每个 App 一条曲线」，也没有全部进程的历史。

schema 1 不保存这两类派生结果。回看要显示主要进程，就显示选定候选下的进程数组，而不是重放 App 汇总或单 pid 曲线。回看也不为了画图标去保存 `bundleIdentifier`；进程退出后图标本来就可能不在。

## 隐私

`ProcessEnumerator` 用 `proc_pidpath` 得到可执行路径，`ProcessIdentityResolver` 再据此读 App 包的显示名和 `bundleIdentifier`。路径可以落在用户目录。显示名通常是 App 名，也可以是可执行文件的 `comm`。

schema 1 允许的身份数据只有产品选定的显示名（P1/P3）或只有 pid（P2）。路径和包标识不编码、不出现在键里。不保存命令行参数；今天的进程行本来也没有参数数组，保存时不要为了补全而去读。

## 依赖、模块边界和风险

不增加 Swift 包。JSON 用 Foundation。保存面板和打开面板用 AppKit，留在 App target。

`Package.swift` 的 `SamplingCore` 用显式 `sources`，并整目录排除 `ViewModels/`、`Views/`。`Pulse.xcodeproj` 没有同步文件夹。将来的实现要同时登记：

| 将来的文件 | 包 | 工程 |
| --- | --- | --- |
| `Pulse/Models/SavedScene.swift`（模型、编码、解码） | 写入 `sources` | `PBXBuildFile`、`PBXFileReference`、Models group、Sources |
| `Pulse/Models/SavedSceneFile.swift`（临时文件和替换；只用 Foundation） | 写入 `sources` | 同上 |
| `Pulse/ViewModels/MemoryDashboardVM+SavedScene.swift`（同步捕获，不采样） | 不用写。`ViewModels` 已排除 | 同上，group 用 ViewModels |
| 回看视图 | 不用写。`Views` 已排除 | 等 V1 或 V2 选定后再加。未选定前不加这个文件 |

测试放在 `Tests/SamplingCoreTests/`，由 `swift test` 编译，不进 App target 的 `pbxproj`。

风险：

- 直接编码 `ProcessRow` 会把 `executablePath` 写进用户文件。
- 点保存时 `await sample()` 会多做一次全表扫描，并把文件时间拖到面板期间的另一帧。
- 用菜单栏投影当来源，失败帧的主机数会丢，进程行却还在。
- 把 `machineFacts` 或 `thermalNotice` 和 `capturedAt` 写在一起，会合成一个不存在的时刻。
- 回看 pid 接上现有退出命令，可能碰到 pid 复用。
- 只改 `pbxproj` 不改 `sources`，或只改 `sources` 不改工程，会让 `swift test` 和 App 构建看到的类型不一致。
- 在 schema 1 里用可选数组容纳 R1，等于不做版本边界。

本设计不实现上述文件。

## 实现时的测试顺序

下面是以后那一个实现 PR 的顺序，不是本 PR 的结果。本环境没有执行这些测试。

先加会失败的 `SavedSceneTests`，再写模型：

- 速率和交换的 `nil` 编码后再解码仍是 `nil`，不是 0。
- 交换和内存占用的真实 0 仍是 0；`memorySource == .resident` 不会变成 `.footprint`。
- `samplingFailed == true` 时，`capturedAt` 保持输入值，不改成 `savedAt`。
- `schemaVersion` 不是 1 时解码抛错，得到的不是全 0 对象。
- 非有限浮点变成 `null`。
- 编码结果的键集合不含 `executablePath`、`bundleIdentifier`、`pressureSeries`、`samples`。
- 进程列表失败的输入得到空 `processes`，主机块仍在。
- 纯函数不读取时钟：`savedAt` 和 `capturedAt` 都由调用方传入。

然后为文件替换加会失败的测试：目标已有内容时，编码失败或替换前的写入失败不改变目标字节；成功后目标是完整 JSON，目录里不留临时文件。

P/Q 选定之后再补一条「进程元素只有约定的键」。未选定前不要用测试把某一候选写成既成事实。

入口、面板和回看视图若要做源码接线测试，沿用 `WiringSourceText`：断言捕获函数没有 `sample()`、回看路径没有 `quitSelected`。这种测试不是 SwiftUI，也不是 VoiceOver。

Mac 上的保存面板、回看布局和 VoiceOver 本设计未验。实现 PR 再把真正要跑的步骤写进 `docs/TECH.md` 的冒烟清单，并标明哪些没跑。本文不改那份清单。

## 本设计故意不改的文档

`docs/TECH.md` 只描述 `main` 上已有的实现。这条能力还没有，所以不往 TECH 里追加一期，也不改冒烟清单。

`docs/PRD.md` 和根 `README.md` 的当前范围也不改。范围要等产品把上面的候选锁定、并且行为真的落地，再在实现 PR 里改。

不新增 ADR。内存占用仍是 ADR-0001，能耗和唤醒仍是 ADR-0002。保存不改变这两个口径。

不改 `docs/specs/00`–`22` 的正文，不改空态文案，不改窗口 frame autosave，不处理仍 open 的 #74。
