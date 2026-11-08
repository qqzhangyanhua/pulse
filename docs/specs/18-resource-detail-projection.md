# Pulse 十八期技术设计（首包：资源 Tab 详情按当前资源呈现主读数）

> 归档：这是第 18 期落地前的设计稿，写完后不再修改。当前实现以 [TECH.md](../TECH.md) 为准，后续期数可能已经改动这里的范围或口径。

> 一期至十七期正文不改写。十七期内存详情的现行文案以十七期那节和已合并的 #58 为准，**本节不改那些句子、算法、ring、Disclosure**。十六期退出存贮不重开。

**已锁定**：侧栏仍是各 Tab 共用的一个 `ProcessDetailSidebar`。只按 `selectedPage` 重排**已经在 `ProcessDetail` 上的字段和曲线**。`.memory` 沿用十七期内存分支。`.gpu` 不进入该分支，也不新做 GPU 主读数。CPU 页主位是该进程自己的 `cpuPercent` 和同一份 `cpuSeries`。网络页主位只声明当前进程网络不可用，不画网络曲线，不用主机速率或 0 冒充。磁盘页主位是该行自己的读/写速率，`nil` 为「—」，真实 0 仍格式化成 0，两路不交叉，不造磁盘曲线。冻结卡换页只改标签和顺序。分子是冻结详情上的字节。分母是这个 `sidebarSubjectPid` 在缺席前、连续 live 期间最后一次 `totalBytes > 0`，不是缺席那一拍的新 snapshot。缺席时列表 `selectedPid` 变为 nil 不清这份分母。

来源：十八期主控已锁的详情主读数；对照 `f06175fd9cbb2992374b7d02b25108df5f84baa6`（#58 合并提交，即本文 base）。仓库里**没有** `networkMetricParts`，**没有** `detailCapability`，**没有**进程网络字节，**没有**进程磁盘曲线。`ProcessDetail.cpuSeries` 已经存在，不必为了把 CPU 曲线放到上面而新造序列 state。

本 PR 只追加本节并在 README 加索引。不写 Swift、不写测试、不跑 `swift test`、不合并、不启动工程。下面的测试矩阵是刀①的设计，不是已执行结果。文档评审通过也不等于工程测试已绿。

## 修订（对照 #59 首稿的展示边界）

1. `.memory` 是「沿用内存既有分支」。`.gpu` 是 `noResourceUpgrade`，不和内存页合成一个 `.unchanged`。
2. 冻结分母是缺席前该 pid 最后一次有效 live 总量。删掉「冻结影像第一次进入展示时再读 snapshot」。不改十六期 quit 记录，不改 `MemoryDetailPresentation.field` 的函数体。
3. 非内存页内存文案就是共享函数 `MemoryDetailPresentation.field(page:part:total:)` 的返回值。列表排序不在本刀。
4. 内存分支里 `metrics` 与 `cpuChart` 都还在。每个投影都保住自己的 `memoryBytes` 和 `memorySeries` 长度。
5. 本地 live / 冻结的主体键只是 `sidebarSubjectPid`。列表 `selectedPid` 在缺席时变为 nil 不清 `lastLive`，也不算换成新主体。不扩范围。

## 十七期现状（保持，不改文件）

| PR | 合并提交 | 文件 |
| --- | --- | --- |
| #57 文档 | `3bc0c3a19edf90e5f1eb30c1e41eb829053e16a8` | 只改了 `docs/TECH.md`、`README.md` |
| #58 实现 | `f06175fd9cbb2992374b7d02b25108df5f84baa6` | `MemoryDetailPresentation.swift`（新）、`MemoryGrowthSignal.swift`、`ProcessDetailSidebar.swift`、`Package.swift`、`project.pbxproj`、四处测试 |

#58 落地后的内存详情文案，十八期一字不改：

- 内存页字段和主曲线标题「驻留内存」；其它页标题「内存」（`MemoryDetailPresentation`）
- 有总量：「占物理内存的 X%（按驻留内存计算）」，X% 仍是 `ByteFormat.share`；无总量：标签「占物理内存」，帮助「此数值为驻留内存。当前没有物理内存总量，不显示占比。」
- 上涨「近期驻留内存上涨」；旁侧「当前进程近期趋势 · 基于现有驻留采样序列」；不足「样本不足，暂不判断」；`.none` 无槽
- Disclosure summary「采样窗口与判断依据」，正文仍是 `MemoryDetailSamplingWindow.body`；`@State`，只在内存页且 `showsLiveTrend`
- `evaluate` 的 80 / 90 / 8 MiB / 60%、选中 ring、Top5 共 ring、列表「上涨」都不动

十七期冒烟里「切到 CPU / 网络 / 磁盘时内存标题回到『内存』」仍然成立：那一格和那条辅助曲线的可见标题继续是「内存」。十八期只改这三页的**主位和顺序**，不把标题改成「内存辅助」。

## 范围

