# Pulse 一期技术设计

> 对齐 `docs/PRD.md` 与高保真定稿。目标：SwiftUI 原生、内存单页采样与模型、退出链路、Developer ID + 公证直装。不做 Electron、不做 App Store 沙盒、不做增长斜率/判泄漏、不做磁盘/网络/GPU/菜单栏 Tab。

**已锁定**：单进程 App + 后台采样 Actor + SwiftUI 绑定。前台采样默认约 1.5s（可调 1–2s）；压力 UI 只暴露 `normal | elevated` 两档。

来源：研发锁定的一期技术设计（采样 / 模型 / 权限 / 分发），并对照 UI 合并后的现状（1.5s 采样、两档压力、Hardened Runtime + 公证路径）。

## 架构

- 仓库：`qqzhangyanhua/pulse`，macOS 14+，SwiftUI + 必要 AppKit（如 `NSAlert` 强制退出确认）。
- 单 Target，一期无 Helper / XPC。
- 分层：
  - `SwiftUI Views` ←观察→ `MemoryDashboardVM`
  - `MemoryDashboardVM` ←订阅快照→ `MemorySampler`（Actor）
  - `MemorySampler` → Mach `host_statistics64` / `vm_statistics64`；→ `ProcessEnumerator`
  - Views → `ProcessActions` → `NSRunningApplication`（按 pid）

约束：

- 快照为不可变 `struct`；采样在后台 Actor，主线程只读。
- Charts 画压力与选中进程曲线；自身占用优先于刷新华丽度。
- 用量曲线可由视图侧基于已有快照 ring 绘制，**不**为此改采样器。

## 采样与数据源

| 能力 | 来源 | 说明 |
| --- | --- | --- |
| 用量大数 / 分类条 | `vm_statistics64` + `host_statistics64` | App / Wired / Compressed / Cached；字节统一后再格式化 |
| 压力档与曲线 | 压力相关统计；UI 指标可用 `pressureMetric`（已用 / 物理内存） | 只暴露正常 / 偏高；曲线 ring buffer ~60–120 |
| 进程列表 | `proc_listpids` / `proc_pidinfo` 或 libproc | name、pid、cpu%、rss、threadCount |
| 机型信息 | sysctl / `ProcessInfo` | 顶栏；不阻塞首屏 |
| 单进程时序 | 选中后对 pid 重采写入 ring | 切进程清空 |

坑点：

- 进程名与图标走 `NSRunningApplication` / Bundle；无 GUI 守护进程显示可执行名即可。
- 采样失败进「采样中 / 失败」态，**不假装 0**。
- 交换若不在快照中，UI 显示「— / 未采样」，不写成 0 字节。

## 领域模型

- `PressureLevel`：`normal | elevated`（文案冷静，如「余量充足」/「余量紧张」；偏高用琥珀而非恐吓红）。
- `MemorySnapshot`：used/total、分类字节、pressure、pressureSeries。
- `ProcessRow`：pid、name、icon?、cpuPercent、memoryBytes、threadCount。
- `ProcessDetail`：row + memorySeries + cpuSeries。
- `DashboardState`：snapshot?、rows、filter、selectedPid?、sampling、quitBusy/error。

默认排序：内存降序（稳定排序）。过滤：本地名称 `localizedCaseInsensitiveContains`，无服务端。

「占用最多的 App」可为视图侧按进程名聚合，仍绑定现有 rows，不新增采样通道。

## UI 绑定与状态（一期）

1. **冷启动**：默认内存页；其它资源 Tab 灰置不可点；先骨架再填第一帧。
2. **列表**：过滤即时；点行设 `selectedPid`；无选中侧栏空态克制。
3. **四态**：选中 / 空态 / 压力偏高 / 采样中与过滤无结果（可叠）。
4. **退出**：主按钮 `terminate()`；失败后可 `forceTerminate()`（系统确认）。侧栏内存主、CPU 辅。

明确不做：分享；侧栏功耗/GPU/磁盘/网络小格；文件夹按钮；二期 Tab 实现。

## 权限与分发

