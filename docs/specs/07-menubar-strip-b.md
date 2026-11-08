# Pulse 七期技术设计（首包：菜单栏轻量条 B）

> 归档：这是第 7 期落地前的设计稿，写完后不再修改。当前实现以 [TECH.md](../TECH.md) 为准，后续期数可能已经改动这里的范围或口径。

> 一期至六期正文不改写。二期锁了菜单栏交互 **A**（栏上仅压力色点）；三期至六期写明「菜单栏弹出条 B 仍不做 / 延期」——**本文只覆盖那条延期**：状态项激活时弹出轻量条 B。不新开采样器、不第二套 VM、不第二扇窗。GPU Tab、恐吓文案、假权限墙、菜单栏内结束进程、弹出条趋势图、恐吓红块、第二套详情面、Helper / XPC / 登录项、新 entitlements / TCC 全盘、Electron / App Store 沙盒、自动杀、常驻通知仍不做。

**已锁定**：菜单栏轻量条 **B**（popover / 轻量条）。栏上外观仍是二期交互 **A**：只画压力色点，栏上不写压力文案、不写已用内存。点击状态项 → 弹出 B；弹出内容为只读投影，绑**同一个** `MemoryDashboardVM` / `MemorySampler` 当前快照。弹出条三块（设计已锁）：① 一行主机压力，只复用现成 `normal | elevated`；② 内存占用 Top **3**（名称 + 内存，内存降序）；③ 底栏动作「打开 Pulse」→ 聚焦 / 打开**现有**主窗（默认内存页）。没有第二扇窗、没有第二套详情面。少于 3 个进程就展示现有条数；空态 / 失败走冷静空态，**不装 0**。采样周期不变（前台约 1.5s，主窗后台或已关、菜单栏保活时约 2–3s）；弹出条刷新不得快过 Sampler。仍单进程、单 Target、macOS 14+、非沙盒 Hardened Runtime。不新开 entitlements、不拆 Helper / XPC。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：用户 + 产品锁定的七期 Must；对照现实现（`Pulse/MenuBar/MenuBarController` 同进程 `NSStatusItem`，主点目前直接 `onFocusMemory`；`MenuBarStatus` 的 `MenuBarDot` / `MenuBarPointer` / `MenuBarSamplingGate`；`PulseAppDelegate.focusMemoryPage()` 已能聚焦或打开主窗并落内存页；`MemoryDashboardVM` 已暴露 `snapshot` / `rows` / `samplingFailed` / `processListFailed`；`MemorySampler` 已按 `memoryBytes` 降序排好 `rows`）。

## 范围（相对一二三四五六期）

| 项 | 一二三四五六期 | 七期首包 |
| --- | --- | --- |
| 菜单栏外观 | 交互 A：栏上仅压力色点；主点直接回主窗内存页 | **A 外观不变**。主点改为弹出轻量条 **B**；「打开 Pulse」复用今日这条聚焦 / 打开主窗路径 |
| 弹出条 B | 三期起明确延期 | **做（本刀）**：压力一行 + Top3 + 「打开 Pulse」 |
| 压力语义 | `normal \| elevated` 两档；栏上不写字 | **仍两档**。压力**文案只进弹出条**，不回到栏上；无第三档恐吓红 |
| Top3 | 主窗内存表已按内存降序 | **做**：从**已采**进程列表按内存取前 3；不新开枚举 |
| 采样 | 单 `MemorySampler`；前台 ~1.5s，后台 ~2–3s | **零 Sampler 改动**。弹出条只读当前快照 |
| GPU Tab | 灰置 | **仍灰置** |
| 增长软信号 / 列表角标 | 三期详情 + 六期内存列表 | **不进弹出条**。不因增长改色点 |
| 菜单栏结束进程 | 仅右键「退出 Pulse」（卸本 App） | **仍不做**从菜单栏 `terminate` / 强杀其它进程 |
| 文案 | 禁泄漏 / 危险 | **仍禁止**。另禁危急 / 告警 / leak / 需要完全磁盘访问 |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 | 不做 | **仍不做** |