| 项 | 既有 | 十八期首包 |
| --- | --- | --- |
| 内存页详情 | #58：驻留字段、占比、basis、Disclosure、内存曲线然后 CPU 曲线 | **整页保持**。投影返回 `.memoryExisting`，视图走这段既有分支，其中仍有 `metrics` 和 `cpuChart` |
| CPU 页详情 | 与内存页同一套顺序，只是标题为「内存」 | 主位：`cpuPercent` + 现有 `cpuChart`。其下：内存指标 + 现有 `memoryChart`，角色为辅助 |
| 网络页详情 | 侧栏不提网络；总览才是主机下行/上行 | 主位只有「当前进程网络暂不可用」。其下 CPU 与内存两个原名辅助指标，再一条内存辅助曲线。无网络曲线 |
| 磁盘页详情 | 侧栏不提磁盘；列表已有读/写速率 | 主位两格「读取」「写入」，来自该行两个 `Double?`。其下 CPU 与内存辅助，再一条内存辅助曲线。无磁盘曲线 |
| 进程网络数据 | `networkAvailability` 恒为 `.unavailable`，列表字是「暂不可用」 | **不新增字节、不探测**。列表短句不动。详情用上面那句长句，不复用列表短句当数字 |
| 进程磁盘历史 | 只有两帧速率，没有 ring | **不造** |
| 冻结 / 退出 / 选中 | 十六期：缺席时列表 `selectedPid` 变 nil，`sidebarSubjectPid` 仍是该 pid，冻结详情留在侧栏 | **不改 quit 规则**。换 Tab 只重放投影。占比分母跟 `sidebarSubjectPid`，不跟列表 `selectedPid` 清空 |
| GPU 详情 | Tab 不可点；侧栏仍是同一份 | **不新做 GPU**。`.gpu` 走 `noResourceUpgrade`，不进入内存主读数分支 |
| 总览、列表、菜单栏、Top5、主机合计 | 既有 | **不改** |

一二至十七期验收不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 字段从哪来（当前源码）

侧栏今天不看页：`detailBody` 一律是 `metrics`（内存格在左、CPU 格在右）、可选上涨槽、可选 Disclosure、`memoryChart`、`cpuChart`。空态文案才按页切换。总览曲线是主机的，不进侧栏。

| 侧栏要显示的 | 真实字段 | 现在谁产生 | 缺失时 |
| --- | --- | --- | --- |
| CPU 百分数 | `ProcessRow.cpuPercent: Double?` | `ProcessCPUPercent.percent`：两帧 wall-clock。第一帧、回绕、`wallNs <= 0` 为 nil | `CPUPercentText` / `ByteFormat.cpu` → 「—」。真实计算得到的 0 是「0.0%」。不是磁盘那套 |
| CPU 曲线 | `ProcessDetail.cpuSeries` | `MemorySampler.detailFrame`：仅当 `row.cpuPercent != nil` 才 append。nil **不** `removeAll` | 点数 `< 2` 仍是「正在采集 CPU 曲线」 |
| 内存字节 | `ProcessRow.memoryBytes: UInt64` | `pti_resident_size`。不是 Optional | `ByteFormat.memory`：0 是「0 字节」 |
| 内存曲线 | `ProcessDetail.memorySeries` | 选中 ring 或 Top5 `adopt`。成功帧会 append | 点数 `< 2` 仍是「正在采集内存曲线」 |
| 内存标题 / 占比 | `MemoryDetailPresentation.field(page:part:total:)` | 十七期纯函数，函数体不改。实时分母只看当前 `snapshot?.totalBytes`（nil 或 0 就是无占比）。冻结分母见下文，不看缺席帧以及之后的 snapshot | 无总量不调用 `share` |
| 磁盘读 / 写 | `diskReadBytesPerSecond` / `diskWriteBytesPerSecond` | 见下一节。两格只读这两个 Optional，不读主机磁盘 | 各字段自己的 nil → `DiskRateText` → 「—」 |
| 进程网络 | 无字节字段 | `networkAvailability` 计算属性，恒 `.unavailable`，label「暂不可用」 | 没有速率可以显示 |
| 主机网络 | `MemoryDashboardVM.hostNetworkRates` + `networkHistory` | `NetworkOverviewSection`，标题「下行」「上行」 | 总览用「—」。**禁止**进进程详情 |
| 主机磁盘 | `hostDiskRates` + `diskHistory` | `DiskOverviewSection` 的 `DiskRateCard`（带主机曲线） | 总览用「—」。**禁止**补进程详情的 nil |

`cpuSeries` 不需要新 state，也不需要一个 normalizing 字段才能排序图表。CPU 页把现有 `cpuChart(detail)` 挪到内存曲线上面即可。序列元素的 `id` / `date` / `value` 原样传递。

### 磁盘：解码失败、第一帧、真实 0（已读源码，不是猜测）

`ProcessEnumerator.readDiskIO`：`proc_pid_rusage` 返回值不是 0 → 整个读数丢掉，`diskBytesRead` 与 `diskBytesWritten` **同时** nil。返回 0 → 两个 `UInt64` 都留下，**可以是 0**。没有「只解出一路」的分支。`ProcessEnumerator` 不在 SamplingCore 里，本文档 PR 没有、也不能在 Linux 上调用它。

`MemorySampler` 只有两路计数都非 nil 才做成 `DiskTick`。然后 `ProcessDiskLoad.advance`：

| 输入 | 速率 | baseline |
| --- | --- | --- |
| `reading == nil`（本帧解码失败） | 两路都 nil（`.missing`） | **留上一帧** |
| 有 tick、`previous == nil`（成功计数的第一帧，字节可以是 0） | 两路都 nil | 存下这一帧 |
| 两帧都在、未回绕、`seconds > 0`、增量为 0 | **两路都是 0** | 更新 |
| 任一路回绕，或 `seconds <= 0` | 两路都 nil | 有 tick 时仍更新 |

所以：第一帧 nil **就是** `ProcessDiskLoad` 的两帧差分，已有 `ProcessDiskLoadTests.testFirstFrameIsNil`。累计字节为 0 的第一帧也是 nil 速率，不是 0 B/s。真实 0 速率是 `testIdleDeltaIsRealZeroNotAPlaceholder`。解码失败是 `testEPERMOrFailedRusageIsNilAndKeepsBaseline`（`reading: nil` 不把速率写成 0）。这三支是已有测试，**本 PR 不跑、不改**。