| 项 | 一期方案 |
| --- | --- |
| 退出 | `NSRunningApplication.terminate()` |
| 强制退出 | 系统确认后 `forceTerminate()`；无自研恐吓文案 |
| 权限 | 不申请 TCC 全盘；不碰 kext；Hardened Runtime 开启；空 entitlements、非沙盒 |
| 分发 | Developer ID + 公证直装（dmg/zip）；不做 App Store 沙盒 |
| 自身影响 | Instruments 抽查；前台默认 ~1.5s，可调到 2s 换占用；切后台降频或暂停 |

公证需本机 Apple 开发者账号；脚本做到「可签」为止，真正公证由机主执行。

## 风险

| 风险 | 应对 |
| --- | --- |
| 压力 API 语义漂移 | 抽象 PressureProvider；UI 只绑两档枚举 |
| 采样拖慢本机 | 后台 Actor + 降频；列表虚拟化 |
| 无法退出受保护进程 | 失败态可见；不强杀系统关键进程 |
| 公证/签名阻塞 | 先本地 Debug / Hardened Runtime `.app` 验收；签名并行 |

## 验收对齐（相对 PRD）

- [ ] 冷启动默认内存页 + 按内存降序
- [ ] 用量大数、分类条、压力档与曲线
- [ ] 名称过滤 + 无结果空态
- [ ] 侧栏内存主曲线 + CPU 辅曲线，切进程重采
- [ ] `terminate` → `forceTerminate` + 系统确认
- [ ] 前台 1–2s 采样、占用克制
- [ ] 文案无恐吓措辞
- [ ] 约 30 秒定位并退出通
- [ ] 公证完成，或至少 Hardened Runtime 本地 `.app` 可装

实现按模块开 PR；合并不擅自进行，等用户/主控确认。

---

# Pulse 二期技术设计（首包）

> 一期正文不改写。一期写明「不做菜单栏 / 其它资源 Tab」——**本文只覆盖这两项**：菜单栏一瞥、CPU Tab。磁盘 / 网络 / GPU 深页、自动判泄漏、Electron、App Store 沙盒、TCC 全盘仍不做。

**已锁定**：同进程菜单栏（无 Helper / XPC）；复用 `MemorySampler` 快照，不第二路 Mach 轮询；CPU 列表用现有 `ProcessRow.cpuPercent`（两帧差值）。压力 UI 仍只暴露 `normal | elevated`。菜单栏交互 **A**：栏上只画压力色点，不写压力文案、不写已用内存。分发仍走 `docs/RELEASE.md` 的 Developer ID + 公证直装。

来源：用户 + 产品锁定的二期首包；对照一期实现（`MemorySampler` Actor → `MemoryDashboardVM` → Views；`ResourceTab` 仅内存可点；窗体后台现停采）。

## 范围（相对一期）

| 项 | 一期 | 二期首包 |
| --- | --- | --- |
| 菜单栏 | 明确不做 | 做：交互 A，栏上仅压力色点；点击回主窗内存页 |
| CPU Tab | 灰置不可点 | 做：解灰；系统 CPU（便宜才采）+ 进程按 cpu% 降序 |
| 磁盘 / 网络 / GPU Tab | 灰置 | **仍灰置** |
| 自动判泄漏 / 增长斜率 | 不做 | **仍不做** |
| Helper / XPC / 登录项 | 无 | **仍无**（除非实现时撞上硬墙，见菜单栏取舍） |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |

一期验收与公证路径不因本文重开。实现等本设计合并 + 研发排期后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与主窗共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

