# 保存当前快照：技术设计（未实现）

> 首版行为已由产品、设计和主控锁定。本文件把该锁定收成工程决定。它仍不是实现授权，也不是 `main` 上的行为。
>
> 对照提交 `930bac1eeab468bc9de677581c233199b6f1f9c9`。开写前读过 PRD、TECH、ADR-0001、ADR-0002，以及 PR #111（仍开着，头是本文；评论里没有另一份同题收口）。规格里已有的「快照」是采样帧 `MemorySnapshot` / `SampledFrame`，不是用户保存的现场。
>
> 文件名的 `31` 只用来接在 `00`–`22` 之后，并避开已经落地、没有单独设计稿的二十三至三十期。这不是三十一期立项。
>
> 早先稿里的 P/Q/R 候选、`SavedScene` JSON、未知版本拒绝和「应用内解码再回看」作废。应用不解码这份文件，也不做迁移框架。

## 锁定的首版

手动点击「保存当前快照」。点击时在主线程同步冻结最近一帧已经发布的有效采样。不新采样，不扫描。

有效帧是 `MemoryDashboardVM.snapshot != nil` 的那一份已发布主机快照，以及同一次发布里的 `rows`、主机 CPU、网络和磁盘。`samplingFailed == true` 时仍然冻结这上一份，采样时间保持 `snapshot.capturedAt`，不用点击时间冒充新的采样。`snapshot == nil` 时没有有效帧。

入口是主窗工具栏按钮，各页都在，包括本机页。它不放进过滤胶囊那一组，也不跟随「仅上涨」「仅窗口 App」「按 App」。

点击后先给只读预览，再由预览里的「保存到本机」打开系统保存对话框。预览不是回看窗口。回看是用户稍后用系统打开那个文件。

预览和文件展示同一份导出文档，内容是：

- 采样时间 `capturedAt`，保存时间 `savedAt`（点击冻结的时刻）。二者分开写。
- 一句「非实时」。
- 主机内存（已用、总量、四段分类、交换）、压力两档、整机 CPU、最忙一核、网络下行/上行、磁盘读取/写入。这些都是这一帧已经发布的数。
- 进程最多 5 行。来源是完整、未过滤的 `rows`，按内存占用降序。不是当前表头排序，不是过滤后的表，也不是按 App 合并后的行。
- 不足 5 个时写明实际个数，不补假行。进程列表没读到时写明没读到，不把空表说成机器上只有 0 个进程。
- 名次只表示内存占用顺序，不表示卡顿原因。

每一行只有：pid、显示名、内存字节、内存来源（`footprint` 为内存占用，`resident` 为驻留内存）、CPU%、线程数。不写进程磁盘、能耗、唤醒，不写曲线、可执行路径、包标识或命令行。

「隐藏进程名」同时作用于预览和将要写入的文件。开关一变，预览立刻变成文件会保存的内容。打开时文件里不得留下原名。冻结下来的原始采样不因这个开关改写。

缺失在预览里写「不可用」，文件里用同一个词。真实 0 仍按现有格式化显示成 0，不用「不可用」顶替。主窗其它位置的缺数仍是「—」；不改 `CPUPercentText.missing`。

取消预览，或取消系统保存对话框，都不写文件。保存失败时留下同一份冻结和预览，可以再选位置；不重新取样。只有目标文件已经替换成功才显示「已保存」。覆盖只发生在系统保存面板已经让用户确认替换之后，应用不静默覆盖。

没有有效帧时，点击只提示「暂无可保存的采样，请稍后重试」。不打开空预览，不生成文件。

预览里的 pid 不能退出、不能强制退出、不能定位、不能 `setSelectedPid`。保存之后 pid 可能被系统复用。

## 明确不做

- 不新增采样，不为保存调用 `MemorySampler.sample()`、`HostMachineReader.read()`、`ProcessEnumerator` 或 `WindowedAppLookup`。
- 不追溯点击之前的历史，不把已有曲线写进文件，不长期录制。
- 不调用 `MemoryGrowthSignal.evaluate`，不做自动判因或泄漏结论。
- 不上传、不分发、不分享。
- 不做历史列表、快照库、对比、覆盖管理，也不做应用内导入、查看入口、只读回看窗口或内嵌浏览器。
- 不改采样节奏、过滤、排序、退出和其它页的既有行为。
- 不夹带空态文案、窗口 frame autosave，不处理 #74。
- 不给 `MemorySnapshot`、`ProcessRow`、`SampledFrame` 加 `Codable`。

## 冻结哪一份数据

