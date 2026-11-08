# Pulse 十九期技术设计（首包：磁盘页读取 / 写入分列排序）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 19 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。

> 一期至十八期正文不改写。五期磁盘 Tab 的默认合计降序、缺值用 `-1`、格子「—」不装 0，以及十八期「列表排序不在本刀 / 不改进程表」都保持原文。**本节只覆盖磁盘进程表两个已有表头的手动排序。** 不新采样、不新列、不新 VM 状态。

**已锁定**：进磁盘页、以及从其它页回到磁盘页，仍走现成 `DashboardNavigation.select`。页真的换了才把排序重置为 `ProcessTableSort.defaultSort(for: .disk)`，也就是今天的 `.disk`、`descending: true`。`.disk` 继续用 `ProcessRow.diskSortKey`：读、写两个 `Double?` 都有值才是两者之和，否则 `-1`。这组默认语义原样保留。默认合计没有自己的表头，两个磁盘表头在 `.disk` 时都不 active。

手动排序只增加两个列身份。读取表头的 column 实参是 `.diskRead`，比 `diskReadBytesPerSecond`。写入表头的 column 实参是 `.diskWrite`，比 `diskWriteBytesPerSecond`。两个实参都是字面量。点「写入」就按写入排序，点「读取」就按读取排序。比较用的缺数哨兵是该字段 `?? -1`，与现有 CPU / 合计磁盘的缺数风格一致。哨兵只存在于比较，不写回行、不交给 `DiskRateText`、不算占比。格子仍是 `DiskRateText`：真实 nil →「—」，真实 0 →「0 字节/秒」。默认降序时，缺这一列的行在真实 0 之后；手动升序时，缺这一列的行在真实 0 之前。不引入「缺数永远沉底」，也不加新 tooltip。

`.name` / `.cpu` / `.memory` / `.threads` 的 `selecting` 与比较不改。菜单栏 Top3 与内存页 Top5 publication 仍走原来的内存页 sort，不读磁盘页的 live `tableSort`。

来源：十九期主控已锁的分列排序；对照 `394128f9bced2342b03ba6294f8a47420dae9669`（`origin/main`，十八期实现 #60）。本节开写前读过的是这份树上的源码，不是口头转述。

本 PR 只追加本节，并在根 `README.md` 的既有期次索引里加半句导航。不写 Swift、不写测试、不跑 `swift test`、不合并、不改生产代码。下面的红绿步骤是实现 PR 的设计，不是本 PR 的执行结果。

## 已读源码（本 SHA）