- `MenuBarExtra`（或同进程 `NSStatusItem`）←观察→ `MemoryDashboardVM`
- `SwiftUI Views`（内存页 / CPU 页）←观察→ 同一 VM
- VM ←订阅快照→ `MemorySampler`（同一 Actor）
- Sampler 同一 `sample()` tick：既有 `host_statistics64` / `vm_statistics64` + `ProcessEnumerator`；系统 CPU 若采，也在这一 tick 内用 `host_statistics(HOST_CPU_LOAD_INFO)` 或等价 `processor_info`
- Views → `ProcessActions` → `NSRunningApplication`（按 pid）——退出链路不新开

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids`。
- 菜单栏不是采样源，只绑 `snapshot.pressure` 画色点。
- 关主窗可留菜单栏；退出 App（⌘Q）卸菜单栏项。右键「退出 Pulse」可选，不替代 ⌘Q。
- 自身占用仍优先于刷新华丽度。

### 建议模块 PR 顺序

1. **采样 / 模型增量（若有）**：`SampledFrame` 可带系统 CPU（可空）；VM 在主窗后台改为降频续采（菜单栏与 CPU 页共用）。能复用现字段则本步可空。
2. **菜单栏**：进程内 `MenuBarExtra` + 点击打开 / 聚焦主窗内存页。
3. **CPU Tab UI**：`ResourceTab.cpu` 解灰并切换；默认 cpu% 排序；总览大数；侧栏与退出复用。

不要把菜单栏与 CPU Tab 塞进同一个功能 PR。合并不擅自写代码。

## 菜单栏

结论：进程内状态项，栏上**只画压力色点**（交互 A），点击回内存页。不做常驻守护、不做权限墙。

### 进程模型（不拆 Helper）

优先 SwiftUI `MenuBarExtra`（部署目标 14+ 已具备），与 `WindowGroup` 同属 `PulseApp`，注入同一 `@StateObject` VM。

不引入 Helper / XPC / Login Item / `LSUIElement`。首包不要求「退出 App 后仍占菜单栏」；退出即卸项，系统回收同进程 `NSStatusItem`。特权分离、沙盒逃逸也不适用（本 App 非沙盒、无特权操作）。

若实现时 `MenuBarExtra` 在关掉最后一个窗口后无法保活或无法可靠回前台：退到**同进程** `NSStatusItem` + 保持 regular `activationPolicy`，仍不拆进程。不要为「实现方便」上 XPC。

| 方案 | 何时用 | 代价 |
| --- | --- | --- |
| `MenuBarExtra` 同进程 | 默认 | 与主窗共享 VM；关窗保活行为需实机确认 |
| `NSStatusItem` 同进程 | MenuBarExtra 关窗/聚焦不稳 | 多一点 AppKit，架构不变 |
| Helper + XPC | **首包不用** | 签名、生命周期、双采样风险；只有「退出后仍常驻」才值得，而首包明确不要 |

### 展示与点击（交互 A，产品已锁）

栏上**只画一颗状态色点**，映射一期两档压力。**不要**在栏上写压力文案（「正常 / 偏高」）、**不要**写已用内存或其它短度量。细节进主窗。

| 快照 | 色点 | 说明 |
| --- | --- | --- |
| `pressure == .normal` | 冷静绿 | 余量充足；不是「安全」奖章 |
| `pressure == .elevated` | 冷静琥珀 | 余量紧张；**不**升第三档恐吓红，不写「危险」 |
| 采样失败 / 尚无快照 | 灰点 | tooltip 可写「采样中」或「暂时读不到压力」；**不装 0、不假装正常** |

- 点击色点：打开或聚焦主窗，并落到**内存页**（不是 CPU 页）。实现可用 `openWindow` / `NSApp.activate` + 既有 `WindowGroup("Pulse")`；VM 需有可写的当前 Tab（内存为默认）。
- 右键「退出 Pulse」可选，与 ⌘Q 同等卸项；不做菜单栏内退出任意其它进程。
- 不做：栏上压力文字、栏上已用内存、独立设置窗、登录项勾选、假「需要完全磁盘访问」墙、第三档红色危险态。

### 采样

一期 `MemoryDashboardVM` 仅在 `scenePhase == .active` 时 `tick()`，后台只 sleep——菜单栏会无数据。二期改：

- **仍只有一个** `MemorySampler.sample()` 循环。
- 主窗前台：保持 ~1.5s。
- 主窗在后台或已关、进程因菜单栏仍在：继续采，频率可相同或略降（约 2–3s）。菜单栏刷新不得快过 Sampler。
- 失败态与一期相同：不假装 0。无快照或采样失败时栏上灰点 + tooltip，不写假用量、不把灰点画成绿。

### 权限与生命周期

- 不申请 TCC 全盘；`Pulse.entitlements` 保持空 dict；不新开 Hardened Runtime 例外。
- 退出 App → 菜单栏项消失。不在 UI 上暗示「没授权所以看不到」。
- 不改 `docs/RELEASE.md` / 公证脚本；菜单栏不改变分发面。

## CPU Tab

结论：解灰现有 CPU 占位，用已经在采的进程 cpu%；系统 CPU 只在便宜时顺手带上。不新开枚举通道。

### UI

- `ResourceTab` 已有 `cpu / disk / network / gpu`，`isEnabled` 现仅 `.memory`，且 `ResourceTabs` `allowsHitTesting(false)`。二期：CPU 可点、可切换；其余仍灰置、不可点。
- 冷启动仍默认内存页（一期验收不回退）。
- 信息架构复用：总览卡片 + 进程表 + 侧栏。CPU 页默认排序改为 cpu% 降序；内存页仍内存降序。过滤、空态、选中行沿用 VM。

### 数据

| 能力 | 来源 | 说明 |
| --- | --- | --- |
| 进程 cpu% | 现有 `ProcessRow.cpuPercent` | `MemorySampler` 已对 `CPUTick` 做两帧 wall-clock 差值；第一帧 `nil` → UI「—」 |
| 默认排序 | `ProcessRow.cpuSortKey` | 已把缺失值沉底（`-1`），**不装 0%** |
| 进程枚举 | 现有 `ProcessEnumerator` | `proc_listpids` / `proc_pidinfo`；不新开通道 |
| 系统 CPU | `host_statistics(HOST_CPU_LOAD_INFO)` 优先 | 与内存同一 tick；两帧 `cpu_ticks` 差 → (user+system+nice)/total；第一帧「—」 |
| 逐核 | `host_processor_info` | 首包不承诺。同一调用几乎零成本且总览放得下再考虑；不做 GPU 式深页 |

`HOST_CPU_LOAD_INFO` 是一次便宜的 host 调用，建议放进现有 Actor 的 `sample()`，结果挂到 `SampledFrame`（可空）。不要为系统 CPU 再开定时器。

周期与精度（与内存同构，不另开采样器）：

- 前台周期与内存相同，约 1.5s；后台可随菜单栏略降（约 2–3s）。
- 进程 cpu% 与系统 CPU 都是**两帧 wall-clock 差值**；第一帧 `cpuPercent == nil`，UI 必须「—」，不装 0。
- 不宣称与活动监视器百分比逐点一致（枚举窗口、tick 来源、聚合口径都可能不同）。侧栏 CPU 曲线与列表同一套差值。

侧栏：继续 `ProcessDetail` 的内存主曲线 + CPU 辅曲线；切进程仍清空重采。退出 / 强制退出仍 `ProcessActions.terminate` → `forceTerminate` + 系统 `NSAlert`。

明确不做（相对本 Tab）：功耗小格、GPU / 磁盘 / 网络侧栏、自动高 CPU 告警、逐核深挖页。

## 风险

| 风险 | 应对 |
| --- | --- |
| 菜单栏 + 主窗双订阅同一 `@Published` | 快照不可变、主线程只读；后台略降频；禁止第二套 VM / 第二路 Mach 轮询 |
| 第一帧 CPU「—」 | 已有 `Double?` 与 `ByteFormat.cpu`；列表与系统大数都保持「—」，验收视为合法 |
| App Nap / 窗体后台停采 | 二期改为后台降频续采。若菜单栏长时间冻住，再评估短生命周期 `ProcessInfo` activity；不做常驻防休眠 |
| 关窗 vs ⌘Q | 关窗留项、退出卸项；右键退出可选。`MenuBarExtra` 不稳则同进程 `NSStatusItem`，不拆 Helper |
| 系统 CPU API / tick 回绕 | 失败或回绕当 `nil`，不写 0；不要用第一帧当 100% |
| 自身占用 | 前台 1.5s 不变；后台只降频不加倍采样；列表继续虚拟化（一期已有） |

## 验收（二期首包）

菜单栏：

- [ ] 栏上只有压力色点：正常绿 / 偏高琥珀；失败或无快照灰点 + tooltip；无压力文字、无已用内存串
- [ ] 不出现第三档恐吓红或「危险」文案
- [ ] 点击打开或聚焦主窗，并落在内存页
- [ ] 退出 App 后状态项消失（右键退出可选）
- [ ] 无第二路 Mach 轮询；无 Helper/XPC；无新 entitlements；UI 无假 TCC 墙

CPU Tab：

- [ ] CPU Tab 可点；磁盘 / 网络 / GPU 仍灰置
- [ ] 冷启动仍默认内存页
- [ ] 进程表默认按 cpu% 降序；第一帧「—」合法，不装 0；不宣称与活动监视器逐点一致
- [ ] 系统 CPU 与内存同一 tick；有数或「—」（未采 / 第一帧均可「—」）
- [ ] 侧栏内存主 + CPU 辅；`terminate` → `forceTerminate` 与一期相同

共性：

- [ ] 文案无恐吓措辞；压力仍两档
- [ ] 前台占用克制；后台菜单栏可略慢，不可另起采样器
- [ ] 不改公证脚本与 entitlements

## 工期

小：按「采样增量 → 菜单栏 → CPU Tab」拆三个工程 PR，天级，不是周级。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认后再动 Swift、采样实现、entitlements 与脚本。

---

# Pulse 三期技术设计（首包）

> 一期、二期正文不改写。一期写明「不做增长斜率/判泄漏」、二期写明「自动判泄漏 / 增长斜率仍不做」——**本文只覆盖内存页详情侧栏的增长软信号**，不是泄漏判定。不做列表角标、不做全表扫描、不做菜单栏告警。磁盘 / 网络 / GPU 深页、自动杀进程、常驻通知、菜单栏弹出条 B、Electron、App Store 沙盒、TCC 全盘、第三档恐吓红仍不做。

**已锁定**：仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。增长信号是对**已选进程** `ProcessDetail.memorySeries` 的纯函数（VM 或小 domain helper），不第二路 Mach 轮询、不新 entitlements。文案三态：上涨 / 样本不足 / 静默（无槽位）。永不写「就是泄漏」。

来源：用户 + 产品锁定的三期首包；对照现实现（Sampler 已为选中 pid 维护约 90 点 memory ring，切进程清空；侧栏已绑 `detail.memorySeries`）。

## 范围（相对一二期）

| 项 | 一二期 | 三期首包 |
| --- | --- | --- |
| 增长斜率 / 判泄漏 | 明确不做 | **仍不做泄漏判定**。只做详情侧栏软信号：窗口够且双条件成立时写「近几分钟持续上涨」 |
| 信号入口 | — | **只详情侧栏**。无列表角标、无全表扫描、无菜单栏告警 |
| 数据源 | 选中 pid 的 `memorySeries` ring（现约 90 点、前台约 1.5s） | **只复用这条 ring**。不扩成全表时序、不新开采样通道 |
| 文案 | 压力两档、无恐吓 | 上涨 / 样本不足 / 静默；禁止「泄漏」「危险」 |
| 菜单栏 | 交互 A：栏上仅压力色点 | **不变**。不做弹出条 B、不因增长改色点 |
| CPU / 磁盘 / 网络 / GPU | CPU 已解灰；其余灰置 | **仍不深挖**磁盘 / 网络 / GPU |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 | 不做 | **仍不做** |
| 压力第三档恐吓红 | 不做 | **仍不做** |

一二期验收、菜单栏交互 A、CPU Tab、公证路径不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏、内存页、CPU 页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

- `SwiftUI Views`（详情侧栏）←观察→ 同一 `MemoryDashboardVM`
- VM ←订阅快照→ `MemorySampler`（同一 Actor）
- Sampler 同一 `sample()` tick：既有 host 统计 + `ProcessEnumerator`；选中 pid 继续写入 `selectedMemorySeries`（现 `seriesLimit = 90`）
- **增长信号不进 Sampler**。对 `ProcessDetail.memorySeries`（或 VM 刚收到的同一数组）做纯函数：`[ChartSample] → MemoryGrowthSignal`
- 纯函数可放 VM 派生，或小 domain helper（建议 `Models/`，便于 `SamplingCore` / `swift test` 覆盖，与 `MenuBarStatus`、`CPUPage` 同构）

约束：

- 不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询。
- 不把全表 `ProcessRow.memoryBytes` 攒成多进程 ring。只有用户点开的那条进程有时序。
- 不改 `Pulse.entitlements`、不改公证脚本、不改菜单栏色点映射。
- 自身占用仍优先：信号是 O(窗口长度) 的纯计算，跟在已有 detail 帧后面，不加倍采样。

### 建议模块 PR 顺序

1. **模型 / helper + 单测**：`MemoryGrowthSignal`（或等价枚举）+ 对 `[ChartSample]` 的纯函数；覆盖上涨 / 样本不足 / 无信号、切序列清空、抖动不应上涨。能 `swift test`，不编 App。
2. **详情侧栏接线**：内存页详情读该信号；三态文案；列表、菜单栏、CPU Tab 零改动。

不要把算法单测和侧栏 UI 塞进同一个功能 PR。合并不擅自写代码。

## Ring / 窗口

结论：复用现成选中进程内存曲线，不改采样器契约。窗口不够先说「暂不判断」，够了才看双条件；切进程必须立刻丢掉旧信号。

### 复用现有 `memorySeries`

一期已锁「选中后对 pid 重采写入 ring；切进程清空」。现实现：

- `MemorySampler.setSelectedPid`：pid 变则 `selectedMemorySeries.removeAll`
- `detailFrame`：命中选中行则 `append(Double(row.memoryBytes), …)`，`seriesLimit = 90`
- `ProcessDetail.memorySeries` 随 `SampledFrame.detail` 交给 VM；`selectedPid` 变化时 VM 先把 `detail = nil`

三期**只读**这条序列。不要为增长信号另开 ring、不要拉长全表采样、不要把系统 `UsageHistory`（总用量）误当成进程曲线。

现 ring 约 60–120 点、前台约 1.5s/点：90 点 ≈ 2.25 分钟，落在产品窗口（约 2–3 分钟、约 80–120 点）内。首包默认用**整段已有 series**（或末尾约 80–120 点，以不超过现 limit 为准）。不要为了「更像泄漏检测」把 Sampler limit 扩到数十分钟。

后台菜单栏续采约 2–3s 时，同一 90 点覆盖更长墙钟。判定仍看**点数 + 净增 + 单调比例**，不另开「后台专用」阈值。

### 前 N 点：样本不足

窗口未满（建议与产品对齐：少于约 80 点、或墙钟不足约 2 分钟——实现时二选一写死，单测钉住）→ 信号 = **样本不足**，文案「样本不足，暂不判断」。

- 刚点开进程、或进程稍后才出现在枚举里：series 从 0 涨，必然先走不足。
- 不足是**可见态**，不是空槽。用户能区分「还在攒窗口」和「窗口够了但没有上涨」。
- 不要在不足时提前给上涨，也不要把不足画成进度条或「检测中」。

### 切进程

`selectedPid` 一变：Sampler 清 ring、VM 清 `detail`，派生信号必须回到「无选中 / 不足」——**禁止**把上一进程的「持续上涨」带到下一进程的第一帧。

进程从列表消失（退出成功或枚举里没了）：现逻辑已 `selectedPid = nil`、`detail = nil`，信号随侧栏一起卸掉，不残留文案。

## 算法草图（非绑定实现细节）

产品锁的是**双条件**：窗口够之后，既要有净增加，又要「多半时间在涨」。下面是便于单测的草图，阈值实现时再钉，**不要**把本节数字读成验收合同。

建议输入：按时间排序的 `memorySeries`（`ChartSample.value` 已是字节）。输出三态，例如：

```text
enum MemoryGrowthSignal {
  case insufficient   // 样本不足，暂不判断
  case rising         // 近几分钟持续上涨
  case none           // 静默，UI 不占位
}
```

建议步骤：

1. **最少点数**：`count < minSamples`（约 80，或与现 ring 下限对齐）→ `.insufficient`。不要用「看起来在涨的 10 个点」抢判。
2. **净增量**：`last.value - first.value`（或窗口首末）须 `> deltaThreshold`（字节）。阈值应滤掉 megabyte 级抖动，又不要大到只有泄漏级才触发。实现时用常量 + 单测夹住，不写进用户文案。
3. **单调比例**：相邻正步（`Δ > 0`）占有效步数的比例 ≥ `riseFloor`（「多半在涨」）。允许少量回落，避免锯齿被当成上涨。
4. **可选滞回**：已是 `.rising` 时，可用略松的净增 / 比例避免文案闪烁；从静默进入上涨仍用严阈值。首包可无滞回，闪烁再加。
5. 双条件缺一 → `.none`（不是不足）。窗口够但净增不够、或净增够但正步比例低，都静默。

明确**不是**：回归斜率显著性、与基线进程对比、跨进程排名、把 Compressed / Cached 主机计数算进该 pid。

### 误报与已锁定的收敛

| 坑 | 为何像上涨 | 产品已锁的收敛（首包就遵守） |
| --- | --- | --- |
| 启动缓存填满 | App 前一两分钟 RSS 爬升 | 先攒满约 2–3 分钟窗口；不足只说「暂不判断」，不说上涨 |
| GC / 压缩回弹 | 锯齿、先掉再抬 | 必须「净增 **且** 多半单调」；只有末点更高不够 |
| 短窗口噪声 | 两三个 1.5s 点的偶然爬升 | 最少点数 / 最短墙钟；禁止用前 N 点抢判 |
| 切进程脏状态 | 上一进程的上涨文案残留 | pid 变化立刻清 ring + 清信号 |
| 把软信号说成泄漏 | 文案或 UI 暗示「就是泄漏」 | 只允许「近几分钟持续上涨」；禁止泄漏 / 危险；静默不占位 |

首包接受：启动期长爬、编译器/浏览器真涨，窗口够且双条件成立时可以出现上涨文案——这是软信号，不是误报清单要清零的对象。不要为压这类场景再开全表扫描或加长采样。

## UI 绑定

结论：只改内存页详情侧栏。列表、菜单栏、CPU Tab 布局与文案不变。

三态（产品已锁语气）：

| 信号 | 侧栏 | 说明 |
| --- | --- | --- |
| `.rising` | 冷静短句「近几分钟持续上涨」 | 可挨着内存曲线标题或内存大数 caption；不改压力色、不用恐吓红 |
| `.insufficient` | 「样本不足，暂不判断」 | 窗口未满时的唯一占位；不写「检测泄漏中」 |
| `.none` 或无选中 | **不渲染槽位** | 没有空 `Text`、没有「暂无异常」占位。曲线「正在采集内存曲线」仍只服务图表本身 |

- 入口：用户在**内存页**点开进程详情，想知道「它是不是还在爬」。CPU 页若复用同一侧栏，首包**不要**在 CPU 页再解释一套；无信号则两边都静默。
- 不做：进程表 badge / 色点 / 排序加权；菜单栏色点随增长变色；菜单栏弹出条 B；持久通知；自动 `terminate`。
- 压力仍是 `normal | elevated` 两档。增长文案不升第三档、不写「危险」。

## 风险

| 风险 | 应对 |
| --- | --- |
| 抖动当上涨（GC、压缩、短脉冲） | 双条件 + 最短窗口；单测钉「末点高但正步少 → `.none`」 |
| 窗口过短抢判 | 不足态可见；少于 minSamples 不得 `.rising` |
| 切进程串文案 | 复用现有清 ring；派生信号随 `detail == nil` 卸掉；单测换序列必须回不足 / none |
| 被读成「就是泄漏」 | 文案白名单；验收搜「泄漏」「危险」；静默不占位，避免假「已排除泄漏」 |
| 实现时忍不住扫全表 / 改菜单栏 | 首包范围表写死详情 only；列表与菜单栏 PR 不在建议顺序里 |
| 后台 3s 续采让墙钟变长 | 用点数（或点数 + 墙钟下限）判定，不按「必须恰好 120s」卡死 |

## 验收（三期首包）

产品 Must：

- [ ] 只在内存页进程详情侧栏出现增长文案；进程表无角标、无全表扫描、菜单栏无增长告警 / 无弹出条 B
- [ ] 窗口够且净增 + 多半单调：冷静文案「近几分钟持续上涨」
- [ ] 窗口不够：「样本不足，暂不判断」
- [ ] 无信号：不渲染占位槽
- [ ] 数据只来自选中进程 `memorySeries`（现有约 60–120 点 / 约 1.5s ring）；不新开 Sampler、不新 entitlements
- [ ] 切进程后旧信号立即消失，新进程从不足或静默重来
- [ ] 永不写「就是泄漏」；无「泄漏」「危险」

明确不做（本包出现即不合格）：

- [ ] 无自动杀、无常驻通知
- [ ] 磁盘 / 网络 / GPU 深页仍不做
- [ ] 无 Helper / XPC、无 TCC 全盘、无新 entitlements
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 压力无第三档恐吓红；菜单栏仍是交互 A 色点

共性：

- [ ] 一二期验收不回退（内存页、CPU Tab、菜单栏色点、退出链路）
- [ ] 纯函数有 `swift test`；不编 App 也能验上涨 / 不足 / 无信号
- [ ] 不改公证脚本与 entitlements

## 工期

小：按「helper + 单测 → 详情接线」拆两个工程 PR，天级，不是周级。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。
