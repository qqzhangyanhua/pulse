# Pulse 十期技术设计（首包：菜单栏轻量条 B — 主机已用内存一行）

> 归档：这是第 10 期落地前的设计稿，写完后不再修改。当前实现以 [TECH.md](../TECH.md) 为准，后续期数可能已经改动这里的范围或口径。

> 一期至九期正文不改写。七期锁了弹出条 B（压力一行 + Top3 +「打开 Pulse」）；八期按该三块冒烟；九期只改内存列表徽标密度、不改菜单栏——**本文只覆盖 B 的信息补全**：在现成压力行下加**一行主机已用内存**。不新开采样器、不第二套 VM、不第二扇窗。GPU Tab、进程级 GPU、无界全表 ring、Helper / XPC、恐吓文案 / 「泄漏」、新 Tab、点击行跳转、新 Sampler 周期、新 entitlements、自动杀、Electron 仍不做。

**已锁定**：十期 = **小刀：菜单栏弹出条 B 信息补全**。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`；同一套七期 `NSStatusItem` / `NSPopover` 壳。栏上仍是二期交互 **A**（只画压力色点，栏上不写压力文案、不写已用内存）。弹出条自上而下四行（产品已锁，可改词不改义）：① 主机压力一行（七期原样，只复用 `normal | elevated`）；② **主机已用内存一行**（次要文字色；有数写「已用 xx GB」，无数写「暂时读不到」）；③ 内存占用 Top **3**（名称 + 内存，不改）；④ 底栏「打开 Pulse」（不改）。没有第二扇窗、没有第二套详情面。空态仍冷静、次要色、**不装 0、不红闪**。采样周期不变（前台约 1.5s，主窗后台或已关、菜单栏保活时约 2–3s）；**零新 Sampler period / cadence**，弹出条刷新不得快过 Sampler。不新开 entitlements、不拆 Helper / XPC。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：用户 + 产品锁定的十期 Must（九期密度已合 #29–#31；七期 B 已合 #25–#27）；对照现实现（`MenuBarController` 同进程 `NSStatusItem` + `NSPopover`；`MenuBarPopoverView` 三槽：`hostPressure` / `topProcesses` / `openPulse`；`MenuBarPopoverSnapshot` 只投影 `pressure` + `processes`；`MemoryDashboardVM` 已暴露 `snapshot` / `rows` / `samplingFailed` / `processListFailed`；`MemorySnapshot.usedBytes` 已由同一 `sample()` 写入，主窗用量大数已用 `ByteFormat.memory`）。

## 范围（相对一二三四五六七八九期）

| 项 | 一二三四五六七八九期 | 十期首包 |
| --- | --- | --- |
| 定位 | 七期：B = 压力一行 + Top3 +「打开 Pulse」；八期按该三块冒烟；九期不改菜单栏 | **信息补全**：同一条 B，压力行下加一行主机已用内存 |
| 菜单栏外观 A | 栏上仅压力色点；不写压力字、不写已用内存 | **A 外观不变**。已用内存只进弹出条，不回到栏上 |
| 弹出条 B | 七期三槽已接线 | **做（本刀）**：压力行下加已用内存一行；Top3 +「打开 Pulse」不动 |
| 压力语义 | `normal \| elevated` 两档；文案只进 B | **仍两档、仍原句**。不因已用内存改色点或升第三档 |
| 主机已用内存 | `MemorySnapshot.usedBytes` 已采；只在主窗用量大数出现 | **做**：只读投影到 B；不新开采样 |
| 采样 | 单 `MemorySampler`；前台 ~1.5s，后台 ~2–3s。七期零 Sampler；九期只允许有界 Top5 series、不是新周期 | **零 Sampler 改动、零新 period / cadence**。弹出条只读当前快照 |
| Top3 | 已采 `rows` 内存降序前 3 | **不改**。不因本刀可点、不跳主窗 |
| 「打开 Pulse」 | 现成 `focusMemoryPage()` | **不改** |
| GPU Tab / 进程级 GPU | 灰置 / 不做 | **仍灰置、仍不做** |
| 无界全表 ring | 九期只允许 Top N=5 有界 series | **仍不做**。本刀不碰 series / ring |
| 点击行跳转 | 七期 Top3 只读；九期徽标不可点 | **仍不可点**。不因已用内存行或 Top3 跳详情 / 改选中 |
| 新 Tab | 无 | **仍无** |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 / 恐吓文案 | 不做 / 禁止 | **仍禁止**。永不写「泄漏」 |

一二三四五六七八九期验收与公证路径不因本文重开。七期 B 的压力 / Top3 / 「打开 Pulse」语义不重开，只在压力行下补一行。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

优先**延长**七期同进程弹出条路径，不要另起 Helper / XPC，也不要退回 `MenuBarExtra`，也不要新开第二套 popover。

- `MenuBarController`（同进程 `NSStatusItem` + `NSPopover`）←观察→ 同一 `MemoryDashboardVM`（现已 `observe(objectWillChange)` 重绘色点与 B）
- 弹出条仍挂在同一状态项按钮上，**不是**第二个 `WindowGroup`
- 「打开 Pulse」仍走现成 `PulseAppDelegate.focusMemoryPage()`
- VM ←订阅快照→ `MemorySampler`（同一 Actor）；弹出条**不**调 `sample()`
- 右键「退出 Pulse」与弹出条内容正交，本刀不改

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询。
- 弹出条是当前快照的只读投影，不是第二套诊断器。
- 不改 `Pulse.entitlements`、不改公证脚本、不改栏上色点映射（`MenuBarDot.resolve` 仍只服务 A）。
- 自身占用仍优先：已用内存行跟色点 / 压力行共用同一 `objectWillChange`；禁止为这一行另开 timer。
- 关主窗仍留菜单栏；弹出条随状态项走，不单独保活。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `Pulse/MenuBar/*`、`MemoryDashboardVM`、`MemorySnapshot`、`ByteFormat`、七期 TECH。本刀必须按「已有 / 没有」落笔，**禁止**为已用内存再采一趟，也**禁止**新开 Sampler 周期。

| 现字段 / 调用 | 文件 | 十期怎么用 |
| --- | --- | --- |
| `NSStatusItem` + `NSPopover` + `MenuBarPopoverView` | `MenuBar/MenuBarController.swift`、`MenuBarPopoverView.swift` | **延长这条壳**。不换宿主、不加第二扇窗 |
| `MenuBarPopoverSection` 三槽 | `MenuBar/MenuBarStatus.swift` | 压力 / Top3 / 「打开 Pulse」槽位保留。已用内存是压力行**下**的次要一行，不是新的对等主槽（不加第四条 Divider 把它升成独立块） |
| `MenuBarPopoverSnapshot` | 同上 | 今天只有 `pressure` + `processes`。**本刀加只读投影**（见下），不改采样模型 |
| `MemoryDashboardVM.snapshot` / `.menuBarPopover` | `ViewModels/MemoryDashboardVM.swift` | 弹出条只读这些。`project` 补传已有 `snapshot.usedBytes`；不新开 `@Published` 采样字段 |
| `MemorySnapshot.usedBytes` / `.totalBytes` / `.pressure` | `Models/MemoryModels.swift` | **已用内存行吃 `usedBytes`**。`pressure` 仍只服务压力行。不要为 B 再读一遍 Mach |
| `ByteFormat.memory` | `Views/SharedUI.swift` | 与主窗用量大数同一格式器。产品句式「已用 xx GB」=「已用」+ 该格式器 |
| `MenuBarCopy.unavailableTooltip` | `MenuBarStatus.swift` | 空态复用「暂时读不到」。不另作文案 |
| `MenuBarDot.resolve` / 栏上 A | 同上 | **栏上仍不写已用内存** |
| Sampler `sample()` / `SamplingPace` | `Sampling/MemorySampler.swift`、`SamplingPace.swift` | **不改**。无新字段、不改 tick、不第二路 Mach |

**缺口**：投影类型 `MenuBarPopoverSnapshot` 今天不带主机已用内存；视图也只画压力一行。这**不是**采样缺口——`MemorySnapshot.usedBytes` 已在同一帧里，主窗英雄卡已经在画。不要把「投影缺一列」读成「要新开 period」。

因此本刀：

1. **零 Sampler 改动**（无新字段、不改 tick、不第二路 Mach、**零新 period / cadence**）。
2. 模型侧只加只读投影：例如给 `MenuBarPopoverSnapshot` 加 `usedBytes: UInt64?`（或等价只读行）。`project` 与压力行同一可读性门：`samplingFailed` 或无 snapshot → `nil`；有 snapshot 且未失败 → 吃 `snapshot.usedBytes`。失败或无数 → 空态「暂时读不到」，不造「已用 0 GB」。
3. 文案句式锁在投影 / 视图：有数 → **已用** + `ByteFormat.memory(usedBytes)`；无数 → **暂时读不到**。不要给 `MemorySnapshot` / `ProcessRow` 加「菜单栏专用」字段。
4. 不要新建第二个 `MemoryDashboardVM` 给这一行用。
5. Top3 仍不可点；已用内存行也不可点。不跳详情、不改选中。

若 SamplingCore 测不到 `Views` 里的 `ByteFormat`：把「已用」句式与空态放在可测投影上，格式化仍调用现成函数（或把格式器抽到已在 SamplingCore 的模块），**禁止**为此新开采样文件。

### 建议工程顺序

信号已经在快照里？**已用字节有，弹出条没有。** 不需要先开采样 PR。

合并后工程顺序（本文只锁设计；**本 docs PR 不写 Swift**）：

1. **纯投影 + 单测**：`usedBytes` 有 / 无（及 `samplingFailed` 藏旧值）→ 已用内存行文案。钉：有 snapshot →「已用」+ 与主窗同一格式；无 snapshot / 失败 →「暂时读不到」，不装 0、不写假「已用 0 GB」。压力行 / Top3 投影不回退。零 Sampler 改动。
2. **接线弹出条 B**：在压力行下画次要层级的已用内存一行（同信息块、次要文字色、无红闪）；Top3 与「打开 Pulse」顺序、交互不动。
3. **没有硬伤就不开 polish PR**。有硬伤：一个行为一个最小 fix，不要和 GPU / Helper / 新周期捆在一起。

能保持零 Sampler 改动时不要先开采样 PR。不要把本刀和 GPU / 自动杀 / Helper 捆在一起。合并不擅自写代码。

## UI 绑定

结论：栏上 A 不变；B 只在状态项激活时出现。本刀只在压力行下补一行。密度：单列、次要文字色、无红色闪烁。

### 状态项 A（不改外观）

| 快照 | 栏上 | 说明 |
| --- | --- | --- |
| `pressure == .normal` | 冷静绿点 | 与二 / 七期相同；**仍不**在栏上写「正常」或已用内存 |
| `pressure == .elevated` | 冷静琥珀点 | **不**升恐吓红，栏上不写「偏高」、不写「已用」 |
| 无快照 / `samplingFailed` | 灰点 + tooltip「暂时读不到」 | 不装 0、不假装正常 |

- 主点（激活）：出示弹出条 B。
- 右键 / Control-点：现成「退出 Pulse」菜单。
- 栏上仍 `imageOnly`、`statusItemTitle == ""`。

### 弹出条 B 槽位（产品已锁顺序，自上而下）

单列。已用内存行是压力行的**次要下一行**，与压力同一信息块——**不加**新 Divider 把它升成对等主槽。Top3、「打开 Pulse」仍用现成分隔。

| 顺序 | 槽位 | 绑定 | 缺数 |
| --- | --- | --- | --- |
| 1 | 主机压力一行 | `snapshot.pressure` → 现成两档语义（七期原句） | 无快照或采样失败：冷静空态「暂时读不到」 |
| 2 | **主机已用内存一行** | `snapshot.usedBytes` → 产品句式 **已用 xx GB**（「已用」+ `ByteFormat.memory`）；次要文字色 | 无快照或采样失败：**暂时读不到**（与 B 现有不可读空态同一句）；**不**写「已用 0 GB」、不装 0、不红闪 |
| 3 | Top 3 内存进程 | 已采 `rows` 按 `memoryBytes` 降序取 `prefix(3)`；每行名称 + 内存 | 1–2 条就画 1–2 条；0 条或 `processListFailed`：「暂无进程」，不造「0 MB」假行。**仍不可点**，不跳主窗 |
| 4 | 底栏动作 | 「打开 Pulse」 | 始终可点；走现成聚焦 / 打开主窗（默认内存页） |

压力行与已用内存行共用同一可读性门（有 snapshot 且 `!samplingFailed`）。不要出现「压力有数、已用空态」或反过来——它们来自同一帧 `MemorySnapshot`。进程列表失败只影响 Top3，不把已用内存打成空态。

### 文案默认（产品已确认，可改词不改义）

| 表面 | 锁定默认 | 说明 |
| --- | --- | --- |
| 压力 · 正常 | **正常 · 余量充足** | 七期原句；本刀不改 |
| 压力 · 偏高 | **偏高 · 余量紧张** | 七期原句；本刀不改 |
| 压力空态 | **暂时读不到** | 七期原句 |
| 已用内存 · 有数 | **已用 xx GB** | 「已用」+ `ByteFormat.memory(usedBytes)`。主机已用通常 ≥ 1 GiB，呈现即「已用 12.34 GB」这类。单位随格式器（不足 1 GiB 可落到 MB），**不**用 `gibWhole` 把 12.3 收成「已用 12 GB」 |
| 已用内存 · 空态 | **暂时读不到** | 与压力空态、栏上 tooltip 同句；次要文字色；不是「危急」、不是红闪 |
| Top3 内存 | `ByteFormat.memory` | 与主窗列表同一格式器 |
| Top3 空态 | **暂无进程** | 七期原句 |
| 打开动作 | **打开 Pulse** | 七期原句 |

禁止出现：泄漏、泄露、leak、危险、危急、告警、需要完全磁盘访问。验收对锁定字符串与实现字符串搜这些词。

### 明确不做（相对本刀）

- GPU Tab；进程级 GPU。
- 无界全表 ring / 全表成长时序。
- Helper / XPC / Login Item；新 entitlements / TCC 全盘。
- 恐吓文案、「泄漏」、假「需要完全磁盘访问」墙。
- 新 Tab。
- 点击行（已用内存行或 Top3）→ 跳详情 / 改选中 / 打开主窗。
- **新 Sampler 采样周期 / cadence**（前台 1.5s、后台 2–3s 不动）。
- Electron / App Store 沙盒。
- 自动杀、常驻通知。
- 第三档恐吓红；栏上写压力字或已用内存。
- 第二套 Sampler / 第二路 Mach / 比 Sampler 更快的弹出条刷新。
- 把主窗过滤结果或当前表头排序误当成 Top3。
- 失败时装「已用 0 GB」或红闪空态。

## 风险

| 风险 | 应对 |
| --- | --- |
| 忍不住给已用内存再采一趟 / 新开 period | 上文缺口写死：不是采样缺口；只读 `snapshot.usedBytes`；范围表写死零新 cadence |
| 做成栏上短度量 | A 外观表写死：已用内存只进 B |
| 把已用内存升成第四个对等主槽 / 新 Divider 块 | 槽位表写死：压力行下、同一信息块、次要层级 |
| 失败装「已用 0 GB」 | 空态「暂时读不到」；单测钉失败 / 无快照 → 无假 0 |
| 用 `gibWhole` 或另造格式器，和主窗大数对不上 | 锁 `ByteFormat.memory`；产品「xx GB」是句式，不是另开整 GB 取整 |
| 压力有数、已用空态（或反过来） | 同一可读性门；同一帧 `MemorySnapshot` |
| Top3 / 已用内存行可点跳转 | 范围表写死不可点；不做 button / tap |
| 弹出条刷新快过 Sampler | 只订 `objectWillChange`；禁止自备 timer |
| 恐吓红 / 危急 / 「泄漏」 | 次要色；验收搜禁词 |
| Helper / 新 entitlement / GPU / 新 Tab | 范围表写死不加 |
| 借本刀改九期 series 或 Sampler tick | 本刀零 Sampler；九期有界 Top5 不在范围内 |

## 验收（十期首包）

产品 Must：

- [ ] 弹出条 B 自上而下：压力一行（七期原句）→ **已用内存一行** → Top3 →「打开 Pulse」
- [ ] 有 snapshot 且未采样失败：已用内存行写 **已用 xx GB**（「已用」+ `ByteFormat.memory(snapshot.usedBytes)`，与主窗用量大数同一格式器）；次要文字色
- [ ] 无 snapshot 或采样失败：已用内存行写 **暂时读不到**；次要文字色；无红闪；不装「已用 0 GB」
- [ ] 栏上仍只是交互 A 压力色点；无压力文字、无已用内存串
- [ ] Top3 +「打开 Pulse」不回退；Top3 / 已用内存行不可点、不跳详情
- [ ] 弹出条只读同一 `MemoryDashboardVM` 当前快照；无第二套 Sampler / VM / Mach 轮询
- [ ] **无新 Sampler period / cadence**；刷新不得快过 Sampler
- [ ] 单列、次要文字色、无红色闪烁；永不写「危急 / 泄漏 / 危险」

明确不做（本包出现即不合格）：

- [ ] 无 GPU Tab、无进程级 GPU、无新 Tab
- [ ] 无无界全表 ring
- [ ] 无 Helper / XPC / 登录项、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无点击行跳转
- [ ] 无新 Sampler cadence
- [ ] 无恐吓文案、无「泄漏」、无假权限墙
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 无自动杀、无常驻通知
- [ ] 压力无第三档恐吓红；栏上不写已用内存

共性：

- [ ] 一二三四五六七八九期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏 A / 七期 B 压力与 Top3、详情增长软信号、九期 Top5∩rising 徽标、退出链路）
- [ ] 冷启动仍默认内存页
- [ ] 投影 / 单测：已用内存有数 / 空态；失败不装 0；压力行与 Top3 不回退；禁词
- [ ] 不改公证脚本与 entitlements

## 工期

小：约 **0.5 天或更短**——按「纯投影 + 单测 → 接线 B」拆，不是功能周。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。