| 位置 | 今天的事实 |
| --- | --- |
| `ProcessSortColumn` | `name` / `cpu` / `memory` / `threads` / `disk`。没有读、写分列 |
| `ProcessTableSort.defaultSort(for:)` | `.disk` → `column: .disk, descending: true`。`.cpu` / `.network` 为 CPU 降序；`.memory` / `.gpu` 为内存降序 |
| `selecting(_:)` | 列身份相同则 `descending` 取反。列身份不同：`.name` 从升序开始，其它列从降序开始 |
| `ordered(_:)` | 主列按 `descending`。主列相等则 `pid` 升序，`descending` 不翻转这个 tie-break。没有 PID 列 |
| `compare` 的 `.disk` | `compareDoubles(lhs.diskSortKey, rhs.diskSortKey)` |
| `diskSortKey` | `guard let diskReadBytesPerSecond, let diskWriteBytesPerSecond else { return -1 }`，否则两者相加 |
| `cpuSortKey` | `cpuPercent ?? -1`。CPU 缺数测试已锁：降序时真实 0 在 nil 前 |
| `ProcessTablePane` 磁盘表头 | 读取、写入两处都是 `sortHeader(..., column: .disk)`。`active` 为 `tableSort.column == column`，所以合计 `.disk` 时两个表头同时亮箭头 |
| `sortHeader` | 按钮调用 `setTableSort(tableSort.selecting(column))`。降序 `chevron.down`，升序 `chevron.up` |
| `sortedRows` | `tableSort.ordered(visibleRows)`。先过滤，后排序 |
| `visibleRows` | `MemoryGrowthRisingFilter.apply`：先 `ProcessNameFilter`；仅 `risingOnly && page == .memory` 才按徽标留下。磁盘页直接返回名称过滤结果 |
| 网络列表头 | `staticHeader(ProcessColumnTitle.network)`，不是 `sortHeader` |
| `setTableSort` | 只 `navigation.updateSort`，然后 `publishMemoryPageSort()`。函数体不写 `selectedPid`，不调用 `setSelectedPid`，不请求 `sample()` |
| `publishMemoryPageSort` | 仅 `selectedPage == .memory` 才写入 publication 并通知 Sampler。磁盘页是 `.skip` |
| `MemoryDashboardVM` 的 `@Published` | 22 处。`navigation` 已包含 sort。没有第二份排序状态机 |
| `DiskRateText.string` | nil →「—」（`NetworkRateText.missing`）；0 →「0 字节/秒」。与「暂不可用」不是同一句 |
| `DashboardNavigation.select` | 目标页不可选则整次返回。页没变（再次点当前页）不重置 sort。页变了才 `defaultSort(for:)` |
| `focusMemoryPage` | 落到内存页；页变了才把 sort 重置成内存默认 |
| `MenuBarPopoverSnapshot.topProcesses` | `sort.ordered(rows).prefix(3)`（`maxProcessRows = 3`）。调用方传 publication 的内存页 sort 和未过滤的 `rows` |
| GPU | `DashboardPage.gpu.isSelectable == false` |

五期验收里的「默认按合计磁盘速率降序；缺值沉底」只描述这条默认 `.disk` 降序：`-1` 小于真实 0，降序时缺值在真实 0 后面。它不是「升序也把缺数钉在表底」。十九期不改五期那一节的句子。十八期详情主读数、冻结分母、磁盘曲线不做，本节也不重开。

现有 `DiskPageTests.testDiskPageSortsByCombinedRateDescendingAndNilsSink` 用的是另一组五行：Busy App 读 40 写 10（合计 50）、idle helper 读 5 写 0（合计 5）、Zero 读 0 写 0（合计 0）、Missing 两路 nil（`-1`）、partial 读 80 写 nil（`-1`）。降序名字顺序是 Busy App、idle helper、Zero、Missing、partial。这组继续有效。十九期的数字验收不用它，也不另造「合计相等」的行来当默认例子。

## 范围

| 项 | 既有 | 十九期首包 |
| --- | --- | --- |
| 进入磁盘页 / 从其它页返回 | `select` 在页变化时重置为 `.disk` 降序 | **保持**。合计键仍是 `diskSortKey` |
| 再次点已经打开的磁盘页 | 保留手选 sort（现有单测：改成 `.name` 后再 `select(.disk)` 仍是 `.name`） | **保持**。手选 `.diskRead` / `.diskWrite` 同样保留 |
| 冷启动 | 内存页，内存默认降序 | **保持** |
| 菜单栏 `focusMemoryPage` | 内存页 + 内存默认 sort | **保持** |
| 读取 / 写入表头 | 两处都传 `.disk`，点哪一个都是合计比较 | **做**：实参分别为 `.diskRead` / `.diskWrite`。点该表头就按该列排序 |
| `.name` / `.cpu` / `.memory` / `.threads` | `selecting` + 现有比较 + pid tie-break | **不改** |
| 网络列 | `staticHeader`，文案「暂不可用」 | **仍不可点** |
| GPU | 不可选 | **仍不可选** |
| 菜单栏 Top3、内存 Top5、`MemoryPageSortPublication` | 只吃内存页已发布 sort | **不改路径** |
| VM `@Published` | 22 | **仍是 22**。不新状态机 |
| 格子文案 | `DiskRateText` | **不改格式化**。不加 tooltip |

一二至十八期验收不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 表头实参