一二三四五六期验收、交互 A 色点映射、CPU / 网络 / 磁盘 Tab、详情增长三态、内存列表上涨角标、公证路径不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

优先**延长**现成同进程菜单栏路径，不要另起 Helper / XPC，也不要退回二期已放弃的 `MenuBarExtra`（实现注释已写明：`.menu` 会变成菜单、`.window` 会变成浮层窗）。

- `MenuBarController`（同进程 `NSStatusItem`）←观察→ 同一 `MemoryDashboardVM`（现已 `observe(objectWillChange)` 只重绘色点）
- 弹出条 B 挂在同一状态项按钮上（建议 `NSPopover` + SwiftUI 宿主，或等价同进程轻量面板），**不是**第二个 `WindowGroup`
- 「打开 Pulse」→ 现成 `PulseAppDelegate.focusMemoryPage()`（`dashboard.focusMemoryPage()` + `NSApp.activate` + 找到 `PulseWindowID.main` 或 `openWindow`）
- VM ←订阅快照→ `MemorySampler`（同一 Actor）；弹出条**不**调 `sample()`
- 右键「退出 Pulse」可保持现状（`MenuBarCopy.quitTitle` → `NSApp.terminate`）；与弹出条内容正交

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询。
- 弹出条是当前快照的只读投影，不是第二套诊断器。
- 不改 `Pulse.entitlements`、不改公证脚本、不改栏上色点映射（`MenuBarDot.resolve` 仍只服务 A）。
- 自身占用仍优先：弹出条跟色点共用同一 `objectWillChange`；禁止为 B 另开 timer。
- 关主窗仍留菜单栏；⌘Q / 「退出 Pulse」仍卸项。弹出条随状态项走，不单独保活。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `Pulse/MenuBar/*`、`MemoryDashboardVM`、`MemorySampler`、`ProcessRow`、`PressureLevel`。本刀必须按「已有 / 没有」落笔，**禁止**为弹出条再采一趟。

| 现字段 / 调用 | 文件 | 七期怎么用 |
| --- | --- | --- |
| `NSStatusItem` + 主点 `onFocusMemory` | `MenuBar/MenuBarController.swift` | **延长这条**。主点改为出示 popover；聚焦主窗改挂到「打开 Pulse」 |
| `MenuBarDot.resolve(pressure:samplingFailed:)` | `MenuBar/MenuBarStatus.swift` | **栏上 A 原样**。弹出条压力行读同一 `PressureLevel`，但**另外**写文案，不把字写回 `statusItemTitle` |
| `MenuBarPointer.primary` | 同上 | 现注释写「主点聚焦内存页、不打开面板」。七期主点改为打开 B；右键仍可出退出菜单 |
| `PulseAppDelegate.focusMemoryPage()` | `MenuBar/PulseAppDelegate.swift` | 「打开 Pulse」的**唯一**打开 / 聚焦路径。不新写第二套 activate |
| `MainWindowAnchor` + `MenuBarSamplingGate` | `MenuBar/MainWindowAnchor.swift`、`MenuBarStatus.swift` | 关窗降频续采已有；弹出条不得改周期 |
| `MemoryDashboardVM.snapshot` / `rows` / `samplingFailed` / `processListFailed` | `ViewModels/MemoryDashboardVM.swift` | 弹出条只读这些。不新开 `@Published` 采样字段 |
| `PressureLevel.title` / `.caption` | `Models/MemoryModels.swift` | 「正常 / 偏高」「余量充足 / 余量紧张」。弹出条复用，不发明第三档 |
| `ProcessRow.name` / `.memoryBytes` | 同上 | Top3 字段。格式化复用现成 `ByteFormat.memory` |
| Sampler `rows.sort`（`memoryBytes` 降序，pid 升序稳定） | `Sampling/MemorySampler.swift` | Top3 的排序来源。**不要**跟主窗当前表头排序走，**不要**吃 `visibleRows` 过滤结果 |
| `SamplingPace` 前台 1.5s / 后台 3s | `Sampling/SamplingPace.swift` | **不改** |