行类型上两个 `Double?` 仍然独立。活采样今天总是两路同 nil 或两路同有值。投影和测试必须允许「读 nil、写 0」这种手工行，并且不得把 nil 填成 0、不得把写速率画进读格。

`DiskRateText.string` 已是：nil → 「—」；0 → 「0 字节/秒」。详情复用它，不另写格式化。

### 网络：没有 per-process 来源

当前树没有 `MemoryDashboardVM.networkMetricParts`。主机 label 就是 `NetworkPageCopy.inboundTitle` / `outboundTitle`（「下行」「上行」），数据是 `hostNetworkRates`。这和「只主机 label」一致。不要把这个名字补回来，也不要把它接到侧栏。

进程行没有网络字节。`PROC_PIDTASKINFO` 不提供。详情主位是固定枚举，无关联值，不读取主机速率，也不因为 `memorySeries` 有点就把网络当成可用。列表列继续用「暂不可用」。详情长句单独放在新投影常量上，避免改到 `processNetworkUnavailable` 把列表一起改掉。

不新增 capability 类型，不在 Sampler 里探测，不把内存曲线当成网络能力的 fallback。

### 采样失败不清旧曲线（现状，投影不得加一条清）

- 主机内存读取失败：`sample()` 在 append 之前 `return .failure`。VM 的失败支只改 `samplingFailed` / `loadState`，不替换 `detail`。
- 进程列表失败或 freshness 不足：`isSuccessfulProcessList` 为假，`applySample` 把 `liveDetail` 留在 `currentLiveDetail`。Sampler 的两条选中序列不 `removeAll`。
- 成功帧上 CPU 为 nil：不 append，也不清空 `selectedCPUSeries`。主位数字是本帧的 nil（「—」），曲线仍是旧点。投影不得用曲线最后一点填掉这个 nil，也不得因为 nil 丢掉曲线。
- 磁盘没有序列。本帧 rusage 失败时**这一行**的速率是 nil。不要为了「留住上次速率」在投影里缓存上一帧。那会把未知画成一个数。

`setSelectedPid` 只在 pid 真正变化时清空两条选中序列。换页不调用它。

### 选中与冻结的入口（不改）

`ProcessQuitSession.displayedDetail`：

1. 无 `sidebarSubjectPid` → nil → 空侧栏。
2. `showsAbsentRecord` → `frozenDetail`。nil 则没有详情。
3. 否则 `liveDetail` 的 pid 相符就用它。
4. 否则行还在、还没有 live detail → `ProcessDetail(row:memorySeries:[]、cpuSeries:[])`。

`frozen = showsAbsentRecord`。`showsLiveTrend` 在冻结时为假，所以上涨槽和 Disclosure 已经进不了冻结卡。十八期不要加第二条路径对冻结序列 `evaluate`。

`selectPage` 不写 `selectedPid`、不写 `quitOutcome`、不清 generation / token / pending。列表排序不在本刀。

`MemoryGrowthRisingFilter.selectedPid`：只有 `risingOnly && page == .memory` 才可能把选中清掉；其它页 **return current**。因此内存 → CPU，即便「仅上涨」开着，也**不会**因为离页而清选中。这个方向保持。开着过滤再回到内存、且该 pid 没有角标时仍会清，也不要反过来。投影函数不接收、不写 `selectedPid`。

offRows：侧栏拿到的已经是那份 `frozenDetail`。换 Tab 用**同一份值**再投影。字节、速率、曲线的 `date` 都不改，也不改成实时。`frozenDetail == nil` 时仍是 `absentRecordBody`（关闭 + 页脚），投影不准变出一张新卡。Quit、pending、store 不因投影重置。

### 冻结占比：分母是缺席前最后一次有效 live 总量

`applySample` 在成功帧里的顺序是：先 `snapshot = frame.snapshot`，再构造 `Observation(liveDetail: frame.detail, detailToFreeze: detail)`，然后 `ProcessQuitSession.applySample` 把缺席 pid 的旧 `detail` 写入 `frozenDetail`。缺席那一拍的 `frame.snapshot.totalBytes` 可以已经是新的 18 GiB，而 `detailToFreeze` 仍是旧详情上的 8 GiB。视图若等冻结卡第一次出现再读 `vm.snapshot`，读到的是 18，不是这个进程最后一次 live 的 16。那一句「第一次进入展示时捕获」作废。冻结当时能看见的 snapshot、旧 detail、或别的当场上下文，都不能当成「以前的 live 总量」。

`ProcessQuitRecord.frozenDetail` 仍只是 `ProcessDetail?`。记录里没有物理总量，十八期不加。主机总量是机器级的 `physicalMemory`，每一成功帧写进新的 `MemorySnapshot`。视图本地只为了冻结后的占比文案，记住这个 pid 在连续 live 期间最后一次 `totalBytes > 0`。这不是物理总量历史，不保证知道缺席期间机器总量变过没有，也不新做身份判定。`MemoryDetailPresentation.field` 的函数体不改；变的只是冻结时传进去的那个 `total`。

例：连续 live 见过分子 8 GiB、分母 16 GiB。缺席帧 snapshot 换成 18 GiB，列表 `selectedPid` 变为 nil，`sidebarSubjectPid` 仍是 A，冻结详情留在侧栏。`.freeze(A, memoryBytes: 8 GiB)` 的分母是 16 GiB，`ByteFormat.share` 为 50%。这里只锁这一格的分母，不把整张冻结卡说成与某一帧 snapshot 重合。切到 CPU 仍是 8 / 16，`field` 只改标题和句式。列表选中没了、名称过滤、再换资源 Tab，都不清这份分母。缺席之后 snapshot 再变，包括 nil 与新的正数，也不改。