`ProcessTablePane` 只改两处调用：

- 读取：`sortHeader(ProcessColumnTitle.diskRead, column: .diskRead, trailing: true)`
- 写入：`sortHeader(ProcessColumnTitle.diskWrite, column: .diskWrite, trailing: true)`

`sortHeader` 不改。它仍然调用 `setTableSort(tableSort.selecting(column))`，`active` 仍然是 `tableSort.column == column`。现有 `selecting` 因此就是：

- 从默认 `.disk` 降序第一次点「写入」这个表头：传入 `.diskWrite`，列身份不同，结果是 `.diskWrite` 降序。
- 从默认 `.disk` 降序第一次点「读取」这个表头：传入 `.diskRead`，结果是 `.diskRead` 降序。
- 再点同一个表头：列身份相同，`descending` 翻转。
- 换到另一个表头：新的 metric 从降序开始。`.name` 仍是第一次升序，这条原规则不动。

「第一次」指该表头。默认的 `.disk` 不是这两个表头的列。不存在表头第一次只把合计 `.disk` 翻转的行为。不增加纯函数，不增加存储，不记点击次数。

默认 `.disk` 时，两个磁盘表头的 `column ==` 都是假，所以都不 active。生效列变成 `.diskRead` 后只有读取 active；变成 `.diskWrite` 后只有写入 active。不新增合计表头。

## 数字验收

行的 pid 就是 P 后面的数字。速率是 `Double?` 的字节/秒，不是展示字符串。排序比较这些数（或缺数哨兵 `-1`）。展示在排序之后仍读原来的 Optional。

### a. 默认合计

只用这一组，不要换成合计相等的另一组：

| 行 | pid | 读 | 写 | `diskSortKey` |
| --- | --- | --- | --- | --- |
| P1 | 1 | 0 | 100 | 100 |
| P2 | 2 | 60 | 30 | 90 |
| P3 | 3 | 0 | 0 | 0 |

`.disk` 降序按 100、90、0，pid 顺序 **1, 2, 3**。三行两路都有值，没有 `-1`。这就是 `defaultSort(for: .disk)` 对这三行的结果，也是进入磁盘页时的排序。

### b. 点「写入」和点「读取」

同一组 P1 / P2 / P3。第一次点的是该表头，不是默认的 `.disk` 列。

| 步骤 | 操作 | 生效 sort | 顺序依据 | pid 顺序 |
| --- | --- | --- | --- | --- |
| default | 进入磁盘页 | `.disk` 降序 | 合计 100、90、0 | **1, 2, 3** |
| 1 | 第一次点「写入」 | `.diskWrite` 降序 | 写 100、30、0 | **1, 2, 3** |
| 2 | 再点「写入」 | `.diskWrite` 升序 | 写 0、30、100 | **3, 2, 1** |
| 3 | 再点「读取」 | `.diskRead` 降序 | 读 60，然后两个真实 0 按 pid 1 再 3 | **2, 1, 3** |

从 default 直接第一次点「读取」这个表头，也是 `.diskRead` 降序，pid 顺序 **2, 1, 3**。两个读 0 是 pid 1 与 pid 3，降序不把 tie-break 翻成 3 再 1。

### c. 读缺数，以及写缺数的独立组

读缺数组（不拿去当 a 的默认合计例子）：

| 行 | pid | 读 | 写 | 读排序键 | 写排序键 | 读格子 | 写格子 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P1 | 1 | nil | 50 | -1 | 50 | — | `DiskRateText` 的 50，不是「—」也不是 0 |
| P2 | 2 | 0 | 20 | 0 | 20 | 0 字节/秒 | 真实 20 的格式 |
| P3 | 3 | 0 | 0 | 0 | 0 | 0 字节/秒 | 0 字节/秒 |