**缺口**：没有 popover 壳，也没有「压力行 + Top3」投影类型。这**不是**采样缺口——`snapshot.pressure` 与已排序 `rows` 已够用。主点今天直接聚焦主窗，是二期 A 的点击语义；七期把「出示 B」和「打开主窗」拆开，打开动作仍走原路径。

因此本刀：

1. **零 Sampler 改动**（无新字段、不改 tick、不第二路 Mach）。
2. 模型侧最多加只读投影，例如 `MenuBarPopoverSnapshot`：从 `snapshot` / `rows` / 失败旗标算出压力行文案 + 最多 3 条 `{name, memoryBytes}`；失败或无列表 → 空态，不造 0 字节行。
3. **不要**给 `ProcessRow` 加「菜单栏专用」字段，也不要为 Top3 另开枚举 flavor。
4. 不要新建第二个 `MemoryDashboardVM` 给弹出条用。

### 建议模块 PR 顺序

信号已经在菜单栏里？**色点有，弹出条没有。** 也不需要先开采样 PR。

合并后工程顺序（本文只锁设计；**本 docs PR 不写 Swift**）：

1. **弹出条壳**：主点 → 挂在状态项上的 popover；单列空槽 + 底栏「打开 Pulse」接到现成 `focusMemoryPage()`；右键退出菜单不变；栏上仍只是 A 色点。零 Sampler 改动。
2. **接线压力行 + Top3**：只读投影 + `swift test`（两档压力、失败空态、0/1/2/3 条、不装 0）→ 填进壳子。

能保持零 Sampler 改动时不要先开采样 PR。不要把本刀和 GPU / 自动杀 / Helper 捆在一起。合并不擅自写代码。

## UI 绑定

结论：栏上 A 不变；B 只在状态项激活时出现。密度：单列、次要文字色、无红色闪烁。

### 状态项 A（不改外观）

| 快照 | 栏上 | 说明 |
| --- | --- | --- |
| `pressure == .normal` | 冷静绿点 | 与二期相同；**仍不**在栏上写「正常」 |
| `pressure == .elevated` | 冷静琥珀点 | **不**升恐吓红，栏上不写「偏高」 |
| 无快照 / `samplingFailed` | 灰点 + tooltip「暂时读不到」 | 不装 0、不假装正常 |

- 主点（激活）：出示弹出条 B，**不再**直接聚焦主窗。
- 右键 / Control-点：可保持现成「退出 Pulse」菜单；不替代 ⌘Q。
- 栏上仍 `imageOnly`、`statusItemTitle == ""`。

### 弹出条 B 槽位（设计已锁）

单列，自上而下：

| 槽位 | 绑定 | 缺数 |
| --- | --- | --- |
| 主机压力一行 | `snapshot.pressure` → 现成两档语义 | 无快照或采样失败：冷静空态（建议复用「暂时读不到」），**不**写假「正常」、不写 0% |
| Top 3 内存进程 | 已采 `rows` 按 `memoryBytes` 降序取 `prefix(3)`；每行 **名称 + 内存** | 1–2 条就画 1–2 条；0 条或 `processListFailed`：冷静空态（如「暂无进程」），**不**造「0 MB」假行 |
| 底栏动作 | 「打开 Pulse」 | 始终可点；走现成聚焦 / 打开主窗（默认内存页）。弹出条可在动作后收起 |

### 文案默认（冷静，可改词不改义）

| 表面 | 锁定默认 | 说明 |
| --- | --- | --- |
| 压力 · 正常 | **正常 · 余量充足** | `PressureLevel.title` + `.caption` |
| 压力 · 偏高 | **偏高 · 余量紧张** | 琥珀语义可跟主窗压力卡，但弹出条不用红块、不闪 |
| 压力空态 | **暂时读不到** | 与栏上 tooltip 同句；不是「危急」 |
| Top3 内存 | `ByteFormat.memory` | 与主窗列表同一格式器 |
| Top3 空态 | **暂无进程** | 或同等冷静句；禁止 0 字节占位 |
| 打开动作 | **打开 Pulse** | 不写「立即处理」「结束进程」 |

