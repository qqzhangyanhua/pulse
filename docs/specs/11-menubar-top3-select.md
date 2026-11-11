# Pulse 十一期技术设计（首包：菜单栏轻量条 B — Top3 点选→打开主窗并选中该进程）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 11 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。
>
> 已被取代：Top3 顺序十四期起跟随最后一次内存页排序，不再固定内存降序。
>
> 已被取代：切到内存页时会按「仅上涨」「仅窗口 App」重算选中，点 Top3 选中的进程可能被当前开关取消选中。
>
> 已被取代：上文这个「可能被开关取消选中」，以及正文里「名称过滤不在范围内、不要为点选改过滤」「可以给 `focusMemoryPage()` 加可选 pid」，都不再作为下一步实现。已锁定只在 Top3 进程行、且 PID 仍在完整 `rows` 里时，于现成选中和共享切页之前调整挡住该 PID 的过滤。共享 `focusMemoryPage` 与 `MemoryGrowthRisingFilter.selectedPid` 本体不改。行为已按 [TECH.md](../TECH.md) 落地。冒烟清单仍未勾选。Mac 激活、滚动、焦点和 VoiceOver 未验。下面的正文是当时的约定，不再改。

> 一期至十期正文不改写。七期锁了弹出条 B（压力一行 + Top3 +「打开 Pulse」），十期只在压力行下补了主机已用内存一行、并写死 Top3 **仍不可点**——**本文只覆盖那条交互延期**：把已有 Top3 行做成可点，一点开现有主窗并按 pid 选中该进程，侧栏现成「退出 / 强制退出」即可用。不新开采样器、不第二套 VM、不第二扇窗。GPU Tab、进程级 GPU、无界全表 ring、新 Sampler 周期、恐吓文案 / 「泄漏」、从弹出条 terminate / force-quit、改栏上 A 色点外观、新 Tab、Helper / XPC、新 entitlements、Electron、自动杀、恐吓红仍不做。