- `.diskRead` 降序：**2, 3, 1**。两个真实 0 按 pid 2 再 3，nil 在它们后面。
- `.diskRead` 升序：**1, 2, 3**。nil 在两个真实 0 前面，0 仍是 pid 2 再 3。
- `.diskWrite` 降序：**1, 2, 3**。写 50、20、0。
- `.diskWrite` 升序：**3, 2, 1**。

P1 的 `diskSortKey` 是 `-1`，因为合计要两路都有值。这只说明它不参加 a 组的合计例子。写排序仍用 50，不因为读是 nil 就丢掉整行，也不把写改成 nil 或 0。读格子保持「—」。

这一组的写都有值。写入缺数另用独立四行，仍不替换 a 组：

| 行 | pid | 读 | 写 | 写排序键 | 写格子 |
| --- | --- | --- | --- | --- | --- |
| P4 | 4 | 0 | nil | -1 | — |
| P5 | 5 | 0 | 0 | 0 | 0 字节/秒 |
| P7 | 7 | 0 | 0 | 0 | 0 字节/秒 |
| P6 | 6 | 0 | 10 | 10 | 真实 10 的格式 |

- `.diskWrite` 降序：**6, 5, 7, 4**。真实 10，然后两个真实 0（pid 5 再 7），nil 在真实 0 之后。
- `.diskWrite` 升序：**4, 5, 7, 6**。nil 在真实 0 之前；两个 0 仍是 pid 5 再 7，降序没有把它们翻成 7 再 5。

P4 的读格子仍是「0 字节/秒」。写 nil 不删行，也不把读涂成「—」。排序后这四行的 `diskWriteBytesPerSecond` 仍是原来的 nil / 0 / 0 / 10，不是 `-1`。

### d. 同值 tie-break

主列相等时按 pid 升序，`descending` 不翻转。至少两组真实 0：

- a 组的读：P1 与 P3 都是真实 0。`.diskRead` 降序是 2, 1, 3；若再翻成升序，两个 0 仍是 pid 1 再 3，整序为 **1, 3, 2**。
- c 组的读：P2 与 P3 都是真实 0。降序 2, 3, 1；升序 1, 2, 3。两种方向都是 pid 2 在 pid 3 前。
- 独立写缺数组：P5 与 P7 都是真实写 0。降序与升序都是 pid 5 在 pid 7 前。

P1 读 nil 只影响读排序键和合计 `diskSortKey`。它的写 50 照常参加写排序。

### e. 过滤在前，排序不碰选中与冻结

主窗顺序是 `visibleRows`，然后同一个 `ordered`。`visibleRows` 就是 `MemoryGrowthRisingFilter.apply`（内部先 `ProcessNameFilter`）。排序函数不调用 `apply`，不读 `filter` / `risingOnlyFilter`，不新开过滤入口。

用 a 组三行，名称分别是 `aaa`、`bbb`、`ccc`：

- 名称查询 `b`：只剩 pid 2，再 `ordered` 仍只有 pid 2。
- 查询空白：三行都在。`.disk` 降序仍是 1, 2, 3。
- 磁盘页即使 `risingOnly == true`，`apply` 也因 `page != .memory` 返回名称过滤结果，不按上涨徽标删行。内存页的上涨过滤不改。

`setTableSort` 不写 `selectedPid`，不写 `detail`，不调用 `sampler.setSelectedPid`，不请求采样。选中 pid 2 时走完 b 的点击，选中仍是 pid 2。`ordered` 的入参行在调用后字段不变（含两个磁盘 Optional）。比较函数不接收 `ProcessDetail` / `frozenDetail`。冻结卡上的字节和速率不会因为比较器跑了一次而变。这条用源码约束核对，不是 GUI。

磁盘页上的 `publishMemoryPageSort` 仍是 `.skip`：publication 里的内存页 sort 不变，Sampler 的 `setMemoryPageSort` 不因磁盘表头点击而收到新值。菜单栏 Top3 仍是那份内存 sort 的 `prefix(3)`。内存页 Top5 的 publication 路径不改。

## 其它页与导航（保持）