视图本地两份 `@State`，都不是 VM 的 `@Published`：

- `lastLiveTotal`：空，或 `(sidebarSubjectPid, totalBytes)` 且 `totalBytes > 0`。键只是侧栏主体。`memoryBytes` 不参与「还算不算同一次 live」。列表 `selectedPid`、`selectedRow`、滚动目标都不是这把键。侧栏详情不跟列表选中共用一把键。
- `frozenMemorySemantics`：只在 live → 缺席那一次写入。之后换页、以及后续 snapshot 的 `onChange`，都只读它。

记住的规则：

- 正常 live（`showsAbsentRecord == false`，且 `sidebar.detail` 就是当前 `vm.detail`，pid 相同）见到 `totalBytes > 0` 时，记下这个 pid 的最近一次。当前是 nil 或 0：不覆盖已有的正数。live 画面仍按当前 snapshot 显示；当前无值就是无占比，不准把记下的正数偷出来显示。
- 这个 pid 从第一次 live 起就没有过 `> 0`：`lastLiveTotal` 保持空。冻结分母为 nil，caption 停在「占物理内存」。缺席之后出现的新总量不得补上比率。
- 清空只发生在 `sidebarSubjectPid` 上。A→B 送 `.subject(B)`：先清掉 A 的 `lastLive` 和冻结语义，再按 B 当前的 live snapshot 观察，A 的 16 GiB 不得进 B。`dismissSidebar` 使主体变为 nil：同样清空，空侧栏不新建 `lastLive`。列表 `selectedPid` 变为 nil、过滤把行藏起、或资源 Tab 切换，而侧栏主体仍是 A：不送 `.subject`，不清 `lastLive`。
- 同一 pid 只在连续 live、且没有经过缺席再出现时接着记。连续 live 里换了一份 detail，可以更新正数总量，但不得因为 same pid 就把已经冻结的语义再锁一次。
- 缺席切换的前提是：旧侧栏和新侧栏的 `sidebarSubjectPid` 都是 A，新的 `showsAbsentRecord == true`，侧栏详情已是这份 `frozenDetail`。这时送 `.freeze(A, memoryBytes: 8 GiB)`，不读当前 snapshot。同一拍列表 `selectedPid` 已是 nil，也不送 `.subject(nil)`。主体换成 B，或侧栏被关掉：跳过这次同 pid 的 `.freeze`，按上面的 `.subject` 清。
- 同一 pid 无身份证据再出现：按十六期是新的实时进程，送 `.newLiveSubject`。清掉上一份 `lastLiveTotal` 和 `frozenMemorySemantics`，重建观察。新 live 只用当前 snapshot；有 `> 0` 才显示比率，没有就未知。不得把上一份冻结总量当成新进程的预热缓存，不得因此改 sampler 或 quit store。

缺席成功帧里，`ProcessQuitSession.applySample` 的 `listSelectedPid` 会变成 nil（人已不在 `rows`）。VM 把 `selectedPid` 写成 nil 后，`didSet` 会把 VM 的 `detail` 清掉，并异步 `sampler.setSelectedPid(nil)`。`sidebarSubjectPid` 仍是 A：记录还在，所以主体不会被清成 nil。侧栏继续用这份 presence 上的 `frozenDetail`。`selectedPid == nil` 或 VM `detail == nil` 只是列表结算，不是新的侧栏主体，观察器不得据此认为「没有 live 主体」而清空 `lastLive`。

纯函数只负责把已经决定的输入变成文案，自己不记缓存。建议 Darwin-free 的 `LastLiveTotalReducer.step`，输入是上一份 `lastLiveTotal` 加上一次事件，输出是下一份 `lastLiveTotal` 和可选的 `FrozenMemoryFieldSemantics`。投影函数不调用它。

```text
struct FrozenMemoryFieldSemantics: Equatable, Sendable {
  pid: Int32
  memoryBytes: UInt64          // 只在 freeze 时从 frozenDetail.row 抄下
  physicalTotalBytes: UInt64?  // 该 pid 连续 live 的最后一次 > 0；从未有过则 nil
}
```

事件只有这些，`freeze` 的参数里没有「现在的 snapshot」：

| 事件 | 何时由视图送入 | 结果 |
| --- | --- | --- |
| `.live(pid, totalBytes)` | 当前侧栏已是该 `sidebarSubjectPid` 的正常 live | `> 0` 且 pid 就是这份记忆的主体：更新最近值。nil 或 0：不覆盖。pid 对不上：整次忽略，不把旧总量带去，也不当成换主体。缺席时不送；已冻结后再送来也忽略 |
| `.subject(pid)` | `sidebarSubjectPid` 从 A 换成 B，或 `dismissSidebar` 后变为 nil | 清空旧记忆和冻结语义。空主体不新建 `lastLive`。换成 B 之后，另一次 `.live` 才按 B 的当前 snapshot 记；不得留下 A 的 16 GiB |
| `.newLiveSubject(pid, totalBytes)` | 同一 pid 缺席后再成为 live | 清掉旧记录上的缓存和冻结语义，只按这次的当前总量重新开始 |
| `.freeze(pid, memoryBytes)` | 新旧侧栏主体都是这个 pid，且新侧栏已是冻结详情 | 用记忆里该 pid 的正数总量（或 nil）配上这个 `memoryBytes`。参数里没有 snapshot，也没有列表 `selectedPid` |

调用点在 `ProcessDetailSidebar`，不在 `body` 里给 `@State` 赋值：