`930bac1` 上只有一条采样通路。`MemorySampler.sample()` 产出不可变 `SampledFrame`。`MemoryDashboardVM.applySample` 在 `@MainActor` 上发布。只有 `SamplingRequestGate.accept` 接受的成功帧才改 `snapshot`、`systemCpuPercent`、`busiestCorePercent`、`hostNetworkRates`、`hostDiskRates`、`rows`。失败的已接受帧只把 `samplingFailed` 设为 true，保留上一份数字。未接受的 flight 不写这些字段。

冻结函数是 `@MainActor` 同步函数。开头把要用的发布值抄进局部常量，函数体内没有 `await`。它不读 `MemorySampler` 的私有 tick、上一帧计数器或选中曲线。`SamplingRequestGate.currentFlight` 没有发布到 VM；在途采样不打断这次冻结，稍后 `accept` 也不改已经冻结的值。`isRetrying` 同样不把点击时间写成新的采样时间。

不要用 `MenuBarPopoverSnapshot.project`。`samplingFailed == true` 时该投影把压力和已用内存收成 `nil`，进程行却可能还在，会把「上一帧还在」写成「主机数缺失」。

不要用 `sortedRows`、`visibleRows`、`AppGroupProjection`、`TopConsumer.leading`、`MemoryGrowthTopSeries` 或菜单栏 Top3。`topMemorySeries` 跟着内存页表头排序，最多 5 条，还会丢掉掉出前 5 的 pid，和这次的「未过滤、按内存」不是同一套。

`thermalNotice` 和 `machineFacts` 没有 `capturedAt`。前者随热状态通知变化，后者只在本机页打开后每 30 秒读一次。二者都不进入冻结值。

`rows` 只在成功帧里被赋值为 `frame.rows`。进程列表失败时这一帧仍成功：主机数是新的，`rows` 为空，`processListFailed == true`。冻结沿用这个空表，不把上一帧进程补回来。

### 不是同一物理瞬间

`capturedAt` 取在主机内存读成功之后（`MemorySampler.swift`）。同一次 `sample()` 里，交换、整机 CPU、最忙一核、网络、磁盘和 `proc_listpids` 都发生在这个时间点之后。CPU、网络、磁盘速率是相邻已接受帧的差值，标签落在这次 `capturedAt` 上，不是瞬间值。进程计数器读得更晚。交换可以单独缺失。压力只保存已经判定的 `normal` / `elevated`，保存时不重读内核压力。

`savedAt` 是点击冻结的时间，由调用方传入。它和 `capturedAt` 都不再在预览或写文件时另取时钟。

已用字节沿用 `snapshot.usedBytes`（已对总量做过上限截断）。四段分类单独抄 `MemoryBreakdown`，不把它们重新加成已用。非有限浮点在做成文档之前视为缺失，不写成 0。

## 导出文档

独立类型，建议名 `SnapshotExport`。原始冻结值只留这次要的字段，从拷贝时就没有 `executablePath`、`bundleIdentifier`、曲线和命令行。显示名留在冻结值里，供开关关闭时使用。

`SnapshotDocument.make(frozen:hideNames:calendar:timeZone:)` 是纯函数，产出预览和文件共用的字符串。格式化只发生在这里。预览不再调用 `ByteFormat` 或 `CPUPercentText`。HTML 不再做第二次数字格式化。

| 文档字段 | 规则 |
| --- | --- |
| 采样时间、保存时间 | 同一套日历和时区格式化。预览和文件用这两条已经格式化的字符串 |
| 非实时 | 固定句「非实时。采样时间不是现在，也不是打开文件的时间。」 |
| 速率 | 固定句「CPU、网络和磁盘速率是到采样时间为止的一段差值，不是同一瞬间的读数。」 |
| `samplingFailed` | 固定句「更晚的采样没有回来。下面仍是上一次已发布的读数，采样时间没有改成保存时间。」不改 `capturedAt` |
| 内存、压力、CPU、最忙一核、网络两侧、磁盘两侧、交换 | 缺失为「不可用」。真实 0 走现有格式：内存 `ByteFormat.memory` 的「0 字节」，CPU `CPUPercentText` 的「0.0%」，速率「0 字节/秒」 |
| 压力 | `PressureLevel.title`：「正常」或「偏高」 |
| 内存来源 | 内存占用，或驻留内存 |
| 进程名 | `hideNames == false` 时用冻结的显示名；`true` 时用固定词「已隐藏」 |
| 不足 5 且列表成功 | 「当前只有 N 个进程。」N 是这一帧 `rows.count`，可以是 0 |
| 列表失败 | 「进程列表没有读到。」进程区为空，不写「当前只有 0 个进程。」 |
| 名次 | 固定句「名次只按内存占用排列，不表示卡顿原因。」 |