**已锁定**：十一期 = **A（菜单栏 Top3 点选开主窗选中进程）**。谁：先扫菜单栏的人。情境：Top3 已经露出要处理的嫌疑进程。成功：点一行 → 现有主窗落到内存页且该进程已选中，侧栏现成 Quit / Force Quit 可直接用。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`；同一套七期 `NSStatusItem` / `NSPopover` 壳。十期已用内存行**保留、仍不可点**；压力行仍不可点；栏上 A 色点外观不改。弹出条数据仍是当前快照的只读投影。**只翻 Top3 的交互**（七 / 十期「不可点」由本文覆盖）。「打开 Pulse」保留：只打开 / 聚焦，**不改选中**（现成 `focusMemoryPage()` 行为）。采样周期不变（前台约 1.5s，主窗后台或已关、菜单栏保活时约 2–3s）；**零新 Sampler period / cadence**，弹出条刷新不得快过 Sampler。不新开 entitlements、不拆 Helper / XPC。文案冷静；永不写「危急 / 泄漏 / 危险」。不从弹出条结束他人进程。

来源：用户 + 产品锁定的十一期 Must（十期已用内存已合 #32–#34；七期 B 已合 #25–#27）；对照现实现（`MenuBarController` 同进程 `NSStatusItem` + `NSPopover`；`MenuBarPopoverView` 三槽：`hostPressure`（压力 + 已用内存同一块）/ `topProcesses` / `openPulse`；`MenuBarPopoverSnapshot` 已投影 `pressure` + `usedBytes` + `processes`，`MenuBarPopoverProcess` **已带 `pid`**；`topProcessesSlot` 今天只画名称 + 内存、无 Button / tap；`PulseAppDelegate.focusMemoryPage()` 打开 / 聚焦主窗并落内存页，**不改** `selectedPid`；`MemoryDashboardVM.selectedPid` 就是进程表选中（`ProcessTablePane` `List(..., selection: $vm.selectedPid)`），侧栏 `quitSelected()` / `forceQuitSelected()` 读这个；`MenuBarController.openPulse()` 已先 `dismissPopover()` 再 `onOpenPulse()`；`install` 今天只有 `onOpenPulse` / `onQuit`）。

## 范围（相对一二三四五六七八九十期）

| 项 | 一二三四五六七八九十期 | 十一期首包 |
| --- | --- | --- |
| 定位 | 七期：B = 压力 + Top3 +「打开 Pulse」，Top3 只读；十期补已用内存一行，仍写死 Top3 不可点 | **交互（A）**：同一条 B，只把 Top3 行做成可点 → 开主窗并按 pid 选中 |
| 菜单栏外观 A | 栏上仅压力色点；不写压力字、不写已用内存 | **A 外观不变**。不改色点、不在栏上写字 |
| 弹出条 B | 十期四行：压力 → 已用内存 → Top3 →「打开 Pulse」 | **槽位 / 文案不改**。只改 Top3 行可点 |
| 主机已用内存 | 十期压力行下、次要色、「已用 xx GB」/「暂时读不到」 | **保留、仍不可点**。本刀不碰这行 |
| Top3 | 已采 `rows` 内存降序前 3；名称 + 内存；七 / 十期不可点 | **做（本刀）**：行可点；点 → 收起 popover + 打开 / 聚焦主窗内存页 + 按 pid 选中（若仍在） |
| 「打开 Pulse」 | 现成 `PulseAppDelegate.focusMemoryPage()`；不改选中 | **不改**。继续只打开 / 聚焦，不写 `selectedPid` |
| 选中 / 退出 | 主窗列表写 `selectedPid`；侧栏 `quitSelected` / `forceQuitSelected` | **复用这条**。弹出条不 terminate / forceTerminate |
| 采样 | 单 `MemorySampler`；前台 ~1.5s，后台 ~2–3s。十期零 Sampler | **零 Sampler 改动、零新 period / cadence**。弹出条只读当前快照 |
| GPU Tab / 进程级 GPU | 灰置 / 不做 | **仍灰置、仍不做** |
| 无界全表 ring | 九期只允许 Top N=5 有界 series | **仍不做**。本刀不碰 series / ring |
| 新 Tab | 无 | **仍无** |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 / 恐吓文案 | 不做 / 禁止 | **仍禁止**。永不写「泄漏」 |

一二三四五六七八九十期验收与公证路径不因本文重开。十期已用内存行、七期压力 / 「打开 Pulse」语义不重开；仅 Top3 可点性由本文覆盖。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

优先**延长**七 / 十期同进程弹出条路径和现成打开 / 选中 API，不要另起 Helper / XPC，也不要退回 `MenuBarExtra`，也不要新开第二套 popover / 第二套 activate。

- `MenuBarController`（同进程 `NSStatusItem` + `NSPopover`）←观察→ 同一 `MemoryDashboardVM`（现已 `observe(objectWillChange)` 重绘色点与 B）
- 弹出条仍挂在同一状态项按钮上，**不是**第二个 `WindowGroup`
- 「打开 Pulse」仍走现成 `PulseAppDelegate.focusMemoryPage()`（`dashboard.focusMemoryPage()` + `NSApp.activate` + 找到 `PulseWindowID.main` 或 `openWindow`）——**不改选中**
- Top3 点选：先走现成 `MenuBarController.dismissPopover()`（与 `openPulse()` 同一收起），再按 pid 写现成 `MemoryDashboardVM.selectedPid`（仅当该 pid 仍在 `rows`），再走**同一条** `focusMemoryPage()`
- VM ←订阅快照→ `MemorySampler`（同一 Actor）；弹出条**不**调 `sample()`
- 右键「退出 Pulse」与弹出条内容正交，本刀不改

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询。
- 弹出条数据仍是当前快照的只读投影；本刀只给 Top3 行加点击，不给投影再采一趟。
- 不改 `Pulse.entitlements`、不改公证脚本、不改栏上色点映射（`MenuBarDot.resolve` 仍只服务 A）。
- 自身占用仍优先：点选不另开 timer、不另开 Mach。
- 关主窗仍留菜单栏；弹出条随状态项走，不单独保活。
- 点选必须落**内存页**。禁止跳到 CPU / 网络 / 磁盘 / GPU。现成 `focusMemoryPage()` 已经把 `DashboardNavigation` / `MenuBarNavigation` 打到 `.memory`。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `Pulse/MenuBar/*`、`MemoryDashboardVM`、`ProcessTablePane`、`ProcessDetailSidebar`、七 / 十期 TECH。本刀必须按「已有 / 没有」落笔，**禁止**为点选再采一趟，也**禁止**发明第二套打开 / 选中 API。

| 现字段 / 调用 | 文件 | 十一期怎么用 |
| --- | --- | --- |
| `NSStatusItem` + `NSPopover` + `MenuBarPopoverView` | `MenuBar/MenuBarController.swift`、`MenuBarPopoverView.swift` | **延长这条壳**。不换宿主、不加第二扇窗 |
| `MenuBarController.openPulse()` / `dismissPopover()` | `MenuBarController.swift` | 点选先走同一套收起。不要另写第二套 close |
| `MenuBarController.install(currentDot:onOpenPulse:onQuit:)` | 同上 | 今天没有按 pid 回调。接线时可给 popover 加一条「点选 pid」闭包，**内部仍 dismiss + 选中 + 现成 `focusMemoryPage()`** |
| `PulseAppDelegate.focusMemoryPage()` | `MenuBar/PulseAppDelegate.swift` | 「打开 Pulse」与点选共用的**唯一**打开 / 聚焦路径。今日实现不改 `selectedPid`——「打开 Pulse」保持这个语义 |
| `MemoryDashboardVM.focusMemoryPage()` | `ViewModels/MemoryDashboardVM.swift` | 只把 `DashboardNavigation` 打到内存页（`MenuBarNavigation.focusMemoryPage()`）。**不改选中** |
| `MemoryDashboardVM.selectedPid` | 同上 | **进程表已经在用的选中**。`ProcessTablePane`：`List(sortedRows, selection: $vm.selectedPid)`。侧栏退出读这个。点选只写这个属性（pid 仍在 `rows` 时） |
| `MemoryDashboardVM.rows` / `.selectedRow` / `.quitSelected()` / `.forceQuitSelected()` | 同上 + `Views/ProcessDetailSidebar.swift` | 点选后侧栏现成「退出 / 强制退出」即可用。弹出条**不**调 `ProcessActions` |
| `MenuBarPopoverSnapshot` / `MenuBarPopoverProcess.pid` | `MenuBar/MenuBarStatus.swift` | 投影已带 pid。点选身份就是这个 pid。不给 `ProcessRow` 加菜单栏字段 |
| `MenuBarPopoverView.topProcessesSlot` | `MenuBarPopoverView.swift` | 今天是只读 `HStack`。**本刀只给有 `processes` 的行加 tap**；空态「暂无进程」仍不可点、不造假行 |
| `usedMemoryLine` / 压力行 | 同上 + `MenuBarPopoverSnapshot` | **仍不可点**。十期信息补全不重开 |
| `MenuBarCopy.openPulseTitle` | `MenuBarStatus.swift` | 「打开 Pulse」文案与按钮不改 |
| Sampler `sample()` / `SamplingPace` | `Sampling/MemorySampler.swift`、`SamplingPace.swift` | **不改**。无新字段、不改 tick、不第二路 Mach |

**缺口**：Top3 行没有 tap；`install` 没有按 pid 的打开回调。这**不是**采样缺口，也**不是**选中模型缺口——`MenuBarPopoverProcess.pid` 与 `selectedPid` 已够用，`focusMemoryPage()` 已能开窗落内存页。不要把「行不可点」读成「要新开 period / 新开 `selectProcess` 类型」。

因此本刀：

1. **零 Sampler 改动**（无新字段、不改 tick、不第二路 Mach、**零新 period / cadence**）。
2. **不发明第二套打开 / 选中 API**。优先延长现成路径：收起 popover →（pid 仍在 `rows` 时）写 `MemoryDashboardVM.selectedPid` → 同一条 `PulseAppDelegate.focusMemoryPage()`。若要把「打开」和「打开并选中」收成一个入口，只允许给现成 `focusMemoryPage()` 加**可选 pid**（缺省 = 今日行为，不改选中）。禁止另写第二套 `NSApp.activate` / 第二扇窗 / 新 `selectAndOpenProcess` 类型。
3. 「打开 Pulse」继续只调无 pid 的 `focusMemoryPage()`，不碰 `selectedPid`。
4. 点选时 **select-if-present**：对照点击当下的 `dashboard.rows`（不要信弹出条画出来的旧行）。pid 仍在 → 写 `selectedPid` 再聚焦；pid 已从列表消失 → **仍打开 / 聚焦主窗内存页**，不把消失 pid 写进选中，不造假行。现成 `tick()` 本来就会在 pid 离开 `rows` 时把 `selectedPid` 清掉。
5. `processListFailed` / Top3 为空：投影已是空数组 +「暂无进程」。**没有可点行**，不要造占位行。
6. 不要新建第二个 `MemoryDashboardVM` 给弹出条用。不要给 `ProcessRow` 加「菜单栏可点」字段。
7. 压力行、已用内存行、栏上色点：**不可点、不改外观**。

名称过滤（`MemoryDashboardVM.filter` / `visibleRows`）不是本刀范围。选中对照完整 `rows`，侧栏 `selectedRow` 也读 `rows`，Quit 不依赖过滤表。不要发明「点选必须清过滤」；也不要把 `visibleRows` 或当前表头排序误当成 Top3。

### 建议工程顺序

信号和选中模型已经在？**pid 有，打开路径有，行没有 tap。** 不需要先开采样 PR。

合并后工程顺序（本文只锁设计；**本 docs PR 不写 Swift**）：

1. **选中 / 聚焦 API + 单测（缺什么补什么，不另起类型）**：钉 `focusMemoryPage()` 仍不改选中；「pid ∈ `rows` → 写 `selectedPid`；pid 已消失 → 不写该 pid、仍可走聚焦」。能直接写 `selectedPid` + 现成 `focusMemoryPage()` 就不要新开方法。零 Sampler 改动。
2. **Top3 行 tap 接线 + 收起 popover**：有进程的行可点；点 → `dismissPopover()` + 上一步的选中 / 聚焦。空态 / `processListFailed` 无行可点。压力行、已用内存行、「打开 Pulse」交互不回退。
3. **没有硬伤就不开 polish PR**。有硬伤：一个行为一个最小 fix，不要和 GPU / Helper / 新周期 / 弹出条杀进程捆在一起。

能保持零 Sampler 改动时不要先开采样 PR。不要把本刀和 GPU / 自动杀 / Helper 捆在一起。合并不擅自写代码。

## UI 绑定

结论：栏上 A 不变；B 只在状态项激活时出现。十期四行顺序不改。本刀只让 Top3 **有进程的行**可点。密度：单列、次要文字色、无红色闪烁。

### 状态项 A（不改外观）

| 快照 | 栏上 | 说明 |
| --- | --- | --- |
| `pressure == .normal` | 冷静绿点 | 与二 / 七 / 十期相同；**仍不**在栏上写「正常」或已用内存 |
| `pressure == .elevated` | 冷静琥珀点 | **不**升恐吓红，栏上不写「偏高」、不写「已用」 |
| 无快照 / `samplingFailed` | 灰点 + tooltip「暂时读不到」 | 不装 0、不假装正常 |

- 主点（激活）：出示弹出条 B。
- 右键 / Control-点：现成「退出 Pulse」菜单。
- 栏上仍 `imageOnly`、`statusItemTitle == ""`。

### 弹出条 B 槽位（十期顺序不改，自上而下）

单列。已用内存行仍是压力行的次要下一行，同一信息块、**不可点**。Top3、「打开 Pulse」仍用现成分隔。

| 顺序 | 槽位 | 绑定 | 缺数 / 交互 |
| --- | --- | --- | --- |
| 1 | 主机压力一行 | `snapshot.pressure` → 现成两档语义（七期原句） | 无快照或采样失败：「暂时读不到」。**不可点** |
| 2 | 主机已用内存一行 | `snapshot.usedBytes` → 「已用 xx GB」；次要文字色 | 无快照或采样失败：「暂时读不到」。**仍不可点**（十期原样） |
| 3 | Top 3 内存进程 | 已采 `rows` 按 `memoryBytes` 降序取 `prefix(3)`；每行名称 + 内存；身份 = `MenuBarPopoverProcess.pid` | 1–2 条就画 1–2 条；0 条或 `processListFailed`：「暂无进程」，不造假行、**无行可点**。**有行则可点**：收起 popover → 打开 / 聚焦主窗内存页 → pid 仍在则选中 |
| 4 | 底栏动作 | 「打开 Pulse」 | 始终可点；走现成 `focusMemoryPage()`，**不改选中** |

点选成功路径（写死）：

1. 收起 / dismiss 现有 `NSPopover`（复用 `MenuBarController.dismissPopover()`）。
2. 打开或聚焦**现有**主窗，并落到内存页（同一条 `PulseAppDelegate.focusMemoryPage()`）。
3. 若该 pid 仍出现在当前 `MemoryDashboardVM.rows`：`selectedPid = pid`，使 `ProcessTablePane` 选中该行、侧栏 `quitSelected` / `forceQuitSelected` 就绪。
4. 若绘制到点击之间 pid 已消失：仍执行 1–2，不写该 pid，不造行，侧栏保持现成空态（「选择一个进程查看详情」）。

禁止：从弹出条 `terminate` / `forceTerminate`；跳到非内存 Tab；点已用内存行或压力行开窗。

### 文案默认（可改词不改义）

| 表面 | 锁定默认 | 说明 |
| --- | --- | --- |
| 压力 · 正常 | **正常 · 余量充足** | 七期原句；本刀不改 |
| 压力 · 偏高 | **偏高 · 余量紧张** | 七期原句；本刀不改 |
| 压力空态 | **暂时读不到** | 七期原句 |
| 已用内存 · 有数 | **已用 xx GB** | 十期原句；本刀不改 |
| 已用内存 · 空态 | **暂时读不到** | 十期原句 |
| Top3 内存 | `ByteFormat.memory` | 与主窗列表同一格式器 |
| Top3 空态 | **暂无进程** | 七期原句；不是可点假行 |
| 打开动作 | **打开 Pulse** | 七期原句；不写「立即处理」「结束进程」 |

禁止出现：泄漏、泄露、leak、危险、危急、告警、需要完全磁盘访问。验收对锁定字符串与实现字符串搜这些词。Top3 行不要改成「结束」「强制退出」按钮。

### 明确不做（相对本刀）

- GPU Tab；进程级 GPU。
- 无界全表 ring / 全表成长时序。
- Helper / XPC / Login Item；新 entitlements / TCC 全盘。
- 恐吓文案、「泄漏」、假「需要完全磁盘访问」墙。
- 新 Tab。
- **从菜单栏弹出条** `terminate` / `forceTerminate` 其它进程。
- 改栏上 A 色点外观；栏上写压力字或已用内存。
- 点已用内存行 / 压力行 → 开窗 / 改选中。
- 改「打开 Pulse」为顺便改选中，或拿掉「打开 Pulse」。
- **新 Sampler 采样周期 / cadence**（前台 1.5s、后台 2–3s 不动）。
- Electron / App Store 沙盒。
- 自动杀、常驻通知。
- 第三档恐吓红。
- 第二套 Sampler / 第二路 Mach / 比 Sampler 更快的弹出条刷新。
- 把主窗过滤结果或当前表头排序误当成 Top3。
- 为空态 / 失败造假行再让人点。

## 风险

| 风险 | 应对 |
| --- | --- |
| 忍不住给点选再采一趟 / 新开 period | 上文缺口写死：不是采样缺口；只读当前 `rows` + 现成 focus / `selectedPid`；范围表写死零新 cadence |
| 做成弹出条里直接退出 / 强杀 | 范围表写死；弹出条无退出他人按钮；验收搜 terminate 调用只留主窗侧栏 |
| 点选另写第二套 activate / 第二扇窗 | 必须复用 `PulseAppDelegate.focusMemoryPage()`；禁止新 `WindowGroup` |
| 「打开 Pulse」被改成也改选中 | 点击语义表写死：无 pid 的 `focusMemoryPage()` 保持今日行为 |
| 画出来的 pid 点击时已消失，却造行或写死 pid | select-if-present：只对照当下 `rows`；消失仍开主窗、不写该 pid |
| `processListFailed` / 空 Top3 造假行 | 投影已空；无行可点；不装 0 |
| 跳到 CPU / 网络 / 磁盘 / GPU | 必须走 `focusMemoryPage()`；验收钉内存页 |
| 把过滤表或表头排序当成 Top3 | 投影仍吃 Sampler 内存降序完整 `rows` |
| 压力 / 已用内存行也被做成可点 | 范围表写死：只翻 Top3 |
| 改栏上 A 色点 | A 外观表写死不改 |
| 弹出条刷新快过 Sampler | 只订 `objectWillChange`；禁止自备 timer |
| 恐吓红 / 危急 / 「泄漏」 | 次要色；验收搜禁词 |
| Helper / 新 entitlement / GPU / 新 Tab | 范围表写死不加 |
| 借本刀改九期 series 或 Sampler tick | 本刀零 Sampler；十期已用内存行不在重开范围 |

## 验收（十一期首包）

产品 Must：

- [ ] Top3 **有进程的行**可点；点一行 → 收起弹出条 + 打开 / 聚焦**现有**主窗 + **落到内存页** + 该 pid 仍在 `rows` 时 `selectedPid` 已是该进程，侧栏现成「退出 / 强制退出」就绪
- [ ] 「打开 Pulse」仍只打开 / 聚焦并落内存页，**不改**当前选中（现成 `PulseAppDelegate.focusMemoryPage()`）
- [ ] 绘制到点击之间 pid 已从 `rows` 消失：仍打开 / 聚焦主窗内存页；不写该消失 pid；不造假行；侧栏冷静空态 / 保持未选中该 pid
- [ ] `processListFailed` 或 Top3 为空：只显示「暂无进程」，无行可点，不造假行
- [ ] 十期已用内存行保留且不可点；压力行不可点；栏上 A 色点外观不改
- [ ] 弹出条只读同一 `MemoryDashboardVM` 当前快照；无第二套 Sampler / VM / Mach 轮询
- [ ] **无新 Sampler period / cadence**；刷新不得快过 Sampler
- [ ] 单列、次要文字色、无红色闪烁；永不写「危急 / 泄漏 / 危险」
- [ ] 弹出条不 terminate / forceTerminate；退出只走主窗侧栏现成动作

明确不做（本包出现即不合格）：

- [ ] 无 GPU Tab、无进程级 GPU、无新 Tab
- [ ] 无无界全表 ring
- [ ] 无 Helper / XPC / 登录项、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无菜单栏结束 / 强杀其它进程
- [ ] 无新 Sampler cadence
- [ ] 无恐吓文案、无「泄漏」、无假权限墙
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 无自动杀、无常驻通知
- [ ] 压力无第三档恐吓红；栏上色点外观不改
- [ ] 不跳到非内存 Tab；不点已用内存行开窗

共性：

- [ ] 一二三四五六七八九十期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏 A / 七期 B 压力与「打开 Pulse」、十期已用内存行、详情增长软信号、九期 Top5∩rising 徽标、退出链路）。Top3 可点性以**本文**为准（覆盖七 / 十期「不可点」）
- [ ] 冷启动仍默认内存页
- [ ] 单测（便宜就写）：`focusMemoryPage()` 不改选中；pid 仍在则选中、消失则不写该 pid；空 / `processListFailed` 无行；禁词；无弹出条 terminate
- [ ] 不改公证脚本与 entitlements

## 工期

小：约 **0.5–1 天**——按「选中 / 聚焦 API + 单测（若缺）→ Top3 tap + 收起 popover」拆，不是功能周。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。