1. `.onAppear` 与 `.task`：用**当前**侧栏判断。已经缺席则绝不送 `.live`。只有正常 live 才用当前 `snapshot?.totalBytes` 送一次 `.live`。正常 live 仍是：`showsAbsentRecord == false`，且 `sidebar.detail` 与当前 `vm.detail` 的 pid 相同。`showsAbsentRecord == false` 但详情只是行还在、VM `detail` 尚未回来的那份空序列 `ProcessDetail`，不算这次 live，定义不另加。主体为 nil 或侧栏为空：不新建 `lastLive`。
2. `.onChange` 于被接受的新 snapshot：与侧栏那次 `onChange` 的先后不必规定。每次都重读**这一拍当前**侧栏的 `showsAbsentRecord`，不用上一拍留下的 live 门。当前已缺席就不送 `.live`。先冻结或后冻结都一样：缺席门拒绝 `.live`，新 snapshot 不覆盖已写入的冻结语义。
3. `.onChange(of: sidebar)`：重读新侧栏。旧主体与新主体都是 A，且新的 `showsAbsentRecord == true`、详情已是 `frozenDetail`：送 `.freeze(A, 8 GiB)`，不带当前 snapshot。新的列表 `selectedPid` 即使是 nil，也不送 `.subject(nil)`。若这次是关掉侧栏或主体换成 B：不做这个同 pid 的 `.freeze`，送 `.subject` 清空。缺席结束、同一 pid 再次 live：送 `.newLiveSubject`。

`.freeze` 之后，列表选中被清、名称过滤、资源 Tab 切换都不重置这两份 `@State`。资源 Tab 不用列表选中的新旧 id 去重置。能清的只有 `sidebarSubjectPid` 的 A→B、`dismissSidebar`，以及同一 pid 的 `.newLiveSubject`。不改 `applySample`，不加 VM `@Published`。

`body` 只读。live 投影的 `total` 是当前 snapshot（nil 或 0 就是未知）。冻结投影只用已经写入的 `frozenMemorySemantics`。换页用同一份。后续 snapshot 的 `onChange` 不再改它。

投影输出仍是现有 `field(page:part:total:)`。`part` 是冻结详情上的 `memoryBytes`，`total` 是语义里的分母，`page` 是当前页。语义的 pid 与 `detail.row.pid` 不一致时，`total` 用 nil，不用 live 参数里的 18 GiB。语义里的 `memoryBytes` 只供单测对照捕获到的分子，不用它拒绝这组分母。

## 投影（刀①，Darwin-free，结构化）

新文件建议 `Pulse/Models/ResourceDetailPageProjection.swift`。只 `import Foundation`。实现 PR 再把它列入 `Package.swift` 的 `sources` 和 `project.pbxproj`。本 PR 不添加该文件。

输入是 `page`、`detail`，以及内存分母来源：实时用当前 `physicalTotalBytes: UInt64?`，冻结用视图已经定好的 `FrozenMemoryFieldSemantics`。投影函数不保存 last-live。`LastLiveTotalReducer.step` 只把入参变成下一份值，状态放在侧栏 `@State`。**参数表里不准出现** `HostNetworkRates`、`HostDiskRates`、`networkHistory`、`diskHistory`、`systemCpuPercent`、`ProcessQuitOutcome`、sampler。

`MemoryDetailPresentation.field(page:part:total:)` 是内存页和其它页共用的那一个函数。`MemoryDetailPresentationTests` 锁的是它的返回值。投影里的 `memory: MemoryDetailFieldCopy` 就是 `field(page: 当前页, part: memoryBytes, total: 这次调用传入的分母)`，所以非内存页的标题「内存」和「占 {GB} 的 {share}」与现有单测一致。不要把「个内核」写进这个函数；那一行仍是视图里的 `ByteFormat.coreLoad`。投影不调用 `MachineInfo`。

输出是值类型枚举，不是字典，也不是「全是 String 的结果」。没有一个笼统的 `.unchanged`。

```text
enum ResourceDetailProjection {
  case memoryExisting(MemoryExistingProjection)   // 仅 .memory
  case cpu(CPUDetailProjection)
  case network(NetworkDetailProjection)
  case disk(DiskDetailProjection)
  case noResourceUpgrade(NoResourceUpgradeProjection)  // 仅 .gpu
}

struct MemoryExistingProjection {
  pid: Int32
  memoryBytes: UInt64
  memorySeries: [ChartSample]     // count 与元素（含 date）等于 detail.memorySeries
  cpuSeries: [ChartSample]        // count 与元素等于 detail.cpuSeries；视图仍画 cpuChart
}

struct CPUDetailProjection {
  pid: Int32
  cpuPercent: Double?                 // detail.row.cpuPercent
  cpuSeries: [ChartSample]            // 等于 detail.cpuSeries
  memory: MemoryDetailFieldCopy       // field(page: .cpu, ...)
  memoryBytes: UInt64
  memorySeries: [ChartSample]         // count 与元素等于 detail.memorySeries
}

enum ProcessNetworkDetailNotice { case unavailable }  // 无关联值

struct NetworkDetailProjection {
  pid: Int32
  notice: ProcessNetworkDetailNotice  // 永远 .unavailable
  cpuPercent: Double?
  memory: MemoryDetailFieldCopy       // field(page: .network, ...)，标题「内存」
  memoryBytes: UInt64
  memorySeries: [ChartSample]         // count 与元素保留；只作辅内存曲线
}

struct DiskDetailProjection {
  pid: Int32
  readBytesPerSecond: Double?
  writeBytesPerSecond: Double?
  cpuPercent: Double?
  memory: MemoryDetailFieldCopy       // field(page: .disk, ...)
  memoryBytes: UInt64
  memorySeries: [ChartSample]
}

struct NoResourceUpgradeProjection {
  pid: Int32
  cpuPercent: Double?                 // 既有 CPU 文案，不是 GPU 主读数
  memory: MemoryDetailFieldCopy       // field(page: .gpu, ...)，标题「内存」，不是「驻留内存」
  memoryBytes: UInt64
  memorySeries: [ChartSample]         // 只能作辅内存曲线
}
```