前 5 的排序由导出函数自己做：`memoryBytes` 降序，相同则 `pid` 升序，再取前缀 5。不依赖 `rows` 今天碰巧已是这个顺序。同名进程保持多行，不按 App 相加。

`hideNames` 只影响 `SnapshotDocument`。再次 `make` 时仍读同一份冻结值。开关的无障碍值用「开」「关」。默认关，预览先显示名称；这是「可隐藏」，不是默认抹掉名称。

## 预览

工具栏在 `MemoryDashboardView` 的 `.toolbar` 里单独加一个 `ToolbarItem`，标题「保存当前快照」。不要放进现有 `ToolbarItemGroup(placement: .primaryAction)` 的过滤 `HStack`：那个组在本机页整组消失，而且动画绑着 `selectedPage`。

`snapshot == nil`：不创建冻结值，不 present 预览，不打开保存面板。提示全文就是「暂无可保存的采样，请稍后重试」。这不是采样失败空态，不复用 `SamplingRetryChrome`。

有有效帧：冻结，然后在主窗上 present 只读 sheet。sheet 只读 `SnapshotDocument`。进程行不是按钮。sheet 上有「隐藏进程名」开关、「保存到本机」和取消。

取消 sheet：丢掉冻结值，不写文件。

「保存到本机」才创建 `NSSavePanel`。面板打开期间 VM 可以继续采样，冻结值不变。`savedAt` 也不改成确认面板的时间。

取消面板：不写文件，sheet 和冻结值留着，可以再点「保存到本机」。

写入失败：不显示「已保存」。sheet 留着同一份文档，说明「没能写入所选位置。这一份采样还在，可以再试。」用户再点「保存到本机」仍用这份冻结值。

写入成功：在同一 sheet 显示「已保存」。在替换成功之前不得显示这四个字。应用不调用 `NSWorkspace.open`，避免把「已保存」说成「已经打开」。

主窗在 sheet 打开时继续按原来的 1.5 秒 / 3 秒采样。sheet 不跟随新帧。

## 文件格式

文件是一份自包含的 UTF-8 HTML，扩展名 `.html`。Finder 双击后由系统交给默认浏览器阅读。这是回看路径。

选择 HTML，是因为要在不装额外应用的 Mac 上打开就能阅读。JSON 或 Markdown 在系统里通常只是源码。PDF 需要单独的生成器，纯文本没有标题和表。应用内的 `WKWebView` 不采用。

约束：

- 生成器只写固定标签：`html`、`head`、`body`、`meta`、`title`、`style`、`h1`、`p`、`h2`、`table`、`thead`、`tbody`、`tr`、`th`、`td`。
- `<title>` 固定为「Pulse 采样」，不含进程名或路径。
- CSS 是生成器里的常量，不插入采样文本。
- 不写 `<script>`，不写事件处理属性，不写 `href`、`src`、`javascript:` 或 `data:`。进程名即使看起来像网址，也只是正文，不做成链接。
- 不引用远程样式、字体、图片或脚本。
- 采样文本只经转义函数进入正文。转义至少包括 `&`、`<`、`>`、`"`、`'`，以及 NUL、U+2028、U+2029。
- 隐藏进程名时，原名不得出现在正文、注释、属性或文件名的任何位置。
- 应用没有这份 HTML 的解码器，没有 schema 版本分支，没有未知版本迁移。

默认文件名用保存时间，形如 `Pulse-快照-yyyyMMdd-HHmmss.html`。文件名不含进程名。`NSSavePanel` 允许的类型是 HTML。不关闭系统自带的替换确认。

## 写入

字节先在内存里完成。生成失败则不碰目标路径。

然后在目标的同一目录写临时文件，关闭后再替换到目标。替换失败时删掉还留着的临时文件，目标原有字节保持不变。成功后目录里不留临时文件。

不写 UserDefaults，不写应用自管的快照目录，不维护索引。不加密。不为这件事加 entitlement。非沙盒保持现状。

## 模块边界

不增加 Swift 包。HTML 和转义只用 Foundation，放进 `SamplingCore`，方便 `swift test`。保存面板留在 App target。

`Package.swift` 用显式 `sources`，并整目录排除 `ViewModels/`、`Views/`。`Pulse.xcodeproj` 没有同步文件夹。将来的实现要同时登记：