- 冷启动：`DashboardNavigation()` 的页是 `.memory`，sort 是内存默认降序。
- `select(.disk)` 从内存 / CPU / 网络进来：页变为磁盘，sort 为 `.disk` 降序。
- 在磁盘页把 sort 改成 `.diskWrite` 或 `.name` 后再 `select(.disk)`：页不变，手选保留。
- `select(.gpu)`：页与 sort 都不变。
- `focusMemoryPage()`：页为内存，sort 为内存默认。
- 名称第一次进入为升序，CPU / 内存 / 线程第一次进入为降序，再点翻转；相等按 pid 升序。CPU nil 仍是 `cpuSortKey == -1`，降序时在真实 0 后。这些现有断言不放宽。
- 网络列仍是 `staticHeader`。磁盘页以外不出现读取 / 写入列，也不出现 `.diskRead` / `.diskWrite` 的表头。

## 明确不做

- 不改 `MemorySampler`、`proc_pid_rusage`、两帧差分、速率周期、`ProcessEnumerator`、主机 IOKit 磁盘
- 不新进程枚举、不新 IO、不新身份 / 退出 / 冻结详情、不改资源详情投影与侧栏主读数
- 不改总览、曲线、`diskHistory`、`SystemDiskHistory`、网络、GPU
- 不改增长 Top5、`MemoryGrowthRisingFilter` 的内存页规则、过滤空态文案
- 不改菜单栏 Top3、`MemoryPageSortPublication`、`menuBarPopover` 的入参
- 不持久化 sort，不加 PID 列，不加列宽 / 颜色 / 整套网络进程速率
- 不把 `-1` 写进行，不把 nil 显示成 0，不把真实 0 显示成「—」
- 不新增 VM `@Published`（现 22），不新增 `@Published lastMemorySort` 或其它排序状态机
- 不改公证脚本与 entitlements

## 实施指导

只做这两处，不另加纯函数或存储：

1. 在现有 `ProcessSortColumn` 上增加 `.diskRead`、`.diskWrite`。`defaultSort(for: .disk)` 仍返回 `.disk` 降序。`.disk` 的 `compare` 分支仍调用 `diskSortKey`，函数体不改。两个新分支就地比较 `diskReadBytesPerSecond ?? -1` 与 `diskWriteBytesPerSecond ?? -1`，交给现有 `compareDoubles`。不改 `ProcessRow` 的存储。
2. `ProcessTablePane` 的读取表头实参改为 `.diskRead`，写入表头实参改为 `.diskWrite`。`sortedRows` 与 `sortHeader` 不改。`MemoryDashboardVM.setTableSort` 不改，`@Published` 仍是 22。

只改已有文件时，不改 `Package.swift` 的 `sources`，不改 `project.pbxproj` 的文件注册。`CPUPage.swift` 与 `DiskPageTests.swift` 都已经在对应目标里。没有必要就不要新增测试文件或模型文件。

## 测试矩阵（设计；本 PR 不写、不跑）

实现 PR 的红绿必须是真的编译失败，再真的跑通。本环境没有执行 `swift test`。不要把本节写成「已经绿了」。

**红：** 生产枚举还没有 `.diskRead` / `.diskWrite` 时，先在已有 `DiskPageTests.swift` 里加上面的 focused 断言，直接使用 `ProcessSortColumn.diskRead` / `.diskWrite` 和生产 `ProcessTableSort`。然后跑 focused。此时的失败应是编译错误（`ProcessSortColumn` 没有这两个成员）。这就是红。禁止用 `XCTFail`、测试里另造一份假枚举、`#if` 藏掉新 case、或改写一个已经通过的旧断言来伪装红。

**绿：** 补上两个 case 和两个 `compare` 分支，并把两处表头实参改成 `.diskRead` / `.diskWrite`，使同一批 focused 编译并通过。然后再跑全量 `swift test`。实现 PR 要留下 focused 与全量各自的真实日志和通过计数。本设计 PR 没有这些数字。