常量 `processNetworkUnavailable = "当前进程网络暂不可用"` 放在投影类型上。视图把 `.unavailable` 画成这一句。模型里不存速率、不存「0」。

规则：

- `page == .memory` → `.memoryExisting`。载荷只是把 `memoryBytes`、`memorySeries`、`cpuSeries` 原样带上，供单测核对长度。视图不靠这份载荷重做十七期布局。
- `page == .gpu` → `.noResourceUpgrade`。`DashboardPage.isSelectable` 为 false 只说明 Tab 点不中。冻结详情仍可留在共用侧栏里，调用方仍可能把 `.gpu` 和一份 `ProcessDetail` 一起送进投影。这一支不造 GPU 主读数、不造 GPU 曲线、不把主 panel 改写成内存页。类型里没有 `cpuSeries`，避免被画成一条资源曲线。CPU 只保留行上的 `cpuPercent` 文案。`memorySeries` 只作辅内存。
- `.cpu` / `.network` / `.disk` 只拷贝上表字段。网络投影不带 `cpuSeries`。磁盘投影不带磁盘序列。
- 每一支的 `memoryBytes` 等于 `detail.row.memoryBytes`，`memorySeries.count` 等于 `detail.memorySeries.count`，元素的 `date` 不变。`.memoryExisting` 与 `.cpu` 的 `cpuSeries` 同样原样。投影不删点、不补点。
- 纯函数，无缓存、无 `inout`、不发 `objectWillChange`、不加 `@Published`。同一 `detail` 连续投影，输入前后 `==`。
- 同一 pid、同一 `detail`、同一分母来源：`.cpu` / `.network` / `.disk` / `.noResourceUpgrade` 的 `cpuPercent` 与 `memoryBytes` 相等。磁盘数只出现在 `.disk`。网络通知只出现在 `.network`。A、B 两个 pid 各投影各的。
- 非内存页内存标题是 `field` 对那个 `page` 的返回值「内存」。不另造「内存辅助」。曲线放在主位之下，不能叫成网络、磁盘或 GPU。
- 冻结入参的 `physicalTotalBytes` 是 reducer 在 `.freeze` 时给出的那一个。旁边再递来的 live 总量（缺席帧的 18 GiB）不得覆盖它。语义 pid 与详情 pid 不一致时，分母用 nil，也不改用 live 总量。

不新造「本资源缺数据」接收类型。磁盘未知就是 `Double?` 的 nil。网络不可用就是上面那个无载荷枚举。冻结缺席仍是十六期的 `showsAbsentRecord`。GPU 的 `noResourceUpgrade` 表示没有资源专属布局，不是一种新的缺席类型。

## 视图顺序（刀②，只重排）

只改 `ProcessDetailSidebar`。`header`、`footer`、空态、`absentRecordBody` 留在页分支外面。`seriesBlock` 的 `count < 2` 占位保持。不新卡片样式、不新颜色、不新 Tab。不要用一个 `else` 把 `.gpu` 和内存页收成同一段。

`detailBody` 按投影分支。`.memoryExisting` 这一支必须仍写在 `detailBody` 本体内，并继续调用现有 `metrics(detail)`（内存格在左、CPU 格在右，两格都在）。相对顺序不变：`memoryGrowthSlot` → `showsLiveTrend && selectedPage == .memory` → `samplingWindowDisclosure` → `memoryChart(detail)` → `cpuChart(detail)`。`cpuChart` 在这条 else / 内存支里，不能为了 CPU 页把主位提前而从内存支删掉。这样 #58 的 `MemoryDetailSidebarWiringSourceTests` 仍能在 `detailBody` 里看到这条顺序。源码断言只说明结构还在，不是 Mac 验收，也不必为了十八期去改那些断言的期望。

| 投影 | 自上而下 | 这一支保住的长度 | 明确不画 |
| --- | --- | --- | --- |
| `.memoryExisting` | 今天的 `metrics`、上涨槽、Disclosure、`memoryChart`、`cpuChart` | `memoryBytes`、`memorySeries.count`、`cpuSeries.count` | 不改成 CPU 在上、内存格消失 |
| `.cpu` | CPU `SidebarMetric`（`ByteFormat.cpu` + `coreLoad`）→ `cpuChart(detail)` → 内存 `SidebarMetric` → `memoryChart(detail)` | `cpuSeries.count` 与 `memorySeries.count` 都在 | 无 Disclosure、无上涨槽、无磁盘、无网络 |
| `.network` | 长句文本（无数字）→ CPU 与内存两个原名 `SidebarMetric` → `memoryChart(detail)` | `memorySeries.count`；类型里没有 `cpuSeries` | 无 `cpuChart`、无网络曲线、无主机下行/上行 |
| `.disk` | 同一行「读取」「写入」→ CPU 与内存辅助 → `memoryChart(detail)` | `memorySeries.count`；读/写各留各的 Optional | 无 `cpuChart`、无 `DiskRateCard`、无磁盘历史 |
| `.noResourceUpgrade` | 内存 `SidebarMetric`（标题「内存」）与 CPU `SidebarMetric` → 只一条辅内存曲线 | `memorySeries.count`；CPU 只有 `cpuPercent` | 无 GPU 主读数、无 GPU 曲线、无 Disclosure、不进入 `.memoryExisting` |