| 将来的文件 | 包 | 工程 |
| --- | --- | --- |
| `Pulse/Models/SnapshotExport.swift`（冻结投影、文档、转义、HTML） | 写入 `sources` | `PBXBuildFile`、`PBXFileReference`、Models group、Sources |
| `Pulse/Models/SnapshotExportFile.swift`（临时文件和替换） | 写入 `sources` | 同上 |
| `Pulse/ViewModels/MemoryDashboardVM+SnapshotExport.swift`（同步冻结） | 不用写。`ViewModels` 已排除 | ViewModels group 与 Sources |
| `Pulse/Views/SnapshotExportPreview.swift`（保存前的只读 sheet） | 不用写。`Views` 已排除 | Views group 与 Sources |

工具栏按钮改在已有的 `MemoryDashboardView.swift`，该文件已经在工程里。不新增第二套 VM。

本设计不创建这些 Swift 文件。

## 实现时的验收与红绿顺序

下面是以后那个实现 PR 的顺序，不是本 PR 的结果。本环境没有执行这些测试。文档 PR 的 CI 通过也不表示 Mac 上的预览、保存面板或 VoiceOver 已经通过。

先加会失败的 `SnapshotExportTests`，再写模型：

- 预览字符串和 HTML 正文来自同一次 `SnapshotDocument`。同一缺失字段两边都是「不可用」；同一真实 0 两边都是格式化后的 0，不是「不可用」。
- 交换、CPU、网络一侧、磁盘一侧可以单独缺失，另一侧的 0 不受影响。
- 非有限浮点变成「不可用」，不是 0。
- `samplingFailed == true` 时，文档里的采样时间仍是输入的 `capturedAt`，保存时间是输入的 `savedAt`。
- `snapshot == nil` 的门闩不产生文档。调用方只得到「暂无可保存的采样，请稍后重试」。
- 前 5 使用未过滤行，按内存降序、pid 升序。当前表头若是 CPU 排序、名称过滤开着、或「按 App」开着，结果仍是原来的 5 个 pid，同名进程不合并。
- 列表成功且不足 5 时出现「当前只有 N 个进程。」列表失败时出现「进程列表没有读到。」且没有进程行。
- 名次说明句在文档和 HTML 里都在。
- `hideNames == true` 时，预览名称和 HTML 全文都不含原名，名称处是「已隐藏」。用带 `<script>`、引号和 `https://` 的哨兵名做这一条。
- `hideNames == false` 时，哨兵名只以转义形式出现：`<` 变成 `&lt;`，HTML 里没有 `<script`、事件属性、`href` 或 `src`。
- HTML 不含路径、包标识、曲线点、进程磁盘、能耗和唤醒字段名或哨兵值。
- 纯函数不读时钟：两个时间都由调用方传入。

再为替换加会失败的测试：目标已有内容时，生成失败或替换前写入失败不改变目标字节；成功后目标是这份 HTML，目录里不留临时文件。

接线测试沿用 `WiringSourceText`，只证明源码约束，不是 SwiftUI，也不是 VoiceOver：

- 冻结函数没有 `sample()`、`HostMachineReader.read()`、`ProcessEnumerator`。
- 工具栏按钮不在过滤 `HStack` 内，本机页分支不会把它一起藏掉。
- 预览和写文件都接收 `SnapshotDocument`，不存在「界面用占位、HTML 仍写 `row.name`」的第二条路径。
- 预览类型里没有 `quitSelected`、`forceTerminate`、`selectPidIfPresent`、`NSWorkspace.open`。
- 「已保存」只出现在写入成功的分支。

Mac 上要另做、且本设计未做的检查：工具栏在各页可点、预览与隐藏开关、系统保存面板的取消和替换确认、Finder 双击打开的页面没有脚本和远程请求、VoiceOver 能读到「非实时」、采样时间和「不可用」。实现 PR 再把真正跑过和没跑的步骤写进 `docs/TECH.md` 冒烟清单。本文不改那份清单。

## 本设计不改的文档

`docs/TECH.md` 仍只描述 `main` 上已有的实现。能力还没落地，所以不往 TECH 里追加一期。

`docs/PRD.md` 和根 `README.md` 的当前范围也不改。等实现 PR 落地时再改。

不新增 ADR。内存占用仍是 ADR-0001，能耗和唤醒仍是 ADR-0002。这次保存不使用进程磁盘、能耗和唤醒，也不改变它们的口径。

不改 `docs/specs/00`–`22` 的正文。