Focused 放在 `DiskPageTests`（或确有必要时的一个新测试文件；优先不要新文件）。至少覆盖：

1. a 组 `.disk` 降序 pid 1, 2, 3，且 `defaultSort(for: .disk)` 仍是 `.disk` 降序。
2. 从 default 调用 `selecting(.diskWrite)` 得到 `.diskWrite` 降序、pid 1, 2, 3；再 `selecting(.diskWrite)` 得到升序、pid 3, 2, 1；再 `selecting(.diskRead)` 得到降序、pid 2, 1, 3。从 default 直接 `selecting(.diskRead)` 也是降序、pid 2, 1, 3。
3. c 的读缺数四条顺序，以及独立写缺数的降序 6, 5, 7, 4 与升序 4, 5, 7, 6。排序后 nil 行的 Optional 仍是 nil，`DiskRateText.string(nil)` 仍是「—」，`DiskRateText.string(0)` 仍是「0 字节/秒」。
4. d 的真实 0：a 组读升序 1, 3, 2；c 组两个方向都是 pid 2 在 3 前；写缺数组两个方向都是 pid 5 在 7 前。
5. e：`ProcessNameFilter` / `MemoryGrowthRisingFilter.apply` 之后再 `ordered`。查询 `b` 只剩 pid 2。磁盘页 `risingOnly == true` 仍不按徽标删行。`ordered` 不改行的磁盘字段。

既有测试默认不放宽：

- `DiskPageTests` 的五行合计降序、冷启动内存、再次进入磁盘页保留手选、`focusMemoryPage` 回内存、GPU 不可选、nil 与真实 0 的文案，期望保持。
- `ProcessTableSortTests` 里名称 / CPU / 内存 / 线程的 pid tie-break 数组仍是这四列，不把磁盘列塞进去充数，也不删掉这些断言。磁盘 tie-break 写在十九期 focused 里。
- `CPUPageTests` 的 CPU nil 在真实 0 后、各页 `defaultSort`、GPU 不可选，不放宽。
- `MemoryDashboardVMSortWiringSourceTests` 继续锁：SamplingCore 排除 `ViewModels`、包文件不收录 `MemoryDashboardVM.swift`、一份未 `@Published` 的 publication、弹出条用 `publication.sort` 与 `rows`、不 `await` Sampler 来刷菜单栏、`setTableSort` 等入口仍走 `publishMemoryPageSort()`。这些断言不删、不改松。

可以在这个源码测试里**加**精确断言，并写明它不是 GUI、也不实例化 VM：

- `ProcessTablePane.swift` 读取表头的实参是字面量 `.diskRead`，写入表头的实参是字面量 `.diskWrite`。两处都不再是 `.disk`。`sortHeader` 的函数体仍是 `selecting(column)` 与 `tableSort.column == column`。
- 网络列仍是 `staticHeader`。
- `setTableSort` 的函数体不含 `selectedPid` 赋值、不含 `setSelectedPid`、不含 `sample()`。
- `MemoryDashboardVM.swift` 的 `@Published` 仍是 22 处，且没有新的排序 `@Published`。
- `ProcessTableSort` 的比较源码不引用 `ProcessDetail`、`frozenDetail`、`selectedPid`、`sampler`。

源码断言通过不等于 Mac 上点过表头，也不等于箭头位置已看过。

## 风险