磁盘两格复用 `SidebarMetric`。符号用资源 Tab 已有的 `internaldrive`，tint 用已有 `PulsePalette.chartDisk`。不要用总览的 `arrow.down` / `arrow.up`。读格只绑 `readBytesPerSecond`，写格只绑 `writeBytesPerSecond`。

网络主位是一行字，不是带假数字的新卡片。CPU / 内存辅助仍是原来的两个名字：「CPU」和「内存」。

实时与冻结调用同一个投影函数。实时只传入当前 `snapshot?.totalBytes`（nil 或 0 不改用 `lastLiveTotal`）。冻结只传入缺席切换时写下的 `FrozenMemoryFieldSemantics`。换页不换这份分母。投影不 append、不 `evaluate`、不读主机速率，也不在函数内部观察 snapshot。

## 明确不动

- 不改 `MemoryDetailPresentation.field` 的函数体、`MemoryGrowthSignal`、`MemoryDetailSamplingWindow`、列表角标。非内存页继续调用这个共享函数
- 不改 `ProcessQuitOutcome`、`ProcessQuitSession`、`ProcessActions`、token、generation、pending、`frozenDetail` 的写入点
- 不改 `selectedPid` 的 `didSet`、`selectPage`、`applySample`、`applyRisingOnlySelection`、`MemorySampler`、`ProcessEnumerator`、采样周期
- 不改 `CPUPageCopy`、`NetworkPageCopy.processNetworkUnavailable`（列表仍是「暂不可用」）、`DiskRateText`、总览、进程表、菜单栏
- 不造 per-process 网络、磁盘历史/曲线、全表 CPU 序列、新 store、新算法
- 不把失败帧清曲线，不把磁盘 nil 显示成 0，不把冻结详情改成实时趋势，不把冻结占比分母改成下一帧 `snapshot.totalBytes`
- 不新增 VM `@Published`、不新增 ring、不把物理总量写进十六期 quit 记录

## 测试矩阵（设计；本 PR 不写、不跑）

**刀①（实现 PR 才加，Linux `swift test`，纯投影）：**

1. 同一 `detail` 投影 `.cpu` / `.network` / `.disk`：`cpuPercent`、`memoryBytes` 都等于该行；`.cpu` 的 `cpuSeries.count` 与 `detail.cpuSeries.count` 相等且元素含 `date` 相等；三支的 `memorySeries.count` 都等于输入。磁盘读/写只在 `.disk`。
2. `.memory` → `.memoryExisting`，其 `memorySeries.count` 与 `cpuSeries.count` 都等于输入。`.gpu` → `.noResourceUpgrade`，标题是 `field(page: .gpu, ...)` 的「内存」，不是「驻留内存」；`memorySeries.count` 等于输入；这一支没有 `cpuSeries` 字段，也没有磁盘或网络速率。
3. pid A 与 pid B 交替投影，输出 pid 和 CPU 跟各自输入走，不留上一次。投影前后输入 `detail ==` 原值。
4. `.live(A, 16 GiB)` 之后 `.freeze(A, memoryBytes: 8 GiB)`。`.freeze` 不接收 18 GiB，也不接收「列表 selectedPid 已是 nil」。语义分母是 16 GiB。投影同时收到这份语义和 live 18 GiB，内存页 caption 的 `share` 是 50%（8 / 16）。换 `.cpu` 后标题变为「内存」，分母仍是 16。同一拍若当前侧栏已缺席，不得再送 `.live(A, 18 GiB)` 把 16 盖掉。
5. 列表选中消失不送 `.subject`，冻结语义还在。`.subject(B)` 清掉 A 的 16，随后 `.live(B, …)` 不得带上 16。`.subject(nil)`（关掉侧栏）清空，且不新建 `lastLive`。`.live(A, 16 GiB)` 之后 `.live(A, nil)` 与 `.live(A, 0)` 仍记住 16，但 live 投影的 `total == nil` 时不得画出 16 的占比。从空状态 `.live(A, nil)` 再 `.freeze(A, 8 GiB)`，分母为 nil；之后的 18 GiB 不得补上。`.newLiveSubject(A, nil)` 清空旧语义；新的 live 只用当前总量，不用 16。
6. 网络：`notice` 只有 `.unavailable`；常量等于「当前进程网络暂不可用」；不等于「暂不可用」、不等于「0 字节/秒」、不等于含「下行」的总览句。`memorySeries` 空或非空都是同一个 notice。类型上没有网络速率字段。
7. 磁盘四支：读 nil / 写 0；读 0 / 写 nil；两路 nil；两路 0。`DiskRateText` 对 nil 是「—」、对 0 是「0 字节/秒」，左右不交换。
8. `cpuPercent == nil` 且 `cpuSeries` 已有点：`.cpu` 主位仍是 nil，`cpuSeries.count` 不变。空的 `memorySeries` 在每一支都保持 0 点，不补到 2 点。
9. `.cpu` 的 `memory` 等于 `MemoryDetailPresentation.field(page: .cpu, part:total:)`。不改 `MemoryDetailPresentationTests` 的既有期望；那些期望已经锁住非内存页 caption。
10. 不改、不重跑 `ProcessDiskLoadTests`、`DiskPageTests`、`MemoryGrowthSignalTests`、十七期文案测试。那些已经锁住 nil/0 和 ring。十八期不把「再测一遍 ring」写成新代码。本 PR 自己也不跑这些测试。本条不写实现代码。

**刀②（源码约束，不是 GUI，Mac 未验）：**

