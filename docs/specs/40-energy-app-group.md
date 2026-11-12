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

- 侧栏头今天的 `kindLine` 是「进程/App · PID …」，pid 来自采样器里的选中行（`ProcessDetailSidebar.swift` 336–347、373–375 行），不是成员列表。
- 退出调用 `quitSelected` / `forceQuitSelected`。两者都要求 `allowsProcessQuit`，并把未合并的 `rows` 交给 `ProcessQuitSession`（`MemoryDashboardVM+QuitSession.swift` 19–31、43–54 行）。`ordinaryTerminate` 和 `requestForce` 只在 `actionPid == listSelectedPid` 时发出这一个 pid（`ProcessQuitSession.swift` 215–231、237–260 行）。
- 强制退出的系统确认沿 `ProcessActions.confirmForceQuit`，名字取未合并行上的这一个 pid。普通退出不另加确认框。取消确认不发信号。不循环组成员，不新增整组结束。
- 关闭侧栏沿 `dismissSidebar`。

`allowsProcessQuit` 今天排除 `.energy`（`MenuBarStatus.swift` 25 行）。落地时能耗页改为允许结束，CPU、内存、磁盘、网络、本机的允许关系不变。`⌘1`–`⌘5` 不插入能耗项。过滤框有焦点时，`⌘⌫` 仍不注册，和 CPU 一样。

不增加 `proc_pid_rusage`。窗口仍在每次现有采样上更新。快照、菜单栏、本机电池不写能耗窗口。

## 待确认

下面这些源码事实还没有产品句子。本稿不补文案，也不把它们写成已经决定。

- 现有 CPU 能耗详情没有内存页那种「当前可见的 N 个同名进程合计」。头只有一个 PID，数字来自合并行。已锁的是「组汇总和操作进程必须可区分」以及「结束只打这一个 PID」。是否再加一句归属，没有给定句子。
- 「不加图表」排除的是新的能耗曲线。`.noResourceUpgrade` 和 `.cpu` 都会画已有的内存曲线或 CPU 曲线（296–300、256–260 行）。能耗详情要出现窗口能耗，但不能据此删掉或留下这两条已有曲线；两种做法都还没被单独锁。
- 能耗页复制今天是名称、PID、窗口能耗、窗口唤醒，第二列是 pid（`ProcessRowCopy.swift` 的 `.energy`）。内存页按 App 的第二列是成员数。CPU 复制会把 `groupedMemberCount` 写进第二列，能耗数字仍是两帧。#141 没有锁分组后的复制。
- `AppGroupChrome.showsProcessTreeButton` 在 `applies` 为真且未合并时显示进程树按钮，合并时关掉树（17–18 行）。能耗页要合并，就必须让 `applies` 包含 `.energy`，于是未合并时现有侧栏会带上这个按钮。#141 没有单独锁进程树。这是复用该函数的结果，不是新做一棵树。

## 文件长度

规则是单文件不超过 500 行，没有超限豁免。`5a9e668` 上 `ProcessTablePane.swift` 533 行，超出来自 #140 要求的页面分支，#141 不要再往里加逻辑。`ProcessDetailSidebar.swift` 496 行。能耗详情若会把它推过 500，放进新的视图文件，并同时登记 `project.pbxproj`。可移植求和与详情投影放进新的 `Pulse/Models` 文件，同时登记 `Package.swift` 和工程。不要改 `AppGroupProjection.combine` 去读窗口表。

## 回归计划

先写能编译的可移植用例，让断言在值上失败，再改生产类型。缺类型或改 CPU 期望不算红。

- 成员窗口里夹一个真实 0、一个正数、一个 nil：对应项的和等于有值成员之和，`isPartial` 为真；另一项可以独立。全部 nil 时和为 nil，且不是 0。行上的 `energyWatts` / `wakeupsPerSecond` 设成不同的诱饵，结果仍是窗口和。
- 代表 pid 与 `combine` 的内存规则相同。组行排序键是窗口和。能耗页升序仍是 0、正数、nil。现有 CPU 升序测试仍是 nil、0、正数。
- 能耗详情投影在诱饵两帧值不同时返回窗口值。`.cpu` 投影仍返回 `detail.row.energyWatts`。
- 未合并 `rows` 里有三个同名 pid，`listSelectedPid` 是代表：`ordinaryTerminate` / `requestForce` 只给出这一个 pid。强制确认用的显示名是这一行的名字。

源码阅读只锁接线，不代替 Mac：

- `AppGroupChrome.applies` 包含 `.energy`，`combine` 仍映射 `\.energyWatts` 与 `\.wakeupsPerSecond`。
- 采样器仍把两帧速率写入 `energyWatts`，窗口仍来自一次 `energyWindow.advance`，没有第二次 `proc_pid_rusage`，也没有 `IOPSGetTimeRemainingEstimate`。
- `quitSelected` 仍把未合并的 `rows` 交给 `ordinaryTerminate`。
- CPU 详情单元格仍是 `ProcessEnergyText.watts(cpu.energyWatts)`。能耗详情的新增源码不读 `row.energyWatts`。

本机冒烟另列，文档 PR 不能勾。实现 PR 写明跑了什么、跳过什么，并附真实截图。`swift test` 不能代替侧栏、确认框和 VoiceOver。