| 风险 | 应对 |
| --- | --- |
| 写入表头仍传 `.disk`，第一次点「写入」变成合计升序 | 实参是字面量 `.diskWrite`。第一次点这个表头就是 `.diskWrite` 降序 |
| 为默认合计另做表头，或让 `.disk` 时两个磁盘表头 active | 不新增合计表头。默认两个 `column ==` 都为假 |
| 用纯函数或点击计数决定表头实参 | 两处实参是字面量。不增加纯函数或存储 |
| 升序仍把 nil 排到真实 0 后面，或加一句「永远沉底」 | 哨兵 `-1`。降序在 0 后，升序在 0 前。不加 tooltip |
| 用 `-1` 替换格子或删掉缺一路的行 | 格子仍 `DiskRateText`。P1 读 nil 仍以写 50 参加写排序。P4 写 nil 仍留在表里 |
| 排序时过滤、改 `selectedPid`、请求采样 | `ordered(visibleRows)`。`setTableSort` 不写选中、不 `sample` |
| 磁盘表头把 publication / Top5 / Top3 改掉 | 非内存页 `publish` 为 `.skip`。不改调用点 |
| 为接线去改 `diskSortKey`、Sampler 或详情 | `diskSortKey` 函数体不动。详情与采样不在本刀 |
| 放宽旧测试来让新 case 编译 | 旧断言保持。新行为只加 focused |
| 把源码测试或 CodeRabbit 的限流 / skipped / neutral 当成审查通过 | 源码测试不是 GUI。限流、跳过、中立不是通过。Linux 以真实 `swift test` 日志为准 |

## 验收

- [ ] 进入磁盘页和从其它页返回仍是 `.disk` 降序，合计键仍是 `diskSortKey`（两路都有值才相加，否则 `-1`）。冷启动仍是内存页。再次点当前磁盘页保留手选。`focusMemoryPage` 仍回内存默认。GPU 仍不可选
- [ ] a 组 `.disk` 降序 pid 为 1, 2, 3。不用另一组合计相等的行代替
- [ ] 读取表头实参是 `.diskRead`，写入表头实参是 `.diskWrite`。从 default 第一次点「写入」是 `.diskWrite` 降序 1, 2, 3；再点「写入」是升序 3, 2, 1；再点「读取」是 `.diskRead` 降序 2, 1, 3。从 default 第一次点「读取」也是 `.diskRead` 降序 2, 1, 3。默认 `.disk` 时两个磁盘表头都不 active。`sortHeader` 不改，不新增纯函数或状态
- [ ] c：读缺数 `.diskRead` 降序 2, 3, 1、升序 1, 2, 3；`.diskWrite` 降序 1, 2, 3、升序 3, 2, 1。独立写缺数降序 6, 5, 7, 4、升序 4, 5, 7, 6。nil 格子「—」，真实 0 格子「0 字节/秒」。一路 nil 不删行
- [ ] 真实 0 的 tie-break 为 pid 升序，降序不翻转。P1 的读 nil 不影响写 50
- [ ] 名称过滤与内存页上涨过滤仍先于 `ordered`。磁盘页不因 `risingOnly` 删行。排序不改行、不写 `selectedPid`、不请求采样。冻结详情不因比较器变化
- [ ] `.name` / `.cpu` / `.memory` / `.threads`、网络静态列、菜单栏 Top3、内存 Top5 publication 的原路径不改。`@Published` 仍是 22。无新状态机
- [ ] 实现 PR 先有编译失败的 focused 红，再有 Linux focused 与全量 `swift test` 的真实计数和日志。不放宽列出的既有测试。源码断言不称作 GUI

## Linux 已测与未验

本 PR 不跑测试。实现 PR 在 Linux 上应能执行的是 SamplingCore：`ProcessTableSort`、`diskSortKey`、`DiskRateText`、`DashboardNavigation`、`MemoryGrowthRisingFilter`、`MemoryPageSortPublication`。`selecting(.diskRead)` / `selecting(.diskWrite)` 就在这一层。`ProcessTablePane` 与 `MemoryDashboardVM` 不在这个目标里，两处字面量用源码阅读断言。

未验，不挡本设计合并，实现 PR 在 Linux 上也不能把它们勾成已过：

- Mac 上点「写入」「读取」以及表头箭头
- Xcode 编译 App、`project.pbxproj` 下的实际运行
- 本设计 PR 没有 CodeRabbit 结论。实现 PR 若见限流、skipped 或 neutral，不算审查通过

实现等本设计合并 + Grok merge gate 后再写 Swift。本 PR 不写 Swift、不写测试、不合并。