禁止出现：泄漏、泄露、leak、危险、危急、告警、需要完全磁盘访问。验收对锁定字符串与实现字符串搜这些词。

### 明确不做（相对本刀）

- GPU Tab。
- 恐吓文案、假「需要完全磁盘访问」墙。
- 从菜单栏 `terminate` / `forceTerminate` 其它进程。
- 弹出条内趋势图、恐吓红块、第二套详情面 / 第二扇窗。
- Helper / XPC / Login Item；新 entitlements / TCC 全盘。
- Electron / App Store 沙盒。
- 自动杀、常驻通知。
- 第三档恐吓红；栏上写压力字或已用内存。
- 第二套 Sampler / 第二路 Mach / 比 Sampler 更快的弹出条刷新。
- 把主窗过滤结果或当前表头排序误当成 Top3。

## 风险

| 风险 | 应对 |
| --- | --- |
| 忍不住给弹出条再采一趟 | 上文缺口写死：不是采样缺口；只读 `snapshot` / `rows` |
| 主点仍直接开主窗，B 变成死文档 | 点击语义表：主点 = 出示 B；「打开 Pulse」= 今日 `focusMemoryPage()` |
| 做成第二扇窗 / `MenuBarExtra.window` | 挂在现有 `NSStatusItem` 按钮上；禁止新 `WindowGroup` |
| Top3 跟过滤表或 CPU 排序走 | 投影只吃 Sampler 内存降序的完整 `rows`，不吃 `visibleRows` |
| 失败装 0 / 假「正常」 | 空态文案；单测钉「失败 → 无假行、压力非 normal」 |
| 弹出条刷新快过 Sampler | 只订 `objectWillChange`；禁止自备 timer |
| 恐吓红 / 危急文案 | 压力仍两档；验收搜禁词 |
| 菜单栏里结束进程 | 范围表写死；弹出条无退出他人按钮 |
| Helper / 新 entitlement | 范围表写死不加 |

## 验收（七期首包）

产品 Must：

- [ ] 栏上仍只是交互 A 压力色点：正常绿 / 偏高琥珀 / 失败灰点；无压力文字、无已用内存串
- [ ] 点击状态项弹出轻量条 B（不是第二扇窗）：压力一行 + Top3（名称 + 内存，内存降序）+ 「打开 Pulse」
- [ ] 压力只复用 `normal \| elevated`；永不写「危急 / 泄漏 / 危险」
- [ ] Top3 来自已采进程列表的内存排序；少于 3 条展示现有条数；空 / 失败为冷静空态，不装 0
- [ ] 「打开 Pulse」聚焦或打开**现有**主窗，并落到内存页（复用 `PulseAppDelegate.focusMemoryPage()`）
- [ ] 弹出条只读同一 `MemoryDashboardVM` 当前快照；无第二套 Sampler / VM / Mach 轮询
- [ ] 采样周期不因弹出条加快；刷新不得快过 Sampler
- [ ] 单列、次要文字色、无红色闪烁

明确不做（本包出现即不合格）：

- [ ] 无 GPU Tab
- [ ] 无恐吓文案、无假权限墙
- [ ] 无菜单栏结束 / 强杀其它进程
- [ ] 无弹出条趋势图、无恐吓红块、无第二套详情面 / 第二扇窗
- [ ] 无 Helper / XPC / 登录项、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 无自动杀、无常驻通知
- [ ] 压力无第三档恐吓红

共性：

- [ ] 一二三四五六期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏色点映射、详情增长软信号、内存列表上涨角标、退出链路）
- [ ] 冷启动仍默认内存页
- [ ] 投影 / 单测：两档压力、失败空态、不足 3 条、禁词
- [ ] 不改公证脚本与 entitlements

## 工期

小：按「弹出条壳 → 接线压力行 + Top3」拆两个工程 PR（能保持零 Sampler 改动则不要先开采样 PR），天级，不是周级。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。
