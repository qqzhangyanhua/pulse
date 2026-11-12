> 已落地。当前行为以 [TECH.md](../TECH.md) 的「能耗页」为准。本稿停改。#141 已随 #149 合入。下面正文是落地前对照 `5a9e668` 写下的约定；其中「不做 #142–#145」已被后来的实现覆盖，不以本稿为准。

# 能耗页按 App、详情与单进程结束（未实现）

> 落地前的技术约定，对应用户 issue [#141](https://github.com/qqzhangyanhua/pulse/issues/141)。它不是实现授权。对照提交 `5a9e6684799aa29bdcca16ab1a8798dabca2854e`（#147 合入 `main`，父提交 `ea972bec`）。这份文档 PR 没有 Swift 改动，没有跑行为红绿，也没有在 Mac 上打开过这个页面。
>
> 口径仍是 [ADR-0002](../adr/0002-process-energy-wakeups.md)。不改 ADR。#140 已落地的一分钟窗口以 [TECH.md](../TECH.md)「能耗页」为准；[35-energy-page.md](35-energy-page.md) 停改。本稿落地后同样以 TECH.md 为准并停改。
>
> 不做 #142 电池、#143 分钟桶与 1 小时、#144 已退出进程、#145 整机历史，也不做 #74 降频。不新增能耗曲线，不整组结束。

## 已锁行为

三列表和「最近 1 分钟平均功率」说明保留。只加三件事：能耗页显示现有「按 App」开关；点行打开现有详情侧栏；结束走现有退出流程。

分组键、代表进程和选中迁移沿 CPU，不新造 App 身份：

- `AppGroupProjection.apply` 按显示名分桶，不读 bundle id（`AppGroupProjection.swift` 24–36 行）。
- 代表是该组内存字节最大的 pid；内存相同取较小 pid（47–54 行）。打开合并时 `selectedPid` 迁到这个代表（`MemoryDashboardVM+QuitSession.swift` 138–144 行）。
- 行 id 仍是这个 pid。没有单独的组 id。

表上的能耗和唤醒是本页 `energyWindowRates` 的成员求和，调用现有 `ProcessEnergyGroup.sum`。有值成员相加，真实 0 参加加法。部分成员缺失时保留和，并标现有「部分读数」（`ProcessEnergyText.partial` / `caption`）。全部缺失是 nil，界面「—」，不补 0。两项分开求和，一项为 0、另一项缺失时互不影响。这个和不写进 `ProcessRow.energyWatts` 或 `wakeupsPerSecond`。CPU 的 `combine` 继续只读那两个两帧字段（56–73 行），CPU 比较器仍把 nil 当成 -1。

排序仍用能耗页自己的比较器。组行的排序键是上面的窗口和，挂在代表 pid 上。nil 双向仍在最后，真实 0 仍在有值一侧。未合并时排序键仍是该 pid 自己的窗口值。

详情里的能耗影响和唤醒必须是同一套窗口值：未合并用该 pid 的 `energyWindowRates`，合并用该组的窗口和。禁止回落到 `row.energyWatts` / `row.wakeupsPerSecond`。今天 `.energy` 走 `ResourceDetailPageProjection` 的 `.noResourceUpgrade`（153–167 行），不画这两项；`.cpu` 才读两帧字段（114–117 行）。不能为了少写分支把能耗页放进 `.cpu`。

组汇总和实际操作进程必须能分开，结束只打一个明确的 pid：

- 合并时，窗口能耗和窗口唤醒旁边写「当前可见的 N 个同名进程合计」。N 是 `groupedMemberCount`，含 1。这句只归属这两项窗口值。未合并不写这句。头部 PID 那一行不能拿来冒充这句。
- 侧栏头的 `kindLine` 仍是「进程/App · PID …」，pid 来自采样器里的选中行（`ProcessDetailSidebar.swift` 336–347、373–375 行），不是成员列表。
- 退出调用 `quitSelected` / `forceQuitSelected`。两者都要求 `allowsProcessQuit`，并把未合并的 `rows` 交给 `ProcessQuitSession`（`MemoryDashboardVM+QuitSession.swift` 19–31、43–54 行）。`ordinaryTerminate` 和 `requestForce` 只在 `actionPid == listSelectedPid` 时发出这一个 pid（`ProcessQuitSession.swift` 215–231、237–260 行）。
- 强制退出的系统确认沿 `ProcessActions.confirmForceQuit`，名字取未合并行上的这一个 pid。普通退出不另加确认框。取消确认不发信号。不循环组成员，不新增整组结束。
- 关闭侧栏沿 `dismissSidebar`。

曲线保留头部 PID 已有的内存曲线和 CPU 曲线，序列是该 pid 的 `memorySeries` / `cpuSeries`。摘要里的 PID 是这一个，正文不写「合计」，不把其它成员的点加进去。不新增能耗曲线，也不新增能耗序列。`.noResourceUpgrade` 今天有一条内存曲线（296–300 行），`.cpu` 另有 CPU 曲线（256–260 行）；能耗页要留下这两条已有曲线，但不能借 `.cpu` 投影去读两帧能耗。

复制：

- 未合并：名称、PID、该 pid 的窗口能耗、该 pid 的窗口唤醒。不写「部分读数」，第二列不是成员数。
- 合并：名称、成员数 N（含 1）、窗口能耗合计、窗口唤醒合计。某一项 `isPartial` 为真时，该字段是现有数值文本、一个空格、然后「部分读数」。全缺失仍是「—」，因为这时 `isPartial` 为假。第二列是 N，不是代表 pid。
- 过滤框有焦点时，`⌘C` 仍交给文字框。

进程树：未合并时显示现有按钮，树仍用未合并的 `vm.rows`，展开、占位、返回和 `selectPidIfPresent` 都不改。合并时隐藏按钮，并关掉已经打开的树。不增加组节点，不改树的数据。这就是 `showsProcessTreeButton` 在 `applies` 含 `.energy` 之后的结果（`AppGroupChrome.swift` 17–18 行）。

`allowsProcessQuit` 今天排除 `.energy`（`MenuBarStatus.swift` 25 行）。落地时能耗页改为允许结束，CPU、内存、磁盘、网络、本机的允许关系不变。`⌘1`–`⌘5` 不插入能耗项。过滤框有焦点时，`⌘⌫` 仍不注册，和 CPU 一样。

不增加 `proc_pid_rusage`。窗口仍在每次现有采样上更新。快照、菜单栏、本机电池不写能耗窗口。

## 文件长度

规则是单文件不超过 500 行，没有超限豁免。`5a9e668` 上 `ProcessTablePane.swift` 533 行，超出来自 #140 要求的页面分支，#141 不要再往里加逻辑。`ProcessDetailSidebar.swift` 496 行。能耗详情若会把它推过 500，放进新的视图文件，并同时登记 `project.pbxproj`。可移植求和与详情投影放进新的 `Pulse/Models` 文件，同时登记 `Package.swift` 和工程。不要改 `AppGroupProjection.combine` 去读窗口表。

## 回归计划

先写能编译的可移植用例，让断言在值上失败，再改生产类型。缺类型或改 CPU 期望不算红。

夹具：同名三行，窗口值与两帧诱饵分开。pid 4 内存 100、窗口能耗 1.5、窗口唤醒 nil，两帧能耗写成 9。pid 9 内存 50、窗口能耗 nil、窗口唤醒 4，两帧唤醒写成 9。pid 2 内存 100、窗口能耗 0、窗口唤醒 0，两帧都写成 9。代表是 pid 2。窗口能耗和是 1.5 且部分缺失，窗口唤醒和是 4 且部分缺失。

- 这个和等于有值成员之和，`isPartial` 为真。全部 nil 时和为 nil，且不是 0。诱饵两帧值不进入和。一项为真实 0、其它成员都有值时，`isPartial` 为假。
- 代表 pid 与 `combine` 的内存规则相同。组行排序键是窗口和。能耗页升序仍是 0、正数、nil。现有 CPU 升序测试仍是 nil、0、正数。
- 合并详情的能耗/唤醒等于上面的窗口和，并带「当前可见的 3 个同名进程合计」。N 为 1 时句子里的数字是 1。未合并不带这句。头部文案仍含 `PID 2`。`.cpu` 投影仍返回 `detail.row.energyWatts`。
- 曲线投影只含 pid 2 的 `memorySeries` 和 `cpuSeries`。摘要 PID 是 2。文本不含「合计」。没有能耗序列。
- 未合并复制是 `名称\t2\t0.0 W\t0.0 次/秒`，不含「部分读数」。上面这组合并复制是 `名称\t3\t1.5 W 部分读数\t4.0 次/秒 部分读数`。全缺失的合并复制两项都是「—」，没有「部分读数」，第二列仍是 N。
- 未合并 `rows` 里有这三个 pid，`listSelectedPid` 是 2：`ordinaryTerminate` / `requestForce` 只给出 2。强制确认用的显示名是 pid 2 的名字。合并时进程树按钮为隐藏；未合并时为显示。已打开的树在合并开关打开后关闭。

源码阅读只锁接线，不代替 Mac：

- `AppGroupChrome.applies` 包含 `.energy`，`combine` 仍映射 `\.energyWatts` 与 `\.wakeupsPerSecond`。
- 采样器仍把两帧速率写入 `energyWatts`，窗口仍来自一次 `energyWindow.advance`，没有第二次 `proc_pid_rusage`，也没有 `IOPSGetTimeRemainingEstimate`。
- `quitSelected` 仍把未合并的 `rows` 交给 `ordinaryTerminate`。
- CPU 详情单元格仍是 `ProcessEnergyText.watts(cpu.energyWatts)`。能耗详情的新增源码不读 `row.energyWatts`。
- 能耗页合并文案含「当前可见的 N 个同名进程合计」。曲线标题或摘要不含「合计」。复制的合并分支写成员数和「部分读数」，未合并分支仍写 pid。进程树按钮仍走 `showsProcessTreeButton`，不出现新的树节点类型。

本机冒烟另列，文档 PR 不能勾。实现 PR 写明跑了什么、跳过什么，并附真实截图。`swift test` 不能代替侧栏、确认框和 VoiceOver。