11. `detailBody` 的 `.memoryExisting` 分支仍按 #58 源码测试的顺序包含上涨槽、Disclosure 门、`memoryChart`，并且其后仍有 `cpuChart`。该分支仍调用 `metrics`。`DisclosureGroup` 仍只有一处。`cpuChart` 的标题字面量不改。`.noResourceUpgrade` 分支不含 `samplingWindowDisclosure`、不含 `cpuChart`。VM 的 `@Published` 仍是 22 处。`selectPage` / `selectedPid` 的 `didSet` 源码不出现投影类型。`ProcessQuitSession.swift` 不出现 `totalBytes` 或 `FrozenMemoryFieldSemantics`。侧栏源码不因 `selectedPid == nil` 去清 `lastLiveTotal`。
12. 网络分支源码不含 `hostNetworkRates`、`networkHistory`、`cpuChart`、`inbound`。磁盘分支不含 `hostDiskRates`、`diskHistory`、`DiskRateCard`、`cpuChart`。侧栏不给 `frozenDetail`、`quitOutcome`、`selectedPid` 赋值，不调用 `evaluate`。`lastLiveTotal` 的写入出现在 `.onChange` / `.onAppear` / `.task`，不出现在 `body` 里。冻结语义不写进 `ProcessQuitOutcome.swift`。
13. 上述源码断言不是 SwiftUI 点击、不是截图、不是 Mac 验收。

本环境没有跑刀①，也没有 Mac。不要把本文写成「测试已绿」或「侧栏已点过」。

## 风险

| 风险 | 应对 |
| --- | --- |
| 用 `hostNetworkRates` 填进程网络 | 投影参数不准有主机速率；主位无数字 |
| 用内存曲线或 0 表示「有网络」 | notice 无载荷；不看 `memorySeries` 长度 |
| 磁盘 nil 画成 0，或读/写对调 | 两个 `Double?` 分开绑；复用 `DiskRateText` |
| 用主机 `DiskRateCard` 做进程详情 | 详情只读行上的两路 Optional；不画主机曲线 |
| 为了 CPU 在上而新造 `cpuSeries` | 已有字段，只重排 `cpuChart` |
| 换页清选中、清 quit、清曲线 | 不改 `selectPage` / `didSet` / sampler |
| 缺席时列表 `selectedPid` 变 nil，观察器把 `lastLive` 清掉，或用 18 GiB 当 16 GiB | 键只是 `sidebarSubjectPid`。列表选中变 nil 不送 `.subject`。`.freeze` 不接收当前 snapshot。换页只读已写入的语义 |
| `.gpu` 掉进内存主读数，冒出「驻留内存」和 Disclosure | `.gpu` 只产生 `.noResourceUpgrade`；内存支只有 `.memory` |
| 改「驻留内存」或 Disclosure 来做辅助标题 | 非内存页标题来自 `field(page:)` 的「内存」；`.memoryExisting` 才走十七期分支 |
| 把列表「暂不可用」改成长句 | 长句只在投影常量 |
| 源码测试或文档评审被说成工程已绿 | 矩阵第 13 条；本 PR 不跑 `swift test` |

## 验收

- [ ] 内存页与 #57 / #58 一致：驻留、占比、basis、Disclosure、算法、ring、曲线顺序都不改
- [ ] CPU 页主位是该进程 `cpuPercent`（nil 为「—」）和同一 `cpuSeries`；内存指标和 `memorySeries` 在下面，标题仍是「内存」
- [ ] 网络页第一行是「当前进程网络暂不可用」；无主机数字、无 0、无网络曲线；CPU / 内存是原名辅助；内存曲线不叫网络
- [ ] 磁盘页顶上是该行 `diskReadBytesPerSecond` / `diskWriteBytesPerSecond`，标题「读取」「写入」；nil 为「—」，0 为「0 字节/秒」；不交叉；无磁盘曲线
- [ ] `.memory` 为 `.memoryExisting`，内存支仍有 `metrics` 和 `cpuChart`。`.gpu` 为 `.noResourceUpgrade`：无 GPU 主读数、无 GPU 曲线，内存曲线只作辅内存，不进入十七期内存分支
- [ ] 同一 detail 换页只变投影；每一支的 `memoryBytes` 与 `memorySeries.count` 等于输入；A/B pid 不串；输出不写回 VM / sampler / quit store
- [ ] 冻结卡换页只改标签和顺序。分子是旧详情的字节（例 8 GiB）。分母是该 `sidebarSubjectPid` 连续 live 最后一次 `> 0` 的总量（例 16 GiB，占比 50%），不是缺席帧先写入的 18 GiB。缺席时列表 `selectedPid` 变为 nil 不清这份分母；VM `detail` 被 `didSet` 清掉也不算换了侧栏主体。只有 `sidebarSubjectPid` 从 A 换成 B、`dismissSidebar`，或同一 pid 再次 live，才清。从未有过有效 live 总量则分母保持 nil。无 `frozenDetail` 不新卡。失败帧不清旧曲线。磁盘未知不是 0
- [ ] 不改十六期 quit 记录、token、generation；不新增 VM state 或 ring。不改 `selectedPid` 规则。内存→CPU 不因「仅上涨」而新清选中
- [ ] 刀①按上表写纯投影测试；刀②只做源码约束。二者都不是本文档 PR 的已执行项。Mac 未验。文档 diff 通过不是 `swift test` 已绿

实现等本设计合并 + Grok merge gate 后再写 Swift。本 PR 不写 Swift、不写测试、不合并。

核对后没有要退回产品的行为：`cpuSeries` 已在 `ProcessDetail` 上；主机网络不是 `networkMetricParts` 而是 `hostNetworkRates`；磁盘第一帧 nil 已是两帧差分。这三处都按源码写死，不另开待决。
