> 已落地。当前行为以 [TECH.md](../TECH.md) 的「能耗页」为准。本稿停改。#139 的小时排行、已退出进程和 4 小时曲线在 `docs/TECH.md`「能耗页」；本稿停在 #140。本机冒烟清单对应条目仍未勾选：实现时没有在 Mac 上打开过这个页面。

# 能耗页骨架与 1 分钟排行（未实现）

> 落地前的技术约定，对应用户 issue [#140](https://github.com/qqzhangyanhua/pulse/issues/140)（父 issue [#138](https://github.com/qqzhangyanhua/pulse/issues/138) 的第一刀）。它不是实现授权，也不是 `4e48c010b52fe2385aa58c5424ec0b98136bbe5c` 上已经存在的页面。
>
> 开写时 `origin/main` 就是这个提交，父提交 `0b59b58`（#137）。没有更晚提交。口径以 [ADR-0002](../adr/0002-process-energy-wakeups.md) 和该提交上的源码为准。本文不修改 ADR。
>
> 文件名按 #140 原文使用 `35-energy-page.md`。已经落地的 [35-memory-group-row-copy.md](35-memory-group-row-copy.md) 仍占着前缀 35，两份稿互不替换。文件号不是期次立项。
>
> 落地后，当前行为以 [TECH.md](../TECH.md) 的「能耗页」为准；两处在落地前必须一致。本稿到落地后停改。本机冒烟清单的对应条目保持未勾选。这份文档 PR 没有 Swift 改动，没有跑行为红绿，也没有在 Mac 上打开过这个页面。

## 范围

只做运行中进程的最近 1 分钟排行：

- 标签栏在 CPU 之后出现「能耗」，符号 `bolt`。
- 表格三列：名称、能耗影响、唤醒。默认为能耗影响降序。三列都能排序，名称能搜索。
- 能耗列是窗口内累计能耗除以有效时长，单位瓦特。不足 1 分钟用已经采到的有效时长。无基线或本帧缺读数是 nil，界面「—」，不补 0。真实有效的 0 不是缺失。
- 复用现有一次 `proc_pid_rusage`。CPU 页的能耗 / 唤醒两列、本机页电池信息保持今天的行为。

不做，也不要在这一刀里搭半套：

- #141 按 App、详情侧栏、结束进程
- #142 电池卡片与剩余时间
- #143 分钟桶和 1 小时切换
- #144 已退出进程保留
- #145 4 小时整机历史
- 菜单栏能耗区块
- 把能耗或唤醒写进保存的快照
- 新的系统调用、第二轮 `proc_pid_rusage`、v6 失败再读 v4
- 重开「样本不足槽补 PID」的文案，或改进程树

#138 里多出来的「状态」列、按 App、详情、电池，以 #140 和这次产品锁为准，不提前做。

## 今天的采样

`ProcessEnumerator` 的 `RawProcessSample` 已经带同一轮 `rusage_info_v6` 的 `energyNanojoules`（`ri_energy_nj`，纳焦）和 `interruptWakeups`（`ri_interrupt_wkups`）。读失败时两个字段都是 nil，没有驻留内存那样的替代。`ProcessEnergyWiringSourceTests` 锁着 `ri_energy_nj` / `ri_interrupt_wkups`，并且禁止 `ri_billed_energy`。

`MemorySampler` 在每个仍在列表里的 pid 上，用这一帧的 `capturedAt` 组成 `EnergyTick`。两个计数要同时有值才构成 tick。然后 `ProcessEnergyLoad.advance` 只保留上一枚基线（`energyTicks`），把相邻两帧的速率写进 `ProcessRow.energyWatts` 和 `wakeupsPerSecond`。进程从列表消失后，下一帧的 `nextEnergyTicks` 不再收下这个 pid。

`ProcessEnergyLoad.rates` 的规则就是 ADR-0002：

- 没有上一枚、任一计数变小、或墙钟时长 ≤ 0：瓦特和唤醒每秒一起为 nil。
- 时长 > 0 且两个计数都不减小：瓦特 = 纳焦差 / 秒 / 1e9，唤醒每秒 = 次数差 / 秒。
- 差分为 0 是真实 0，不是缺失。`ProcessEnergyText` 把 nil 写成「—」，把 0 写成「0.0 W」和「0.0 次/秒」。
- 读失败时 `advance(reading: nil)` 本帧缺失，基线留着。下一枚成功 tick 若计数不减小，差值含中间这段累计，时长含这段墙钟。

CPU 页表头是 `ProcessEnergyText.impactTitle`（「能耗影响」）和 `wakeTitle`（「唤醒」）。排序在 `ProcessTableSort` 里把 nil 当成 -1，所以升序时缺读数排在真实 0 前面。这个比较只服务 CPU 页，能耗页不能改它。

前台休眠 1.5 秒，后台 3 秒（`SamplingPace`）。60 秒里有多少帧不固定。关窗后仍是同一条采样循环。

## 文案

产品锁里的「能耗影响(W)」和「唤醒每秒」是口径，不是第二套表头。ADR-0002 把用户可见名称定为「能耗影响」和「唤醒」。CPU 页已经这样写，单元格单位分别是「 W」和「 次/秒」。

能耗页继续用这两枚标题和 `ProcessEnergyText.watts` / `wakeups`。不把表头改成「唤醒/秒」或「能耗影响(W)」，也不改 CPU 页的表头、单元格和排序。界面不出现「分数」，不声称等于活动监视器的能耗影响。

页上有一块静态说明，不是开关，也不是时间范围选择器：

- 标题：`最近 1 分钟平均功率`
- 正文：`用这段时间里累计的能耗除以实际时长。不足 1 分钟时用已经采到的时长。读不到显示「—」，不显示 0。这不是活动监视器的能耗影响分数。`

不按行显示各自的秒数，不加「1 小时」控件。采样中的占位不另叠「没有匹配的 App」。

## 页面骨架

`ResourceTab` 的顺序决定标签栏：内存、CPU、能耗、磁盘、网络、本机。能耗插在 CPU 和磁盘之间，`rawValue` 为「能耗」，`symbol` 为 `bolt`。GPU 仍然不进标签栏。`DashboardPage` 增加 `.energy` 且可选。不要靠枚举声明顺序去排标签。

视图菜单的 `⌘1`–`⌘5` 仍是内存 / CPU / 磁盘 / 网络 / 本机。不插入能耗项，不加 `⌘6`。冷启动仍是内存页。主窗仍不记住页面、排序和过滤。

工具栏继续只有现有的名称过滤（「过滤 App」）和「保存当前快照」。不显示「按 App」「仅上涨」「仅窗口 App」。这三个开关的 `showsToggle` / `applies` 保持今天的页集合，不把 `.energy` 加进去。名称过滤与其它进程页共用同一个输入，切页不清空。

不画内存总览，也不画 CPU / 磁盘 / 网络的主机曲线。因此这一页不另放降频句；降频仍在原有各页。不画 `ProcessDetailSidebar`，不显示进程树按钮，不提供结束或强制退出。`allowsProcessQuit` 对 `.energy` 为 false，`⌘⌫` 的「退出选中进程」保持禁用。今天的实现是 `self != .machine`，加了 case 却不改这句就会把结束打开，实现时必须改成显式排除能耗页。

布局是：静态说明，然后三列表。不复用 `ProcessLine` 的现有横排。那一行在 `showsEnergy == true` 时仍会画出 CPU、内存和线程，而且读的是 `row.energyWatts`。`ProcessTablePane` 现在约 526 行，已经超过 500 行的上限；能耗表放进新的视图文件，只在这个文件里加页面分支。

点行可以沿用现有全局 `selectedPid`，用来高亮和复制。本页不因为选中去画详情。切回有侧栏的页时，侧栏仍是这个已经存在的选中，曲线仍按今天的 `setSelectedPid` 重采。这不是本页的详情功能。

右键和 `⌘C` 仍是现有「复制」。有选中行才写剪贴板。一行制表符：名称、PID、能耗影响、唤醒。本页不合并，第二列是 pid，不是成员数。不写 CPU、内存、线程。数值用本页的窗口速率，不用 `energyWatts` / `wakeupsPerSecond`。过滤框有焦点时，`⌘C` 仍交给文字框。

底部权限脚注沿用现有句子：这一帧有 EPERM 时写「另有 N 个系统进程没有读取权限」。这些进程不补进行，也不写成 0。

### 空态

有进程时才谈搜索。两种空态的标题不能相同。

| 状态 | 标题 | 说明 | 按钮 |
| --- | --- | --- | --- |
| 采样中，列表还没有行 | 正在采样… | 无 | 无 |
| 进程列表没读到，且没有行 | 暂时无法列出进程 | `SamplingRetryChrome.processListFailedMessage` | 现有「重试」 |
| 采样失败，且没有行 | 进程列表还没有数据 | `SamplingRetryChrome.overviewFailureMessage` | 现有「重试」 |
| 列表成功，但没有运行中的进程 | 还没有进程数据 | 这一帧没有进程可显示。 | 无 |
| 列表里有进程，名称过滤后一个不剩 | 没有匹配的 App | 换个名称试试，或清空过滤。 | 「清空过滤」只清空名称 |

第三行和第四行都不是「没有匹配的 App」。过滤框里有字，但列表本身是空的，仍走「还没有进程数据」或上面的失败态，不走搜索空态。不使用内存页的「仅上涨」空态。失败文案不写「CPU」。

搜索就是 `ProcessNameFilter`：去掉首尾空白后，按名称做 `localizedCaseInsensitiveContains`。不搜 pid、路径或包标识。空白查询等于不过滤。

## 1 分钟窗口

平均功率不是把各帧瓦特再加起来除以帧数。间隔不匀时两者不相等。锁定的算法是累计计数差除以有效时长，和 `ProcessEnergyLoad.rates` 同一对公式。

能耗页不读取已经发布的两帧 `energyWatts` / `wakeupsPerSecond`。那两个字段继续只给 CPU 页、CPU 详情和按 App 求和。窗口速率是同一枚 `EnergyTick` 的第二个消费者，写到采样帧上按 pid 索引的单独一张表。查不到或结果为缺失时，单元格是 nil，禁止回退到两帧字段。

不把窗口瓦特写进 `ProcessRow`。快照、按 App 和 CPU 复制因此不会在没人改它们的时候带上 1 分钟数字。保存快照继续不包含能耗和唤醒。

每个 pid 只保留当前单调段里、相对最新一枚成功 tick 年龄 ≤ 60 秒的成功 tick。年龄按 `EnergyTick.date` 的墙钟，这个日期就是该帧的 `capturedAt`。60 秒是墙钟，不是 60 帧，也不是 #143 的分钟桶。不在两枚 tick 之间插值，不把分母补成 60。

对当前列表里的每个 pid，用这一帧已经造好的 `EnergyTick?` 推进：

1. 读数缺失（纳焦或唤醒次数任一没有，现有代码要求两者同时存在）：本帧两项都是 nil。不改已保存的 tick。不把这一帧记成 0。
2. 段内已经有 tick，且相对最后一枚，纳焦变小、唤醒次数变小，或时长 ≤ 0：单调段作废，只留下这一枚新 tick，本帧两项都是 nil。这就是基线重建。任一计数回退都会让两项一起缺失，不单独保留另一项的差值。这和 `rates` 的成对规则相同。段内还没有 tick 时不走这一步。
3. 其它成功读数追加进段内。然后丢掉年龄 > 60 秒的 tick。年龄刚好 60 秒的留下。
4. 段内少于两枚：nil。这是无基线，包括进程刚出现、刚重建基线、以及长时间没有成功读数之后只剩一枚新 tick。
5. 否则锚点是留下的最早一枚，当前是最新一枚。调用 `ProcessEnergyLoad.rates(previous:anchor, current:current)`。有效时长就是这两枚的墙钟差，大于 0 且不超过 60 秒。瓦特和唤醒每秒都来自这一对。差分为 0 的那一项是真实 0，另一项可以是正数。

满窗时有效时长通常比 60 秒短不到一个采样间隔：窗口外的那枚 tick 被丢掉，起点之前的那一截计数不进入分子，也不把少掉的时间补回分母。Pulse 启动之前没有采到的时间同样不补。

一次失败读数不把整分钟打成缺失以外的 0。下一枚成功 tick 若仍落在 60 秒内且计数不减小，分子含这段累计，分母含这段墙钟，和今天「失败帧留住基线、下一帧按整段时长求差」一致。失败若超过 60 秒，旧 tick 会在下一次成功时因为年龄 > 60 被丢掉；若只剩新的一枚，结果是 nil，而不是一条跨了好几分钟、却标成 1 分钟的平均。

进程不在这一帧的列表里：删掉它的窗口状态。表上只留运行中的进程，退出后立刻消失，不因为这一分钟里耗过电而留下。pid 再次出现当作新观测，从无基线开始。

身份只有 pid，和今天的 `energyTicks` 一样。计数变小能把复用后的新进程从旧锚点上切开。新进程的计数若没有变小，现有两帧路径也分不出这是不是另一个进程；1 分钟窗口沿用这个限制，不新增启动时间、进程世代或系统调用。不改「样本不足槽」的 PID 句子，不改进程树。

窗口在每一次 `MemorySampler.sample()` 上更新，不论主窗在不在、当前是不是能耗页。仍是前台约 1.5 秒、后台约 3 秒。不另开计时器，不增加 `proc_pid_rusage`。v6 失败不补 v4。内存回退驻留内存的规则不变。

## 排序

进入能耗页时 `ProcessTableSort` 的默认值是能耗列、降序。点列规则沿用现有 `selecting`：名称第一次点为升序，能耗和唤醒第一次点为降序，再点同一列翻转。离开再进入会按今天的 `DashboardNavigation.select` 重置成这个默认值。

比较器只给能耗页用，不改 `ProcessTableSort.compare`：

- 名称按现有字符串比较。缺读数不参与，也不沉底。
- 能耗、唤醒：先比有值的数。真实 0 就是 0。nil 在升序和降序都排在所有非 nil 之后。
- 主键相同，包括同为 nil，按 pid 升序断开，不随升降序翻转。

因此升序是 0、正数、nil；降序是较大的数、0、nil。CPU 页升序仍是 nil、0、正数。两边都要有回归测试，防止改成同一种。

过滤顺序：名称过滤，然后上述排序。没有仅上涨、仅窗口 App、按 App。

## 测试与接线

可移植逻辑用 XCTest，文件放在 `Tests/SamplingCoreTests/`。这个目录由 SPM 整目录收录，不进 App target，不为测试文件增加 `PBXBuildFile`。

窗口：

- 只有一枚 tick：两项 nil，且不是 0
- 两枚 tick、时长小于 60 秒：瓦特 = 纳焦差 / 时长 / 1e9，唤醒每秒 = 次数差 / 时长
- 时长刚好 60 秒的锚点留下；超过 60 秒的丢掉。不插值，不把分母改成 60
- 差分为 0：该项是 0，结果不是缺失
- 纳焦变小，或只有唤醒次数变小：两项一起 nil，段被新 tick 替换；再来一枚不减小的 tick 才按短窗出数
- 失败读数：本帧 nil，段还在；下一枚成功读数在 60 秒内且不回退时，差值含这段间隔
- 失败超过 60 秒后只剩一枚新 tick：nil
- 时长 ≤ 0：nil，段换成这一枚
- pid 从列表消失后状态删除；再出现是无基线
- 计数没有变小的 pid 连续出现不会被另一次身份检查切开

排序和空态：

- nil 在升降序都在最后；真实 0 留在有值的一侧
- 同值按 pid 升序
- 默认排序是能耗降序；名称排序不把 nil 沉底
- 现有 `ProcessEnergySortTests` 仍要求 CPU 页升序时 nil 在真实 0 之前
- 名称匹配的行即使两项都是 nil 也留下；搜索空态和「还没有进程数据」的标题不同
- `.energy` 可选、不允许结束；按 App、仅上涨、仅窗口 App 的开关在这一页都不显示
- CPU 页列标题仍是「名称、CPU、内存、能耗影响、唤醒、线程」

接线约束，用现有的源码阅读测试方式锁住，不代替 Mac：

- `Package.swift` 的 `sources` 加入 `Sampling/ProcessEnergyWindow.swift` 和 `Models/EnergyPage.swift`
- 视图文件只登记 `project.pbxproj`（`PBXBuildFile`、`PBXFileReference`、分组、`PBXSourcesBuildPhase`）。`Views` 已被包排除
- `MemorySampler` 仍调用 `ProcessEnergyLoad.advance`，仍把两帧速率写进 `energyWatts` / `wakeupsPerSecond`，并且仍从 `ri_energy_nj` 取值
- 采样器里不出现第二次 `proc_pid_rusage`，也不出现 `ri_billed_energy` 或 `IOPSGetTimeRemainingEstimate`
- CPU 页单元格仍是 `ProcessEnergyText.watts(row.energyWatts)`
- `MemoryGrowthListHelpWiringSourceTests` 今天把 `PBXBuildFile` 计为 92。实现若新增 App 源文件，这个计数要改成新的数量，并写明加了哪些文件

单文件不超过 500 行。

## 实现时要动的表面

可移植新文件：`Pulse/Sampling/ProcessEnergyWindow.swift`、`Pulse/Models/EnergyPage.swift`。两者都进 `Package.swift` 和 `project.pbxproj`。

只进工程的新视图：`Pulse/Views/EnergyProcessTable.swift`。

要改、但不改口径的现有文件：`MemorySampler.swift`（已在包排除列表里）、`SampledFrame`、`DashboardPage`、`ResourceTab`、`MemoryDashboardView`、`DashboardNavigation` 的默认排序、`ProcessRowCopy`、`PulseApp` 的剪贴板分支。`ProcessTableSort` 的能耗比较和 CPU 页列定义不动。

`DashboardPage.allCases` 会多一个 case。现有「非内存页」循环会看到能耗页。那些断言应继续成立：这一页不是内存可见组，不合并，不显示上涨徽标，不允许结束。不要为了编译通过把它放进内存分支。

## 冒烟

实现 PR 才能勾。文档 PR 全部未跑。至少覆盖：

- 标签在 CPU 之后，标题「能耗」，符号 `bolt`；说明文字含最近 1 分钟、短窗和「不是活动监视器的分数」
- 三列、默认能耗降序；无基线是「—」；闲置进程的真实 0 是「0.0 W」而不是「—」
- 名称、能耗、唤醒可排序；缺读数升降序都在最后
- 「没有匹配的 App」和「还没有进程数据」都能看到，而且不是同一句话
- 没有按 App、侧栏、结束、电池卡、小时切换和历史曲线
- CPU 页两列、本机页电池、菜单栏、快照内容与改前一致
- `⌘1`–`⌘5` 的目标没有被能耗页挤开

静态测试和模型推理不能代替上面这些。实现 PR 要写明哪些跑了、哪些跳过，并附真实截图。
