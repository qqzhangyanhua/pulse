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

---

# Pulse 四期技术设计（首包：网络 Tab）

> 一期、二期、三期正文不改写。一期写明「不做磁盘/网络/GPU」、二期写明「磁盘 / 网络 / GPU 仍灰置」、三期写明「仍不深挖磁盘 / 网络 / GPU」——**本文只覆盖网络 Tab 首包**：总览 → 进程表 → 详情 → 退出，与内存 / CPU 同构。磁盘 Tab、GPU、菜单栏弹出条 B、列表增长角标、泄漏恐吓文案、假权限墙、Helper / XPC、Electron 仍不做。

**已锁定**：仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。系统级网络入/出速率走现有「便宜 host 计数 + 两帧差值」风格，挂在同一 `sample()` tick。进程级网络字节当前采样器**没有**；首包不编造数字，表列标「暂不可用」，默认按其它已有指标排序。不新开 entitlements、不拆 Helper / XPC、不自动杀。文案冷静，无恐吓。

来源：用户 + 产品锁定的四期 Must；对照现实现（`ResourceTab.network` 已占位但 `DashboardPage.network.isSelectable == false`；`ProcessEnumerator` 只采 rss / 线程 / CPU 时间；`SampledFrame` 只有 `systemCpuPercent`，无网络字段）。

## 范围（相对一二三期）

| 项 | 一二三期 | 四期首包 |
| --- | --- | --- |
| 网络 Tab | 灰置不可点 | **做**：解灰；信息架构与内存 / CPU 同构 |
| 系统网络入/出 | 不采 | **做**：host 接口累计字节的两帧差值 → 入/出速率；第一帧「—」 |
| 进程级网络 | `ProcessRow` 无此字段 | **首包不编造**。列上写「暂不可用」；表按其它已有指标排序 |
| 磁盘 Tab / GPU | 灰置 | **仍灰置** |
| 菜单栏 | 交互 A：栏上仅压力色点 | **不变**。不做弹出条 B；点击仍回内存页 |
| 列表增长角标 | 三期已锁「只详情、无列表角标」 | **仍不做**（延期） |
| 泄漏 / 恐吓文案 | 禁止 | **仍禁止**。网络页也不写「泄漏」「危险」「超速」「被盗流量」 |
| 假权限墙 | 禁止 | **仍禁止**。读失败只说「暂时读不到」，不暗示缺 TCC |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请**。本包不改 `Pulse.entitlements`、不加沙盒例外 |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 | 不做 | **仍不做**。退出链路仍是用户点的 `terminate` → `forceTerminate` |

一二三期验收、菜单栏交互 A、CPU Tab、增长软信号（仅内存页详情）、公证路径不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏、内存页、CPU 页、网络页共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

- `SwiftUI Views`（网络总览 + 既有 Tab 壳 / 进程表 / 侧栏）←观察→ 同一 `MemoryDashboardVM`
- VM ←订阅快照→ `MemorySampler`（同一 Actor）
- Sampler 同一 `sample()` tick：既有 `host_statistics64` / `HOST_CPU_LOAD_INFO` + `ProcessEnumerator`；系统网络若采，也在这一 tick 内用 `getifaddrs` 读 `AF_LINK` 的 `ifi_ibytes` / `ifi_obytes`
- Views → `ProcessActions` → `NSRunningApplication`（按 pid）——退出链路不新开

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids`。
- 网络页不是第二套诊断器：复用 `ResourceTabs`、`ProcessTablePane` / `ProcessLine`、`ProcessDetailSidebar`、过滤与退出。
- 菜单栏不是网络采样源，仍只绑 `snapshot.pressure` 画色点。
- 自身占用仍优先：接口计数是一次便宜的 libc 遍历，不要为网络另开定时器或 IOKit / Network.framework 会话。

### 建议模块 PR 顺序

1. **采样 / 模型 + 单测**：`HostNetworkReader`（或等价）+ 两帧差值纯函数；`SampledFrame` 可带系统入/出速率（可空）；覆盖第一帧 `nil`、计数回绕 / 读失败 → `nil`、loopback 不计入。能 `swift test`，不编 App。
2. **网络 Tab UI 同构接线**：`DashboardPage.network` 解灰；总览大数 + 曲线；进程表复用现行，网络列「暂不可用」；默认按其它已有指标排序；侧栏与退出复用。

不要把采样单测和 Tab UI 塞进同一个功能 PR。合并不擅自写代码。

## 现采样器里有什么（读仓库后的结论）

实现前已对照 `Pulse/Sampling/` 与 `ProcessRow`。首包必须按「已有 / 没有」落笔，**禁止**把 Mach IPC 或磁盘 I/O 改贴成网络。

| 现字段 / 调用 | 文件 | 是不是网络 |
| --- | --- | --- |
| `host_statistics64` / `vm_statistics64` | `HostMemoryReader` | 否，主机内存 |
| `host_statistics(HOST_CPU_LOAD_INFO)` | `HostCPUReader` | 否，主机 CPU |
| `proc_listpids` + `proc_pidinfo(PROC_PIDTASKINFO=4)` | `ProcessEnumerator` | 否。`RawProcessSample` 只有 rss、线程、user/system 时间 |
| `pti_messages_sent` / `pti_messages_received` | `ProcTaskInfo` 已声明、**未写入** `ProcessRow` | **不是网络**。这是 Mach IPC 消息数。禁止当入/出字节展示 |
| `ProcessRow` | `MemoryModels` | pid、name、icon 路径、`cpuPercent`、`memoryBytes`、`threadCount`。**无**网络字段 |
| `SampledFrame.systemCpuPercent` | 同一 tick 的主机 CPU | 网络应对齐这个可空挂载方式，另开字段，不要塞进 CPU |

公开 `rusage_info_v4`–`v6`（`proc_pid_rusage`）有磁盘读写字节，**没有**稳定的公开 per-process 网络字节。活动监视器进程网络列走的是 Network Statistics 私有栈，通常要额外 entitlement 或 Helper。本包锁定两者都不加。

因此四期第一刀：

- **做**系统级入/出速率（host 接口计数，可靠、无新权限）。
- **不做**进程级字节。表列写「暂不可用」，或根本不把假 `UInt64` 挂到 `ProcessRow` 上。
- 缺数时「—」或「暂不可用」，**不装 0 B/s**。

## 系统网络采样（第一刀，已选 API）

结论：用 **`getifaddrs()` + `AF_LINK` 的 `struct if_data`（`ifi_ibytes` / `ifi_obytes`）**。与现有 CPU 路径同构：一次便宜的 Darwin 计数、两帧墙钟差值、挂在同一 `sample()`、第一帧 `nil`。

不选 `host_statistics*`：Mach host 统计没有接口字节 flavor，仓库里的 `HostMemoryReader` / `HostCPUReader` 也覆盖不了网络。不选 Network.framework / IOKit / `NWPathMonitor`：那些给连通性，不给字节速率，还会多会话、多占用。不选 `sysctl(net.inet.ip.stats)`：只在 IP 层，漏接口、口径更不像总览。

`sysctl(NET_RT_IFLIST2)` / `if_data64` 可作为「`getifaddrs` 在实机上宽度不够」时的同族备选，仍是 BSD 接口计数、仍无新 entitlement。首包默认 `getifaddrs`：macOS 14+ 64-bit 上 `ifi_ibytes` 宽度足够，且与现有 `import Darwin` 风格一致。

### 计数 → 速率

建议形状（实现名可改，语义钉住）：

```text
struct HostNetworkCounters {
  inboundBytes: UInt64   // 非回环、UP 接口 ifi_ibytes 之和
  outboundBytes: UInt64
}

struct HostNetworkRates {
  inboundBytesPerSecond: Double?
  outboundBytesPerSecond: Double?
}
```

规则与 `SystemCPULoad.advance` 对齐：

- 第一帧：记下 counters，速率 `nil`，UI「—」。
- 其后：`Δbytes / Δseconds`。墙钟 ≤ 0、当前计数 < 上一帧（接口重置 / 回绕）、`getifaddrs` 失败 → 该帧 `nil`，**不写 0**。
- 失败读保留上一帧 baseline（与 CPU `advance` 相同），不要用 0 覆盖。
- 只累加 `AF_LINK`、`IFF_UP`、非 `IFF_LOOPBACK`。`lo0` 不计。首包不拆 Wi-Fi / 有线 / utun 分项（避免做成磁盘式深页）。
- 接口集合变化（新插网线、VPN 起来）：按名字做 per-iface 差值再加总更稳；新接口第一帧跳过。若实现成「先加总再差值」，须单测钉住「集合变化不得喷出天文数字」。
- 不宣称与活动监视器 Network 总览逐点一致（接口过滤、VPN、单位都可能不同）。

周期：前台约 1.5s，后台随菜单栏约 2–3s。不要为网络另开更快的 tick。

视图侧可做 `SystemNetworkHistory` ring（对齐 `SystemCPUHistory`）：只在速率非 `nil` 时入环，缺数跳过，永不存 0 冒充空闲。

## 进程表：首包回退（不编造）

产品允许两句同时成立：总览看系统总量；进程网络要么按其它已有指标排序，要么格子写「暂不可用」。

首包锁：

1. **不**给 `ProcessRow` 填假的网络字节。不要用 `pti_messages_*`、不要用磁盘 `ri_diskio_*`、不要用 0 当「没流量」。
2. 网络页可多一列「网络」，**每行**「暂不可用」。也可以首包不加列、只改默认排序——若加列，文案必须是「暂不可用」，不能是「—」装成「已采但是 0」。
3. 默认排序：**cpu% 降序**（现成 `cpuSortKey`，缺值沉底）。这是「其它已有指标」里最接近速率的一列；用户仍可点内存 / 名称 / 线程。`ProcessTableSort.defaultSort(for:)` 今天把 `.network` 并进内存降序，接线时改掉。
4. 过滤、选中、空态、虚拟化列表沿用；不要为网络页新开枚举通道。

以后若公开 API 在**不**加 entitlement / Helper 的前提下能稳定给出 per-process 字节，另开设计再补列。本包不预埋假字段、不申请权限「以备后用」。

## 网络 Tab UI

结论：解灰现有网络占位，壳子跟 CPU Tab（二期）同一套。冷启动仍默认内存页。

### 导航与壳

现成锚点（接线时改这些，不要另起一套窗口）：

- `ResourceTab.network` / `DashboardPage.network` 已在枚举里；`isSelectable` 现为 `false`，`ResourceTabs` 灰置不可点。四期：网络可点；**磁盘 / GPU 仍灰置**。
- `MemoryDashboardView`：`selectedPage == .cpu` 走 `CPUOverviewSection`，否则内存总览。四期加网络总览分支（建议 `NetworkOverviewSection`，对齐 `CPUOverviewSection` 的 150pt 卡片：左侧大数、右侧 sparkline）。
- `ProcessTablePane`：cpu / 非 cpu 两套空态。网络页复用同一 `processList` + `ProcessLine`，换页级文案，不要第三套表格控件。
- `ContentView.onAppear`：不可选页会打回内存。网络可点后不再被打回。
- `MemoryDashboardVM.selectPage` 注释仍写「Memory and CPU only」——接线时改，菜单栏主点仍 `focusMemoryPage()`。
- 三期 `memoryGrowthSlot` 已按页门控：网络页**不要**解释增长软信号，无信号则静默（现逻辑已是这样）。

### 总览

| 能力 | 来源 | 说明 |
| --- | --- | --- |
| 接收 / 发送大数 | `SampledFrame` 上的系统入/出速率 | 文案用「接收」「发送」，不用「下载狂飙」。`nil` →「—」 |
| 总览曲线 | 视图侧 ring | 可画合计吞吐或只画接收；缺数不入环。少于 2 点：「曲线采集中」 |
| 失败 | 与 CPU 同构 | 「暂时读不到网络数据」+「重新采样」；**不**写「需要完全磁盘访问」 |

不做：按接口拆条、连接列表、端口扫描、实时包捕获、把内存压力色套到网络上（网络页不发明第三档「拥堵红」）。

### 侧栏与退出

侧栏继续 `ProcessDetail`：内存主曲线 + CPU 辅曲线；切进程仍清空重采。网络页**不**画假的进程网络曲线。退出 / 强制退出仍 `ProcessActions.terminate` → `forceTerminate` + 系统 `NSAlert`。无自动杀、无「检测到异常流量后结束进程」。

明确不做（相对本 Tab）：磁盘 / GPU 侧栏小格、菜单栏弹出条 B、列表增长角标、假 TCC 墙。

## 文案（冷静，白名单语气）

网络页语气对齐 CPU 页 `CPUPageCopy`，不沿用内存压力「余量紧张」——网络没有压力档。

建议（实现时可收进 `NetworkPageCopy`）：

| 场景 | 文案 |
| --- | --- |
| 采样中 | 正在采样… |
| 主机读失败 | 暂时读不到网络数据 / 这轮采样没有回来，点重新采样再试。 |
| 第一帧或缺速率 | — |
| 进程网络列 | 暂不可用 |
| 侧栏空态 | 选一个进程看详情（可与 CPU 共用） |
| 总览 caption | 接收 · … · 发送 · … |

禁止出现：泄漏、危险、超速、异常流量、被盗、中招、需要完全磁盘访问、未授权所以看不到、流量告警。失败态不暗示用户去开 TCC。

## 风险

| 风险 | 应对 |
| --- | --- |
| 把 Mach 消息 / 磁盘 I/O 当成网络 | 上文对照表写死；单测与验收搜 `pti_messages`、`diskio` 不得进网络列 |
| 第一帧或失败装 0 B/s | 可空速率 +「—」；与 CPU 同一条「不装 0」纪律 |
| 接口增减导致吞吐尖刺 | 优先 per-iface 差值；集合变化单测 |
| 为了进程网络去加 entitlement / Helper | 首包范围表写死不加；缺列用「暂不可用」 |
| 做成磁盘/GPU 深页或菜单栏 B | 磁盘 / GPU 仍灰置；菜单栏仍交互 A |
| 恐吓文案 | 白名单；验收搜「泄漏」「危险」「超速」 |
| 自身占用 | 同一 tick、同一降频；禁止第二路轮询 |

## 验收（四期首包）

产品 Must：

- [ ] 网络 Tab 可点；信息架构为总览 → 进程表 → 详情 → 退出，与内存 / CPU 同构
- [ ] 总览展示系统接收 / 发送速率（`getifaddrs` 接口计数两帧差）；第一帧或失败为「—」，不装 0
- [ ] 进程网络无可靠来源时：列上「暂不可用」或等价明示，**不**编造字节；默认按其它已有指标（cpu% 降序）
- [ ] 侧栏仍是内存主 + CPU 辅 + 既有退出链路；无自动杀
- [ ] 文案冷静：无「泄漏」「危险」「超速」及假权限墙

明确不做（本包出现即不合格）：

- [ ] 磁盘 Tab、GPU 仍灰置
- [ ] 无菜单栏弹出条 B；栏上仍只是压力色点；点击仍回内存页
- [ ] 无列表增长角标
- [ ] 无 Helper / XPC、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 不把 `pti_messages_*` 或磁盘 I/O 显示成网络

共性：

- [ ] 一二三期验收不回退（内存页、CPU Tab、菜单栏色点、增长软信号仅内存详情、退出链路）
- [ ] 冷启动仍默认内存页
- [ ] 系统网络差值有 `swift test`；不编 App 也能验第一帧 / 失败 / 回绕
- [ ] 不改公证脚本与 entitlements

## 工期

小：按「采样 / 模型 + 单测 → 网络 Tab UI 同构接线」拆两个工程 PR。保持同构、不加新 entitlement 时是天级，不是周级。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。

---

# Pulse 五期技术设计（首包：磁盘 Tab）

> 一期、二期、三期、四期正文不改写。一期写明「不做磁盘/网络/GPU」、二期写明「磁盘 / 网络 / GPU 仍灰置」、三期写明「仍不深挖磁盘 / 网络 / GPU」、四期写明「磁盘 Tab / GPU 仍灰置」——**本文只覆盖磁盘 Tab 首包**：总览 → 进程表 → 详情 → 退出，与内存 / CPU / 网络同构。GPU、菜单栏弹出条 B、列表增长角标、活动监视器级磁盘 IO 深挖、泄漏恐吓文案、假权限墙、Helper / XPC、Electron 仍不做。

**已锁定**：仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。系统级磁盘读/写粗速率走 IOKit `IOBlockStorageDriver` 累计字节 + 同一 `sample()` tick 的两帧差值（第一帧 / 失败 / 回绕 → `nil` → UI「—」）。进程级读/写走公开 `proc_pid_rusage` 的 `ri_diskio_bytesread` / `ri_diskio_byteswritten`（同样两帧差）；读不到的格子写「—」，不编造。不新开 entitlements、不拆 Helper / XPC、不自动杀。文案冷静，无恐吓。卷容量 / 剩余 **本刀 Out**。

来源：用户 + 产品锁定的五期 Must；对照现实现（`ResourceTab.disk` / `DashboardPage.disk.isSelectable == false`；`SampledFrame` 已有 `systemCpuPercent` + `hostNetworkRates`，无磁盘字段；`ProcessEnumerator` 只采 rss / 线程 / CPU 时间；四期已写明 `rusage_info_v4`–`v6` 有磁盘字节、没有进程网络字节）。

## 范围（相对一二三四期）

| 项 | 一二三四期 | 五期首包 |
| --- | --- | --- |
| 磁盘 Tab | 灰置不可点 | **做**：解灰；信息架构与内存 / CPU / 网络同构 |
| 系统磁盘读/写 | 不采 | **做**：IOKit 块设备累计字节的两帧差值 → 读/写速率；第一帧「—」 |
| 进程级磁盘读/写 | `ProcessRow` 无此字段 | **做（有稳定公开 API）**：`proc_pid_rusage` 累计字节两帧差；缺数「—」 |
| 卷容量 / 剩余 | — | **本刀 Out**。不放进同构总览，避免第三度量 / 新 UX |
| GPU Tab | 灰置 | **仍灰置** |
| 菜单栏 | 交互 A：栏上仅压力色点 | **不变**。不做弹出条 B；点击仍回内存页 |
| 列表增长角标 | 三期已锁「只详情、无列表角标」 | **仍不做** |
| 泄漏 / 恐吓文案 | 禁止 | **仍禁止**。磁盘页也不写「泄漏」「危险」「磁盘将满」「被占满」 |
| 假权限墙 | 禁止 | **仍禁止**。读失败只说「暂时读不到」，不暗示缺 TCC |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请**。本包不改 `Pulse.entitlements`、不加沙盒例外、不加 IOKit user-client entitlement |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 | 不做 | **仍不做**。退出链路仍是用户点的 `terminate` → `forceTerminate` |
| 活动监视器级磁盘深挖 | 不做 | **仍不做**（ops / 延迟 / 队列 / 分卷条 / `fs_usage`） |

一二三四期验收、菜单栏交互 A、CPU / 网络 Tab、增长软信号（仅内存页详情）、公证路径不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏、内存页、CPU 页、网络页、磁盘页共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

- `SwiftUI Views`（磁盘总览 + 既有 Tab 壳 / 进程表 / 侧栏）←观察→ 同一 `MemoryDashboardVM`
- VM ←订阅快照→ `MemorySampler`（同一 Actor）
- Sampler 同一 `sample()` tick：既有 `host_statistics64` / `HOST_CPU_LOAD_INFO` / `getifaddrs` + `ProcessEnumerator`；系统磁盘若采，也在这一 tick 内读 IOKit `IOBlockStorageDriver` 的 `Statistics`；进程磁盘在**同一趟**枚举里加一次 `proc_pid_rusage`，不新开 `proc_listpids`
- Views → `ProcessActions` → `NSRunningApplication`（按 pid）——退出链路不新开

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids`。
- 磁盘页不是第二套诊断器：复用 `ResourceTabs`、`ProcessTablePane` / `ProcessLine`、`ProcessDetailSidebar`、过滤与退出。
- 菜单栏不是磁盘采样源，仍只绑 `snapshot.pressure` 画色点。
- 自身占用仍优先：IOKit 是一次匹配遍历 + 属性字典；`proc_pid_rusage` 是每 pid 一次便宜的 libproc 调用。不要为磁盘另开定时器、不要 `popen("iostat")` / `fs_usage`。
- 链接 `IOKit.framework`（系统框架）**不是**新 entitlement。只读 registry 属性，不开 user client。

### 建议模块 PR 顺序

1. **采样 / 模型 + 单测**：`HostDiskReader`（或等价）+ 两帧差值纯函数；`ProcessEnumerator` 顺手带 `ri_diskio_*`；`SampledFrame` 可带系统读/写速率（可空）与进程读/写速率（可空）；覆盖第一帧 `nil`、计数回绕 / 读失败 / `EPERM` → `nil`。能 `swift test`，不编 App。
2. **磁盘 Tab UI 同构接线**：`DashboardPage.disk` 解灰；总览大数 + 曲线；进程表加读取 / 写入列；默认按合计磁盘速率排序（缺值沉底）；侧栏与退出复用。

不要把采样单测和 Tab UI 塞进同一个功能 PR。合并不擅自写代码。

## 现采样器里有什么（读仓库后的结论）

实现前已对照 `Pulse/Sampling/` 与 `ProcessRow`。首包必须按「已有 / 没有」落笔，**禁止**把 Mach 页错误、网络字节或 VM pagein 改贴成磁盘。

| 现字段 / 调用 | 文件 | 是不是磁盘 IO |
| --- | --- | --- |
| `host_statistics64` / `vm_statistics64` | `HostMemoryReader` | **否**。`pageins` / `pageouts` / swap 是 VM pager，不是块设备读写。禁止当系统磁盘速率 |
| `host_statistics(HOST_CPU_LOAD_INFO)` | `HostCPUReader` | 否，主机 CPU |
| `getifaddrs` `ifi_ibytes` / `ifi_obytes` | `HostNetworkReader` | 否，主机网络。禁止当磁盘 |
| `proc_listpids` + `proc_pidinfo(PROC_PIDTASKINFO=4)` | `ProcessEnumerator` | **否**。`pti_pageins` / `pti_faults` 是 VM；`pti_messages_*` 是 Mach IPC。四期已禁止当网络，五期同样禁止当磁盘 |
| `proc_pid_rusage` | **现未调用** | **是**。公开 `ri_diskio_bytesread` / `ri_diskio_byteswritten`（`RUSAGE_INFO_V2` 起，V4–V6 / `CURRENT` 仍在） |
| `ProcessRow` | `MemoryModels` | pid、name、icon 路径、`cpuPercent`、`memoryBytes`、`threadCount`；`networkAvailability` 恒为 `.unavailable`。**无**磁盘字段 |
| `SampledFrame.hostNetworkRates` | 同一 tick 的主机网络 | 磁盘应对齐这个可空挂载方式，另开字段，不要塞进网络 |

四期已锁：公开 rusage 有磁盘字节、**没有**稳定的公开 per-process 网络字节。五期只启用磁盘那两个字段；网络列继续「暂不可用」，不要回头用 `ri_diskio_*` 填网络。

因此五期第一刀：

- **做**系统级读/写粗速率（IOKit 块设备计数，可靠、无新权限）。
- **做**进程级读/写粗速率（`proc_pid_rusage`，公开、无新权限）。部分 SIP / 系统进程会 `EPERM`——格子「—」，**不**因此申请 root Helper。
- 缺数时「—」，**不装 0 B/s**，也不改写成网络页那种整列「暂不可用」（网络是「没有 API」；磁盘是「有 API，这一格没差值」）。

## 系统磁盘采样（第一刀，已选 API）

结论：用 **IOKit `IOBlockStorageDriver` → `Statistics` 字典的 `Bytes (Read)` / `Bytes (Write)`**（头文件常量 `kIOBlockStorageDriverStatisticsBytesReadKey` / `…BytesWrittenKey`）。与现有网络路径同构：一次便宜的 Darwin 计数、两帧墙钟差值、挂在同一 `sample()`、第一帧 `nil`。

`IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), …)` + `IORegistryEntryCreateCFProperties`（或只取 `Statistics`）。macOS 14+ 用 `kIOMainPortDefault`，不要用已弃用的 `kIOMasterPortDefault`。

不选这些：

| 候选 | 为何不选 |
| --- | --- |
| `host_statistics64` 的 pageins / pageouts / swap | VM pager，不是块设备。跟把 `pti_messages_*` 当网络同一类不诚实 |
| `sysctl` / 自造 diskstats | Darwin 没有 Linux `/proc/diskstats` 等价物；`kern.disks` 不给字节 |
| `statfs` / `volumeAvailableCapacity` | 容量 / 剩余，不是速率；本刀 Out |
| DiskArbitration | 挂载描述，不给累计字节 |
| `iostat` / `fs_usage` 子进程 | 占用量、权限、解析脆弱；活动监视器级深挖，Out |
| Network.framework / `getifaddrs` | 网络，不是磁盘 |

Hardened Runtime + 空 entitlements：非沙盒 App 读 IOKit registry 属性不需要 `com.apple.security.iokit-user-client-class`，也不需要 TCC 全盘。只读、不 `IOServiceOpen`。不要「以防万一」预埋 entitlement。

`IOBlockStorageDriver` 在分区表之上：一个驱动 ≈ 一块整盘（`disk0`），不是每个 APFS 卷一条。首包对**每个驱动做差值再加总**（对齐网络 per-iface），新出现的驱动第一帧跳过，避免集合变化喷出天文数字。磁盘映像驱动可计入粗速率；**不要**做分卷条、按盘 picker、延迟 / ops / 队列——那是活动监视器级深挖。

不宣称与活动监视器 Disk 总览逐点一致（过滤、映像盘、单位都可能不同）。

### 计数 → 速率

建议形状（实现名可改，语义钉住）：

```text
struct HostDiskDriverCounters {
  id: String            // registry / BSD 名，仅作差值键
  bytesRead: UInt64     // Statistics "Bytes (Read)"
  bytesWritten: UInt64  // Statistics "Bytes (Write)"
}

struct HostDiskRates {
  readBytesPerSecond: Double?
  writeBytesPerSecond: Double?
}
```

规则与 `HostNetworkLoad.advance` / `SystemCPULoad.advance` 对齐：

- 第一帧：记下 counters，速率 `nil`，UI「—」。
- 其后：`Δbytes / Δseconds`。墙钟 ≤ 0、当前计数 < 上一帧（重置 / 回绕）、IOKit 匹配或属性失败 → 该帧 `nil`，**不写 0**。
- 失败读保留上一帧 baseline（与 CPU / 网络 `advance` 相同），不要用 0 覆盖。
- 按驱动 id 做 per-driver 差值再加总。新驱动第一帧跳过。须单测钉住「集合变化不得喷出天文数字」。
- 无可用驱动 / 空 Statistics：该帧 `nil`，不是 0 B/s。

周期：前台约 1.5s，后台随菜单栏约 2–3s。不要为磁盘另开更快的 tick。

视图侧可做 `SystemDiskHistory` ring（对齐 `SystemNetworkHistory`）：只在速率非 `nil` 时入环，缺数跳过，永不存 0 冒充空闲。

## 进程磁盘：`proc_pid_rusage`（有 API，不装「整列不可用」）

产品允许：总览看系统粗速率；进程列在稳定 API 下给出粗读/写，否则「—」。

公开 libproc：`proc_pid_rusage(pid, RUSAGE_INFO_V4 /* 或 CURRENT */, &info)` → `ri_diskio_bytesread` / `ri_diskio_byteswritten`。自 `RUSAGE_INFO_V2`（约 10.9）起就有；Pulse 部署目标 14+，锁 **V4 或 `RUSAGE_INFO_CURRENT`**（两者都带这两个字段）。无新 entitlement、无 TCC 全盘、无 Hardened Runtime 例外。

这与四期网络**不对称**：网络没有公开 per-process 字节，所以整列「暂不可用」。磁盘有公开字段，所以：

1. 在现有 `ProcessEnumerator.inspect` **同一趟**加一次 `proc_pid_rusage`。`proc_pidinfo` 失败仍可丢行；**rusage 失败不得丢行**——进程照列，磁盘速率 `nil`。
2. Sampler 维护 `pid → DiskTick{bytesRead, bytesWritten, date}`（对齐 `cpuTicks`）。速率 = 两帧墙钟差。第一帧 / 墙钟 ≤ 0 / 当前 < 上一帧（pid 复用或回绕）→ `nil`。
3. 返回非 0（`EPERM` / `ESRCH` / 其它）：该 pid 本帧 `nil`。SIP 保护进程、内核任务常会拒绝——格子「—」，**不要**为此加 Helper / 提权 / 假「需要完全磁盘访问」。
4. **不**用 `pti_pageins`、`pti_faults`、`pti_messages_*`、网络 `ifi_*`、主机 IOKit 总数均摊来编造进程字节。
5. 不给 `ProcessRow` 填假的 `UInt64` 0。字段用 `Double?`（字节/秒）或一对 optional；`nil` 的 UI 必须是「—」。

默认排序：磁盘页按 **读+写合计速率降序**（本页主度量，对齐 CPU 页按 cpu%、内存页按内存）。缺值沉底（`-1`），不装 0。用户仍可点 CPU / 内存 / 名称 / 线程。`ProcessTableSort.defaultSort(for:)` 今天把 `.disk` 并进内存降序，接线时改掉。

过滤、选中、空态、虚拟化列表沿用；不要为磁盘页新开枚举通道。

进程表列：磁盘页加 **读取 / 写入**（可两列，或一列写成「读取 · 写入」）。文案必须是这两个词；缺速率「—」，不能是「暂不可用」装成「没有 API」，也不能是「0 字节/秒」。其它页不加这两列。

以后若某台机器上 Hardened Runtime 把 `proc_pid_rusage` 打成全表失败：整列退回「—」，并在实现 PR 里写明实测，**仍不加 entitlement**。不要改口去用 Mach / 网络计数。

## 卷容量 / 剩余（本刀 Out）

`statfs` / `FileManager.volumeAvailableCapacityForImportantUsage` 不加权限也能读，但同构总览已锁成两个速率大数（对齐网络「接收 / 发送」），再塞「已用 / 可用」会变成第三度量或进度条——新 UX。活动监视器级分卷也不做。

五期首包：**不做**卷容量、剩余、已用百分比、启动盘条。不要在总览 caption 里偷偷挂 `statfs`。若以后要做，另开设计。

## 磁盘 Tab UI

结论：解灰现有磁盘占位，壳子跟 CPU Tab（二期）/ 网络 Tab（四期）同一套。冷启动仍默认内存页。

### 导航与壳

现成锚点（接线时改这些，不要另起一套窗口）：

- `ResourceTab.disk` / `DashboardPage.disk` 已在枚举里；`isSelectable` 现为 `false`。五期：磁盘可点；**GPU 仍灰置**。
- `MemoryDashboardView`：`selectedPage` 现只分 CPU / 网络 / 默认内存。五期加磁盘总览分支（建议 `DiskOverviewSection`，对齐 `NetworkOverviewSection` 的 150pt 双卡片：左侧大数、右侧 sparkline）。
- `ProcessTablePane`：cpu / network 走 `resourceTableBody`，其它走内存空态。磁盘页复用同一 `processList` + `ProcessLine`，换页级文案与读取 / 写入列。
- `ContentView.onAppear`：不可选页会打回内存。磁盘可点后不再被打回。
- `MemoryDashboardVM.selectPage` 注释仍写「Memory, CPU, and network」——接线时改，菜单栏主点仍 `focusMemoryPage()`。
- 三期 `memoryGrowthSlot` 已按页门控：磁盘页**不要**解释增长软信号，无信号则静默。

### 总览

| 能力 | 来源 | 说明 |
| --- | --- | --- |
| 读取 / 写入大数 | `SampledFrame` 上的系统读/写速率 | 文案用「读取」「写入」，不用「狂读盘」。`nil` →「—」 |
| 总览曲线 | 视图侧 ring | 可画读 / 写分线；缺数不入环。少于 2 点可「正在采样…」 |
| 失败 | 与网络同构 | 「暂时读不到磁盘数据，稍后重试」；**不**写「需要完全磁盘访问」 |
| 空态 | 产品已锁 | 「暂无磁盘数据」 |
| 采样中 | 产品已锁 | 「正在采样…」 |

不做：分卷条、容量环、每盘 ops / 延迟、IOPS 仪表、把内存压力色套到磁盘上（磁盘页不发明第三档「磁盘爆红」）。

### 侧栏与退出

侧栏继续 `ProcessDetail`：内存主曲线 + CPU 辅曲线；切进程仍清空重采。五期**不**加进程磁盘曲线（保持与内存 / CPU / 网络侧栏同构，避免新 UX）。退出 / 强制退出仍 `ProcessActions.terminate` → `forceTerminate` + 系统 `NSAlert`。无自动杀、无「检测到狂写后结束进程」。

明确不做（相对本 Tab）：GPU 侧栏小格、菜单栏弹出条 B、列表增长角标、假 TCC 墙、卷容量条。

## 文案（冷静，白名单语气）

磁盘页语气对齐 CPU / 网络页，不沿用内存压力「余量紧张」——磁盘没有压力档。

产品已锁（实现时可收进 `DiskPageCopy`）：

| 场景 | 文案 |
| --- | --- |
| 空态 | 暂无磁盘数据 |
| 采样中 | 正在采样… |
| 主机读失败 | 暂时读不到磁盘数据，稍后重试 |
| 总览标签 | 读取 / 写入 |
| 第一帧或缺速率（总览或进程格） | — |
| 侧栏空态 | 选一个进程看详情（可与 CPU / 网络共用） |

禁止出现：泄漏、危险、磁盘将满、被占满、狂写、异常 IO、中招、需要完全磁盘访问、未授权所以看不到、磁盘告警。失败态不暗示用户去开 TCC。进程缺数用「—」，不用「暂不可用」（那个词留给「没有 API」的网络列）。

## 风险

| 风险 | 应对 |
| --- | --- |
| 把 VM pagein / Mach 消息 / 网络字节当成磁盘 | 上文对照表写死；单测与验收搜 `pageins`、`pti_messages`、`ifi_ibytes` 不得进磁盘列 |
| 第一帧或失败装 0 B/s | 可空速率 +「—」；与 CPU / 网络同一条「不装 0」纪律 |
| 驱动增减导致吞吐尖刺 | 强制 per-driver 差值；集合变化单测 |
| 为了 SIP 进程去加 Helper / entitlement | 首包范围表写死不加；`EPERM` 格子「—」 |
| 用 rusage 磁盘字节回头填网络列 | 四期已禁；五期只把这两个字段给磁盘页 |
| 做成 GPU 深页、分卷深挖或菜单栏 B | GPU 仍灰置；容量 / ops Out；菜单栏仍交互 A |
| 恐吓文案 / 假权限墙 | 白名单；验收搜「泄漏」「危险」「完全磁盘」 |
| 自身占用 | 同一 tick、同一降频；禁止第二路轮询、禁止 `iostat` 子进程 |

## 验收（五期首包）

产品 Must：

- [ ] 磁盘 Tab 可点；信息架构为总览 → 进程表 → 详情 → 退出，与内存 / CPU / 网络同构
- [ ] 总览展示系统读取 / 写入粗速率（IOKit `IOBlockStorageDriver` 累计字节两帧差）；第一帧或失败为「—」，不装 0
- [ ] 进程读取 / 写入来自 `proc_pid_rusage` 的 `ri_diskio_*` 两帧差；第一帧 / 失败 / 回绕 / `EPERM` 为「—」，不编造、不用 Mach / 网络计数
- [ ] 默认按合计磁盘速率降序；缺值沉底
- [ ] 侧栏仍是内存主 + CPU 辅 + 既有退出链路；无自动杀
- [ ] 文案冷静，且只用已锁句子：空态「暂无磁盘数据」；采样「正在采样…」；失败「暂时读不到磁盘数据，稍后重试」；总览「读取」「写入」；缺数「—」
- [ ] 无「泄漏」「危险」及假权限墙

明确不做（本包出现即不合格）：

- [ ] GPU 仍灰置
- [ ] 无菜单栏弹出条 B；栏上仍只是压力色点；点击仍回内存页
- [ ] 无列表增长角标
- [ ] 无卷容量 / 剩余 / 分卷条
- [ ] 无活动监视器级 ops / 延迟 / 队列 / `fs_usage`
- [ ] 无 Helper / XPC、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 不把 `host_statistics64` pageins、`pti_pageins`、`pti_messages_*` 或网络字节显示成磁盘

共性：

- [ ] 一二三四期验收不回退（内存页、CPU Tab、网络 Tab、菜单栏色点、增长软信号仅内存详情、退出链路）
- [ ] 冷启动仍默认内存页
- [ ] 系统磁盘差值与进程磁盘差值有 `swift test`；不编 App 也能验第一帧 / 失败 / 回绕 / `EPERM`
- [ ] 不改公证脚本与 entitlements

## 工期

小：按「采样 / 模型 + 单测 → 磁盘 Tab UI 同构接线」拆两个工程 PR。保持同构、不加新 entitlement 时是天级，不是周级。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。

---

# Pulse 六期技术设计（首包：内存列表上涨轻角标）

> 一期至五期正文不改写。三期写明「不做列表角标」、四期 / 五期写明「列表增长角标仍不做（延期）」——**本文只覆盖那条延期**：把已有的 `MemoryGrowthSignal` 上涨态投到内存页进程列表行上，做成轻角标。不新开增长算法、不扫全表、不扩 Sampler ring。GPU Tab、菜单栏弹出条 B、磁盘 / 卷额外项、自动杀、恐吓文案、Helper / XPC、Electron 仍不做。

**已锁定**：仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。角标复用三期详情侧栏已经在算的 `MemoryGrowthSignal`（`[ChartSample] →` 三态），**禁止**第二套斜率 / 泄漏算法。角标**只在该行进程已经是 `.rising` 时出现**；样本不足、无信号、持平都不画角标，也不在角标位写「—」。本刀只改**内存 Tab** 列表行。不新开 entitlements、不拆 Helper / XPC、不自动杀。文案冷静，对齐详情「内存趋势」上涨态；永不写「泄漏」。

来源：用户 + 产品锁定的六期 Must；对照现实现（`MemoryGrowthSignal.evaluate` + `MemoryGrowthSidebar.slot` 只服务内存页详情；Sampler 只为选中 pid 维护 `selectedMemorySeries`，切进程清空；`ProcessRow` 无增长字段；`ProcessLine` 跨 Tab 复用、现无角标）。

## 范围（相对一二三四五期）

| 项 | 一二三四五期 | 六期首包 |
| --- | --- | --- |
| 增长斜率 / 判泄漏 | 三期已锁：只软信号，不是泄漏判定 | **仍不做泄漏判定**。算法、阈值、输入序列一字不改 |
| 信号入口 | 只详情侧栏；列表角标延期 | **做**：内存页列表行轻角标，投影已有 `.rising` |
| 数据源 | 选中 pid 的 `memorySeries` | **只复用这条**。不扩成全表时序、不新开采样通道 |
| 列表角标 | 三期禁止；四 / 五期延期 | **做（本刀）**：仅内存列表；仅 `.rising` |
| CPU / 网络 / 磁盘列表行 | 同构 `ProcessLine`，无增长角标 | **仍不画**。产品未要求全 Tab；默认内存-only 保范围最小 |
| GPU Tab | 灰置 | **仍灰置** |
| 菜单栏 | 交互 A：栏上仅压力色点 | **不变**。不做弹出条 B；不因增长改色点 |
| 文案 | 详情：上涨 / 不足 / 静默；禁泄漏 | 角标只用冷静上涨短词；不足 / 无信号**不占位**（与详情不足态不同） |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 | 不做 | **仍不做** |
| 压力第三档恐吓红 | 不做 | **仍不做** |

一二三四五期验收、菜单栏交互 A、CPU / 网络 / 磁盘 Tab、详情侧栏三态、公证路径不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

- `SwiftUI Views`（`ProcessLine`，仅内存页）←观察→ 同一 `MemoryDashboardVM`
- 详情侧栏继续走现成 `memoryGrowthSlot` / `MemoryGrowthSidebar`——**本刀不改详情三态**
- 列表角标是对同一 `MemoryGrowthSignal` 的**另一处投影**，不是第二条判定
- Sampler 同一 `sample()` tick：选中 pid 继续写入 `selectedMemorySeries`（现 `seriesLimit = 90`）
- **增长信号仍不进 Sampler**。不给全表 `ProcessRow.memoryBytes` 攒多进程 ring

约束：

- 不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询。
- 不改 `Pulse.entitlements`、不改公证脚本、不改菜单栏色点映射。
- 自身占用仍优先：角标是 O(1) 的可见性谓词（对已经算过的信号），不加倍采样。
- `ProcessLine` 已被 CPU / 网络 / 磁盘页复用——接线必须按页门控，禁止「所有 Tab 顺手亮角标」。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `MemoryGrowthSignal.swift`、`MemoryDashboardVM.memoryGrowthSlot`、`ProcessRow`、`MemorySampler`。本刀必须按「已有 / 没有」落笔，**禁止**为了列表亮灯再发明一套增长数学。

| 现字段 / 调用 | 文件 | 六期怎么用 |
| --- | --- | --- |
| `MemoryGrowthSignal.evaluate` | `Models/MemoryGrowthSignal.swift` | **原样调用**。`minSamples` / `deltaThreshold` / `riseFloor` 不改 |
| `MemoryGrowthCopy` / `MemoryGrowthSidebar.slot` | 同上 | 详情继续：`.rising` / `.insufficient` 可见，`.none` 不占位。列表**不**复用不足态文案 |
| `ProcessDetail.memorySeries` | Sampler 选中 pid ring | 角标的**唯一**输入序列 |
| `ProcessRow` | `MemoryModels` | pid / cpu / rss / 线程 / 磁盘速率等。**无**增长字段 |
| Sampler `selectedMemorySeries` | 切 pid `removeAll` | **不扩**成全表 ring |

**缺口**：`ProcessRow` 上没有现成 `growthSignal` flag。这**不是**采样缺口——现有 series + `evaluate` 已能判定**选中行**是否 `.rising`。不要为了「每行都能亮」去给可见进程攒 ring：那会变成第二路时序、违反三期「只有点开的进程有曲线」，也把本刀从天级 UI 拖成采样改造。

因此本刀：

1. **零 Sampler 改动**（无新字段、不拉长 ring、不扫全表）。
2. 模型侧最多加一个纯函数 / VM 派生，例如 `MemoryGrowthListBadge`：`页 == .memory && 该行 pid == selectedPid && evaluate(detailSeries) == .rising` → 返回角标文案，否则 `nil`。
3. **不要**给 `ProcessRow` 加 `isRising` 存成采样字段——那会暗示每行都有独立判定。
4. 未选中行没有 series → 没有上涨信号 → 无角标。这是本刀范围，不是漏做。

### 建议模块 PR 顺序

信号已经在 `ProcessRow` 上？**没有。** 但也不需要先开采样 PR。

合并后工程顺序（一个 UI PR 即可，若暴露层只是几行纯函数）：

1. **小模型暴露 + 列表接线**：`MemoryGrowthListBadge`（或等价）纯函数 + `ProcessLine` 内存页角标 + `swift test`。覆盖：仅 `.rising` 可见；不足 / none / 未选中 / 非内存页都不出现；文案无「泄漏」。

三期算法单测已在。不必再拆「helper PR → UI PR」，除非暴露层长出新阈值（本刀禁止新阈值）。不要把本刀和 GPU / 菜单栏 B / 磁盘卷容量捆在一起。合并不擅自写代码。

## 可见性（产品 Must）

结论：角标是「该行**已经**处于上涨软信号」的列表投影，不是新扫描。

| 条件 | 角标 |
| --- | --- |
| 内存页 + 该行 pid == `selectedPid` + `evaluate(memorySeries) == .rising` | **画**轻角标 |
| `.insufficient`（窗口未满、刚点开、切进程后第一帧） | **不渲染**。不是角标上写「—」，也不是详情那句「样本不足，暂不判断」 |
| `.none`（窗口够但净增不够 / 正步比例低 / 持平） | **不渲染** |
| 未选中行（无 series） | **不渲染** |
| CPU / 网络 / 磁盘 / GPU 页 | **不渲染** |
| 无选中 / 进程已从列表消失 | 随侧栏一起卸掉，无残留 |

切进程：三期已锁「旧上涨不得带到下一进程第一帧」。列表角标同一条：新行在不足或 none 期间不得亮；只有新 pid 自己评出 `.rising` 才亮。

详情侧栏三态保持原样：不足仍然可见「样本不足，暂不判断」；列表不把不足态做成角标。两边读同一信号，展示策略不同——这是有意的，避免每行都闪「—」。

## UI 绑定

结论：只改内存页进程列表行。设计定视觉（色、尺寸、形状、是否 pill / 点）；TECH 锁定**出现条件与文案语气**。

### 位置

- 主入口：内存 Tab 的 `ProcessLine`，贴在进程名附近（轻角标，**不是**新的可排序列，不参与默认排序加权）。
- `ProcessLine` 已按页显示网络列 / 磁盘列。六期再加一个 `showsMemoryGrowthBadge`（或把文案 `String?` 传进去），仅 `selectedPage == .memory` 为真。
- CPU / 网络 / 磁盘列表行：本刀**不画**。产品没有先锁「全 Tab 都亮」；默认内存-only，避免同构行被增长语义污染。
- GPU Tab Out。菜单栏仍交互 A，不做弹出条 B。

### 文案（冷静，已选题，设计可改词不改义）

对齐详情标题「内存趋势」+ 上涨 caption「近几分钟持续上涨」。列表位更短。

| 表面 | 锁定用词 | 说明 |
| --- | --- | --- |
| 角标本体 | **上涨** | 短、冷静、与详情上涨态同义 |
| Hover / accessibility | **近期内存持续上涨** | 比本体多「近期」「内存」，避免被读成 CPU / 磁盘在涨 |
| 详情（不改） | 「内存趋势」/「近几分钟持续上涨」 | 列表不复制整句，以免挤行 |

以上为锁定默认。设计仍可微调用词（不改含义），**不得**写成判定或恐吓。

禁止出现：泄漏、泄露、leak、危险、告警、异常、中招、需要完全磁盘访问。验收对锁定字符串与实现字符串搜这些词。

### 明确不做（相对本刀）

- 自动 `terminate` / 因上涨结束进程。
- 假「需要完全磁盘访问」墙。
- 菜单栏色点随增长变色、弹出条 B、常驻通知。
- 全表扫描、第二套斜率、把 `UsageHistory` 系统总用量误当成进程曲线。
- 活动监视器式「内存泄漏」列或排序加权。
- 给不足态画灰角标或「—」。

## 风险

| 风险 | 应对 |
| --- | --- |
| 忍不住给全表攒 ring / 改 Sampler | 上文缺口写死：不是采样缺口；未选中无角标是范围 |
| 第二套算法（列表用 rss 两点差） | 只允许 `MemoryGrowthSignal.evaluate`；单测钉「同一 series，详情 rising ⟺ 该行角标」 |
| 不足 / 持平画成「—」角标 | 可见性表：只有 `.rising` 渲染；不足与 none 都是 `nil` |
| 切进程脏角标 | 复用三期清 ring；派生随 `selectedPid` / `detail` 卸掉 |
| `ProcessLine` 跨 Tab 漏网 | 按页门控；CPU / 网络 / 磁盘验收「无角标」 |
| 被读成「就是泄漏」 | 文案白名单；验收搜「泄漏」「leak」「危险」 |
| 自动杀 / 新 entitlement | 范围表写死不加 |

## 验收（六期首包）

产品 Must：

- [ ] 内存页进程列表行：仅当该行进程已有 `MemoryGrowthSignal.rising` 时出现轻角标
- [ ] 样本不足 / 无信号 / 持平 / 未选中：**无角标**，角标位也不写「—」
- [ ] 算法仍是三期 `MemoryGrowthSignal.evaluate`（同一 `memorySeries`）；不新开 Sampler 字段、不第二套增长数学
- [ ] CPU / 网络 / 磁盘列表行无此角标；GPU 仍灰置
- [ ] 详情侧栏三态不回退（上涨 / 不足可见 / none 不占位）
- [ ] 角标本体锁定「上涨」；Hover / accessibility 锁定「近期内存持续上涨」（设计可改词不改义）
- [ ] 永不写「泄漏」/ leak / 「危险」；无自动杀；无假权限墙

明确不做（本包出现即不合格）：

- [ ] 无全表 ring / 无第二路采样
- [ ] 无菜单栏弹出条 B；栏上仍只是压力色点；点击仍回内存页
- [ ] 无 Helper / XPC、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 无磁盘 / 卷额外项、无活动监视器泄漏列

共性：

- [ ] 一二三四五期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏色点、详情增长软信号、退出链路）
- [ ] 冷启动仍默认内存页
- [ ] UI / 单测：角标可见 ⟺ 上涨信号；其余缺席；拷贝无「泄漏」
- [ ] 不改公证脚本与 entitlements

## 工期

小：信号已在详情侧；`ProcessRow` 无现成 flag，但暴露只是纯函数。**一个工程 PR**（小模型暴露 + 列表行 + 单测）即可，天级，不是周级。不要先开采样 PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。

---

# Pulse 七期技术设计（首包：菜单栏轻量条 B）

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

---

# Pulse 八期技术设计（收尾验收：polish + 本机冒烟）

> 一期至七期正文不改写。一二三四五六七期已经把内存页、菜单栏 A、CPU Tab、详情增长软信号、网络 / 磁盘 Tab、列表上涨角标、菜单栏轻量条 B 锁完——**本文不是新功能刀**，只覆盖**收尾验收**：文案 / 空态 / 密度 polish，以及一张本机冒烟清单。GPU Tab、全表成长环 / 全表增长时序、新 Tab、Helper / XPC、恐吓文案、假权限墙仍不做。

**已锁定**：八期 = **A（收尾）**。零新采样、零功能扩张。工程若动代码，只修冒烟里发现的文案 / 空态 / 密度小问题，**不是**新功能。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`；**零 Sampler 改动、零新模型字段、零新 entitlement**。栏上仍是二期交互 A 色点；弹出条仍是七期 B（压力一行 + Top3 +「打开 Pulse」）。详情「内存趋势」仍是三期三态；列表徽标仍是六期「仅选中行 `.rising`」。网络 / 磁盘 Tab 空 / 加载 / 失败文案仍对齐四 / 五期已锁句子。分发仍走 `docs/RELEASE.md`；无 Developer ID 时公证标明 blocked，**不挡**功能验收。不做新界面。

来源：用户 + 产品锁定的八期 Must（七期菜单栏 B 已合 #25–#27）；对照现实现（内存 / CPU / 网络 / 磁盘 Tab、详情 `MemoryGrowthSignal`、内存列表 `MemoryGrowthListBadge`、同进程 `NSStatusItem` + 弹出条 B）。本文只锁验收与冒烟，不重开各期架构。

## 范围（相对一二三四五六七期）

| 项 | 一二三四五六七期 | 八期 |
| --- | --- | --- |
| 定位 | 各期功能刀（采样 / Tab / 角标 / 弹出条） | **收尾验收**：polish + 本机冒烟，不是新刀 |
| Sampler / 模型字段 | 各期按刀增量（四 / 五期有采样增量；六 / 七期已锁零 Sampler） | **零 Sampler、零新模型字段** |
| 新 entitlement / TCC | 空 dict，不申请 | **仍不申请** |
| 新 Tab / GPU | GPU 仍灰置；无新 Tab | **仍灰置、仍无新 Tab** |
| 全表成长环 / 全表增长时序 | 三期起只选中 pid ring | **仍不做**。禁止借 polish 扩成全表 |
| 菜单栏 | A 色点 + B 弹出条 | **回归冒烟**，不改交互 |
| 增长软信号 | 详情三态 + 列表上涨角标 | **回归冒烟**（设计侧 4 条之 1–2），不改算法 |
| 网络 / 磁盘 | 四 / 五期同构 Tab | **回归冒烟**（设计侧 4 条之 4），不深挖 |
| Helper / XPC / 登录项 | 无 | **仍无** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 / 恐吓文案 | 不做 / 禁止 | **仍禁止** |
| 工程 PR | 按刀拆采样 / UI | **默认无功能 PR**。冒烟发现硬伤才开最小 fix（单行为） |

一二三四五六七期验收与公证路径不因本文重开。本文合并后的工作是**本机勾选**，不是再写一套架构。

## 零增量（工程红线）

八期**不是**架构增量。下列三项写死，出现即不合格：

- **零 Sampler**：不改 `sample()` tick、不拉长 ring、不第二路 Mach / `proc_listpids`。
- **零新模型字段**：不给 `ProcessRow` / `SampledFrame` / `MemorySnapshot` 加字段；不新开增长算法、不新开弹出条度量。
- **零新 entitlement**：`Pulse.entitlements` 保持空 dict；不申请 TCC 全盘、不加 Hardened Runtime 例外、不拆 Helper / XPC。

工程若动代码：只修冒烟勾到的文案错字、空态漏渲染、密度过挤 / 过空——**单行为、最小 diff**。禁止借机做 GPU Tab、全表 ring、新 Tab、菜单栏第二窗、弹出条趋势图。

## 本机冒烟清单

矩阵以本文为准。开发 / 用户在 **macOS 14+、Xcode 15+** 对本机 Debug `.app`（`CODE_SIGN_IDENTITY=-`）勾选。Linux CI 只能审文档，不能代勾。

### 设计侧冒烟（已锁，可扩不可少）

这 4 条是设计侧锁定的验收核，**可扩不可少**。不做新界面来「方便勾选」。

- [ ] **详情「内存趋势」三态**（三期）：上涨可见「近几分钟持续上涨」；样本不足可见「样本不足，暂不判断」；无信号 **不占位**（无空槽、无「暂无异常」）。全程无「泄漏」/ leak / 「危险」
- [ ] **列表徽标**（六期）：仅内存页、仅该行已选中且 `MemoryGrowthSignal` 为 `.rising` 时出现「上涨」；hover / accessibility 为「近期内存持续上涨」。不足 / none / 未选中 / 非内存页：**无角标**，角标位也不写「—」
- [ ] **菜单栏 B**（七期）：点击状态项弹出轻量条——压力一行（仅 `normal | elevated`）+ 内存 Top3 +「打开 Pulse」进**现有**主窗内存页。空态用次要文字色；无红闪、无菜单栏终止 / 强杀其它进程。栏上仍是 A 色点
- [ ] **网络 / 磁盘 Tab 文案**（四 / 五期）：空 / 加载 / 失败仍对齐前期锁，不另作文案。网络：加载「正在采样…」、失败「暂时读不到网络数据」+「这轮采样没有回来，点重新采样再试。」、进程列「暂不可用」。磁盘：空态「暂无磁盘数据」、加载「正在采样…」、失败「暂时读不到磁盘数据，稍后重试」；缺速率「—」，不装 0、不用「暂不可用」冒充「没有 API」

### 一期～七期回归（共性，可保留）

- [ ] **一期**：冷启动默认内存页；压力只 `normal | elevated` 两档；进程表默认内存降序；退出 `terminate` → 强制退出 `forceTerminate` + 系统确认；无恐吓文案
- [ ] **二期**：栏上 A 色点（正常绿 / 偏高琥珀 / 失败灰）；CPU Tab 可点，信息架构与内存同构；主窗打开路径仍落内存页（现由 B 的「打开 Pulse」触发，不再是主点直开）
- [ ] **三期**：见上方设计侧第 1 条；切进程后旧上涨立即消失
- [ ] **四 / 五期**：网络 / 磁盘 Tab 可点、同构冒烟（总览 → 表 → 详情 → 退出），**不深挖**（无分卷 / 无进程网络字节 / 无 GPU）；文案见设计侧第 4 条
- [ ] **六期**：见上方设计侧第 2 条
- [ ] **七期**：见上方设计侧第 3 条；零第二扇窗、零第二套 VM / Sampler
- [ ] **公证**：仍按 [docs/RELEASE.md](RELEASE.md)。无 Developer ID / 公证材料时该项标 **blocked**，**不挡**上面的功能验收

## Polish 范围

仅修冒烟发现的**文案 / 空态 / 密度**小问题（错字、漏空态、行高过挤、次要色没用上）。

禁止借机：

- 解灰 GPU、做 GPU 深页
- 把选中 pid ring 扩成全表成长环 / 全表增长时序
- 新 Tab、新窗口、菜单栏趋势图、第三档恐吓红
- 改采样周期、加 entitlement、上 Helper / XPC
- 重写增长算法或另做一套「泄漏」文案

没有硬伤就不开工程 PR。有硬伤：一个行为一个最小 fix PR，标题写清「八期 polish：…」，不要和 GPU / 全表 ring 捆在一起。

## 建议工程顺序

1. **冒烟清单进仓**（本文）。合并后开发 / 用户本机按清单勾选；矩阵不另起表格文件。
2. **本机勾选**。能勾完且无硬伤 → 八期收尾完成，不必再开功能 PR。
3. **硬伤才修**。只开最小 polish / 文案 fix PR（单行为）。修完把对应勾选补上。
4. **公证并行、不挡功能**。有 Developer ID 再走 `RELEASE.md`；没有就标 blocked。

不要先开「八期功能」采样 PR 或 UI 重做 PR。本文合并**不是**写 Swift 的门禁——默认没有 Swift 要写。

## 验收（八期）

设计侧 4 条（已锁，可扩不可少）——与上文冒烟核重复，勾一次即可：

- [ ] 详情「内存趋势」三态：上涨 / 样本不足 / 无占位；无「泄漏」
- [ ] 列表徽标：仅选中行 `.rising` 出「上涨」，hover「近期内存持续上涨」
- [ ] 菜单栏 B：压力一行 + Top3 +「打开 Pulse」进主窗；空态次要色、无红闪 / 无终止
- [ ] 网络 / 磁盘 Tab：空 / 加载 / 失败文案仍对齐前期锁

明确不做（本包出现即不合格）：

- [ ] 无新界面、无新 Tab、GPU 仍灰置
- [ ] 无全表成长环 / 无第二套增长数学 / 无 Sampler 改动
- [ ] 无新模型字段、无新 entitlements、无 Helper / XPC
- [ ] 无恐吓文案、无假权限墙、无自动杀
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 不把公证 blocked 当成功能失败

共性：

- [ ] 一二三四五六七期验收不回退（见上方回归勾选）
- [ ] 冷启动仍默认内存页
- [ ] 不改公证脚本与 entitlements

## 工期

小：半天～1 天量级——**文档进仓 + 本机勾选**，不是功能周。有硬伤再加一个最小 polish PR，仍是天级以内的单行为，不是再开一期刀。本文只锁验收，不估日历人天。

实现默认**不动** Swift、采样、entitlements 与脚本。只有冒烟勾出硬伤、且用户 / 主控确认后，才开最小 fix PR。

---

# Pulse 九期技术设计（首包：内存列表上涨徽标密度 Top N=5）

> 一期至八期正文不改写。六期写明「角标仅选中行 `.rising`」、八期冒烟第 2 条仍按「仅选中行」回归——**本文只覆盖那条密度延期**：把已有的内存列表「上涨」徽标从「仅选中」扩成「当前排序 Top N=5 ∩ `.rising`」。不新开增长算法、不扫全表、不改 Sampler 周期。GPU Tab、无界全表 series / ring、点击徽标跳详情、恐吓文案 / 「泄漏」、Helper / XPC、新 Tab、Electron、自动杀、新 entitlements 仍不做。

**已锁定**：九期 = **B（密度）**。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。徽标**只复用** `MemoryGrowthSignal.evaluate`，**禁止**第二套斜率 / 泄漏算法、禁止 rss 两点差 hack。列表徽标出现条件改为：该行 pid ∈ **当前内存页排序 Top N=5** 且 `evaluate == .rising`。文案 / 样式复用六期：本体「上涨」；hover / accessibility「近期内存持续上涨」；次要文字色；无红闪。不是滚动视口「看得见的行」，不是无界全表 ring。详情侧栏「内存趋势」三态（三期）一字不改。选中 pid 若不在 Top 5：列表徽标不亮，详情照常。N=5 **硬封顶**。允许 **有界** Sampler 增量：为当前 Top 5 个 pid 维护短 series（同一 `sample()` tick / 同一周期，**不是**新采样周期）；pid 跌出 Top 5 则立刻 drop / clear。零新 entitlement / Helper / XPC。只改内存 Tab 列表。

来源：用户 + 产品锁定的九期 Must（八期收尾已合 #28）；对照现实现（`MemoryGrowthList.badge` 仍是 `页 == .memory && rowPid == selectedPid && evaluate(detailSeries) == .rising`；`ProcessTablePane` 只把 `vm.memoryGrowthListBadge` 传给选中行；Sampler 只为选中 pid 写 `selectedMemorySeries`，`seriesLimit = 90`；`ProcessTableSort` 内存页默认内存降序）。

## 范围（相对一二三四五六七八期）

| 项 | 一二三四五六七八期 | 九期首包 |
| --- | --- | --- |
| 定位 | 六期：列表徽标仅选中行 `.rising`；八期按该条冒烟 | **密度（B）**：同一枚徽标，出现条件改为 Top N=5 ∩ `.rising` |
| 增长算法 | 三期 `MemoryGrowthSignal.evaluate`；六 / 八期禁止第二套 | **仍只调用这一份**。无 rss 两点差、无新阈值 |
| Sampler series | 三期起只选中 pid `selectedMemorySeries`；六 / 八期锁零 Sampler / 禁全表 ring | **允许有界增量**：当前 Top N=5 各一条短 series。同一 tick / 同一周期。N=5 硬封顶。**不是**新采样周期，**不是**无界全表 ring |
| 列表徽标可见性 | 六期 / 八期：仅选中行 + `.rising` | **做（本刀）**：pid ∈ 当前排序 Top 5 且 `.rising`。选中但不在 Top 5 → 列表不亮 |
| 详情「内存趋势」 | 三期三态（上涨 / 不足可见 / none 不占位） | **不改**。选中 pid 在不在 Top 5 都不影响详情 |
| 文案 / 样式 | 六期：「上涨」+「近期内存持续上涨」；次要色；无红闪 | **原样复用**。不新作文案、不改色 |
| 滚动视口可见行 | — | **不做**。不是「屏幕上看得见的行都评」 |
| 点击徽标跳详情 | 六期角标不可点 | **仍不可点**。点行选中仍走现成列表选中，不因徽标跳转 |
| CPU / 网络 / 磁盘列表行 | 六期不画 | **仍不画** |
| GPU Tab | 灰置 | **仍灰置** |
| 采样周期 | 前台 ~1.5s，后台 ~2–3s | **不改**。Top 5 series 吃同一 `sample()` |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 / 恐吓文案 | 不做 / 禁止 | **仍禁止**。永不写「泄漏」 |

一二三四五六七八期验收与公证路径不因本文重开。八期冒烟第 2 条「仅选中行」由本文覆盖；详情三态、菜单栏 B、网络 / 磁盘文案不重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

- `SwiftUI Views`（`ProcessLine`，仅内存页）←观察→ 同一 `MemoryDashboardVM`
- 详情侧栏继续走现成 `memoryGrowthSlot` / `MemoryGrowthSidebar`——**本刀不改详情三态**
- 列表徽标仍是对同一 `MemoryGrowthSignal.evaluate` 的投影，不是第二条判定
- Sampler 同一 `sample()` tick、同一周期（前台 ~1.5s / 后台 ~2–3s）、同一 `seriesLimit`（现 90）
- 选中 pid 的 `selectedMemorySeries` **继续按三期维护**（详情曲线 + 三态）
- **有界增量**：再为「当前内存页排序 Top N=5」维护最多 5 条短 series。pid 跌出 Top 5 立刻 drop / clear。N=5 硬封顶
- 选中 pid ∈ Top 5 时，详情与列表可共用同一段 series，禁止为同一 pid 采两遍
- 选中 pid ∉ Top 5 时：详情 series 照写，列表徽标不亮

约束：

- 不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询、不改采样周期。
- 不改 `Pulse.entitlements`、不改公证脚本、不改菜单栏 A / B。
- 自身占用仍优先：有界 5 条 series，禁止无界全表 ring。
- `ProcessLine` 跨 Tab 复用——接线必须按页门控，禁止「所有 Tab 顺手亮徽标」。
- 增长信号仍不进 `ProcessRow` 采样字段。不要给每行存 `isRising`。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `MemoryGrowthSignal.swift`、`MemoryGrowthList`、`MemoryDashboardVM.memoryGrowthListBadge`、`ProcessTablePane`、`MemorySampler`。本刀必须按「已有 / 没有」落笔，**禁止**为了多行亮灯再发明一套增长数学，也**禁止**把六期的「零 Sampler」误读成九期红线——六期只服务选中行，密度刀需要有界 series。

| 现字段 / 调用 | 文件 | 九期怎么用 |
| --- | --- | --- |
| `MemoryGrowthSignal.evaluate` | `Models/MemoryGrowthSignal.swift` | **原样调用**。`minSamples` / `deltaThreshold` / `riseFloor` 不改 |
| `MemoryGrowthListCopy` / `MemoryGrowthRisingBadge` | 同上 + `ProcessTablePane` | 文案「上涨」/「近期内存持续上涨」、次要色胶囊 **原样**。无红闪、不可点 |
| `MemoryGrowthList.badge` | 同上 | **改谓词**：`页 == .memory && pid ∈ top5 && evaluate(该 pid series) == .rising`。不再要求 `rowPid == selectedPid` |
| `ProcessDetail.memorySeries` / `selectedMemorySeries` | Sampler 选中 pid ring | **详情唯一输入**。三期清 ring / 切进程规则不改 |
| Top N=5 series | **现无** | **本刀有界增量**。当前排序前 5 个 pid 各一条；跌出即清 |
| `ProcessTableSort` | `CPUPage.swift` | 内存页当前表头排序（默认内存降序）决定 Top 5 集合 |
| `ProcessRow` | `MemoryModels` | **仍无**增长字段。不要加 `isRising` |
| 六 / 八期「仅选中行」 | `ProcessTablePane` `selectedPid == row.pid ? badge : nil` | **拆掉这道门**。改成按行查 Top5∩rising |

**缺口**：Sampler 今天只有选中 pid 的 series，未选中行评不出 `.rising`。这是六期故意留下的范围，不是算法缺口。九期要密度，就必须给当前 Top 5 攒短 series——**有界、可丢、N=5 硬封顶**。不要借缺口做成全表 ring，也不要用相邻两帧 `memoryBytes` 冒充上涨。

因此本刀：

1. **有界 Sampler 增量**（不是新周期）：维护 Top N=5 短 series；跌出即 `removeAll` / drop；传入超过 5 个 pid 也只留 5 个。
2. 选中 pid 详情 series **继续独立按三期走**（可与 Top 5 共用同一缓冲，不可双 tick）。
3. 模型侧纯函数 / VM 派生：`pid ∈ Top5 && evaluate == .rising` → 六期角标文案，否则 `nil`。不足 / none / 不在 Top 5 / 非内存页都是 `nil`，角标位不写「—」。
4. **不要**给 `ProcessRow` 加 `isRising` 采样字段。
5. 选中但不在 Top 5：列表无徽标；详情三态仍工作。这是本刀范围，不是漏做。

### Top N=5 定义（写死）

| 是 | 不是 |
| --- | --- |
| 内存页当前 `ProcessTableSort` 下、已采 `rows` 的前 5 个 pid（默认内存降序） | 滚动视口里看得见的行 |
| N=5 硬封顶；不足 5 条就按现有条数 | 无界全表 ring / 全表 series |
| 改表头排序或名次变化导致跌出前 5 → 立刻 drop / clear 该 pid series | 名称过滤表 `visibleRows`（过滤只影响画不画那一行，不改 Top 5 集合） |
| 仅内存 Tab 列表画徽标 | CPU / 网络 / 磁盘 / GPU 页、菜单栏 |
| 人在其它页时：不按 CPU / 磁盘排序扩 series | 把七期弹出条 Top3 或过滤表误当成 Top 5 |

离开内存页期间：Sampler **不要**跟 CPU / 磁盘表头走。续写用「最近一次内存页排序」的 Top 5，或回退到内存降序；切页本身不是清 series 的理由。回到内存页后按当时表头重新取前 5，跌出的照常 drop。

选中 pid 永远继续写详情 series，无论它在不在 Top 5。

## 建议工程顺序

1. **Sampler / 模型**：有界 Top 5 series + 纯函数「pid ∈ Top5 && `evaluate == .rising` → 六期角标文案，否则 `nil`」。`swift test` 钉：Top5 且 rising 亮；Top5 外不亮；不足 / none 不亮；排序 churn 跌出的旧 pid 立刻无徽标且 series 被清；只走 `evaluate`、无第二套算法；N 硬封顶 5（传入 6 个也只留 5）。
2. **列表 UI 接线**：`ProcessLine` / `MemoryGrowthListBadge` 从「仅选中」改为按行查 Top5∩rising。视觉、文案、次要色、不可点——与六期同一枚芯片。
3. **没有硬伤就不开 polish PR**。有硬伤：一个行为一个最小 fix，不要和 GPU / 全表 ring 捆在一起。

不要先开「新采样周期」PR 或「全表 ring」PR。合并不擅自写代码。

## 可见性（产品 Must）

结论：徽标是「当前排序前 5 里、已经评出上涨软信号」的列表投影。最多 5 枚。

| 条件 | 列表徽标 |
| --- | --- |
| 内存页 + pid ∈ 当前排序 Top 5 + `evaluate(该 pid series) == .rising` | **画**「上涨」（六期同款） |
| `.insufficient`（窗口未满、刚进入 Top 5、刚切排序） | **不渲染**。不是角标上写「—」 |
| `.none`（窗口够但净增不够 / 正步比例低 / 持平） | **不渲染** |
| pid ∉ Top 5（含选中但不在前 5） | **不渲染**。详情三态不受影响 |
| 名称过滤把该行藏起来 | 行不画则徽标不画；**不**因此把该 pid 移出 Top 5 series |
| CPU / 网络 / 磁盘 / GPU 页 | **不渲染** |
| 进程已从已采列表消失 / 跌出 Top 5 | series drop；无残留徽标 |

切排序 / 名次 churn：跌出 Top 5 的旧 pid 不得把上涨徽标带到新位置；新进入的 pid 在不足或 none 期间不得亮。对齐三期「旧上涨不得带到下一进程第一帧」的精神，作用对象从「选中 pid」换成「Top 5 集合」。

详情侧栏三态保持原样：不足仍然可见「样本不足，暂不判断」；列表不把不足态做成徽标。两边读同一 `evaluate`，展示策略不同——这是有意的。

## UI 绑定

结论：只改内存页进程列表行的**出现条件**。视觉锁在六期，本刀不重开设计。

### 位置

- 主入口：内存 Tab 的 `ProcessLine`，贴在进程名附近（轻徽标，**不是**新的可排序列，不参与默认排序加权）。
- 接线从「整表一个 `memoryGrowthListBadge` + 仅选中行传入」改为「按行 pid 查 Top5∩rising」。
- CPU / 网络 / 磁盘列表行：本刀**不画**。
- GPU Tab Out。菜单栏 A / B 不因上涨改色点或进弹出条。
- 点击徽标**不**跳详情、不改选中。点行选中仍走现成 `List` selection。

### 文案 / 样式（复用六期，不改义）

| 表面 | 锁定用词 | 说明 |
| --- | --- | --- |
| 徽标本体 | **上涨** | 与六期同一短词 |
| Hover / accessibility | **近期内存持续上涨** | 与六期同一句 |
| 颜色 | 次要文字色（`.secondary`） | 无红、无闪、无第三档恐吓红 |
| 详情（不改） | 「内存趋势」/「近几分钟持续上涨」 | 三期三态原样 |

禁止出现：泄漏、泄露、leak、危险、告警、异常、中招、需要完全磁盘访问。验收对锁定字符串与实现字符串搜这些词。

### 明确不做（相对本刀）

- GPU Tab；新 Tab。
- 无界全表 series / ring；滚动视口「可见行」扫描。
- 点击徽标 → 跳详情 / 改选中。
- **新 Sampler 采样周期 / cadence**（前台 1.5s、后台 2–3s 不动）。
- Helper / XPC / 登录项；新 entitlements / TCC 全盘。
- 恐吓文案、「泄漏」、假权限墙。
- Electron / App Store 沙盒。
- 自动杀、常驻通知。
- 第二套斜率、rss 两点差、活动监视器式「内存泄漏」列。
- 给不足态画灰徽标或「—」。

## 风险

| 风险 | 应对 |
| --- | --- |
| 忍不住做成无界全表 ring | Top N=5 硬封顶；跌出即清；验收「列表最多 5 枚」 |
| 按滚动视口可见行或过滤表取 Top 5 | 定义表写死：当前 `ProcessTableSort` + 已采 `rows`；不吃 viewport / `visibleRows` |
| 第二套算法（列表用 rss 两点差） | 只允许 `MemoryGrowthSignal.evaluate`；单测钉「无第二套、阈值不改」 |
| 借密度刀改采样周期 | 范围表写死：同一 `sample()` tick / 同一 period |
| 选中但不在 Top 5 时详情也被关掉 | 详情仍走 `selectedMemorySeries`；验收钉「列表灭、详情三态仍在」 |
| 排序 churn 脏徽标 / 旧 series 残留 | 跌出立刻 drop；单测钉旧 pid 无徽标 |
| N 被改成 10 / 可见行数 | 硬编码 5；传入超 5 只留 5 |
| `ProcessLine` 跨 Tab 漏网 | 按页门控；CPU / 网络 / 磁盘验收「无徽标」 |
| 被读成「就是泄漏」 | 六期文案白名单；验收搜「泄漏」「leak」「危险」 |
| 点击徽标跳详情 | 芯片保持不可点；不做 button / tap gesture |
| Helper / 新 entitlement / GPU | 范围表写死不加 |

## 验收（九期首包）

产品 Must：

- [ ] 内存页进程列表：最多 5 枚「上涨」徽标；只出现在**当前排序 Top 5** 且 `MemoryGrowthSignal == .rising` 的行
- [ ] 文案 / 样式与六期相同：本体「上涨」；hover / accessibility「近期内存持续上涨」；次要文字色；无红闪
- [ ] 样本不足 / 无信号 / 持平 / 不在 Top 5（含选中但不在前 5）：**无徽标**，角标位也不写「—」
- [ ] 详情「内存趋势」三态不回退（上涨 / 不足可见 / none 不占位）；选中 pid 在不在 Top 5 都不影响详情
- [ ] 算法仍是三期 `MemoryGrowthSignal.evaluate`；无第二套增长数学、无 rss 两点差
- [ ] 无新 Sampler 周期；Top 5 series 与今日同一 tick / period；N=5 硬封顶；跌出即清
- [ ] CPU / 网络 / 磁盘列表行无此徽标；GPU 仍灰置
- [ ] 永不写「泄漏」/ leak / 「危险」；无自动杀；无假权限墙

明确不做（本包出现即不合格）：

- [ ] 无 GPU Tab、无新 Tab
- [ ] 无无界全表 series / ring；无滚动视口「可见行」扫描
- [ ] 无点击徽标跳详情
- [ ] 无新 Sampler cadence、无 Helper / XPC、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 无恐吓文案、无「泄漏」

共性：

- [ ] 一二三四五六七八期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏 A / B、详情增长软信号、退出链路）。列表徽标可见性以**本文**为准（覆盖六 / 八期「仅选中行」）
- [ ] 冷启动仍默认内存页
- [ ] UI / 单测：Top5∩rising 亮；Top5 外 / 不足 / none 缺席；排序 churn 丢旧 pid；N 封顶 5；拷贝无「泄漏」
- [ ] 不改公证脚本与 entitlements

## 工期

小：半天～1 天量级——按「有界 Sampler / 模型 + 单测 → 列表接线」拆，不是功能周。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。

---

# Pulse 十期技术设计（首包：菜单栏轻量条 B — 主机已用内存一行）

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

---

# Pulse 十一期技术设计（首包：菜单栏轻量条 B — Top3 点选→打开主窗并选中该进程）

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

---

# Pulse 十二期技术设计（首包：内存进程列表「仅上涨」过滤）

> 一期至十一期正文不改写。九期把列表「上涨」徽标锁在当前排序 Top N=5 ∩ `.rising`，并写死禁止无界全表 ring——**本文只覆盖那条扫描延期**：在内存 Tab 工具栏右侧加一枚轻量开关「仅上涨」，打开后进程表只留下**现有可用**的 `.rising` 行。不新开增长算法、不扫全表、不扩 Sampler ring、不改采样周期。GPU Tab、进程级 GPU、无界全表成长环、恐吓文案 / 「泄漏」、自动杀、菜单栏改动、新徽标样式、新 Tab、Helper / XPC、新 entitlements、Electron 仍不做。

**已锁定**：十二期 = **C（内存列表「仅上涨」过滤）**。谁：在长进程表里扫嫌疑的人。情境：Top5 「上涨」徽标不够用，要把表收成「当前已被现有增长信号标成 `.rising`」的行。成功：打开一枚轻量开关，内存进程表只剩 `.rising` 行；行仍可点选，现成 Quit / Force Quit 可用。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。开关只出现在**内存 Tab 工具栏右侧**，文案 **仅上涨**；ON = 只留现有 `.rising`（当前排序 Top N=5 series / 徽标，最多 **0–5 行**，有界子集，**不是**全机判决）；OFF = 恢复完整表。过滤空态两行：主句 **Top5 暂无上涨**，下一行次要字 **其他进程未做趋势判断**。算法仍是三期 `MemoryGrowthSignal.evaluate`，文案仍用现成「上涨」；**禁止**第二套斜率 / 泄漏算法、禁止 rss 两点差、禁止新徽标样式。名称过滤、表头排序、点行选中、侧栏退出**不得回退**。被本开关滤掉的选中行**不得**留下可操作的陈旧侧栏目标。采样周期不变（前台约 1.5s，后台约 2–3s）；**零新 Sampler period / cadence**，**零新 VM / Mach 轮询**。不新开 entitlements、不拆 Helper / XPC。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：用户 + 产品锁定的十二期 Must（十一期 Top3 点选已合 #35–#37；九期密度已合 #29–#31）；对照现实现（`MemoryGrowthSignal.evaluate` 三态；`MemoryGrowthList.badge` 只认 `topMemorySeries` 上的 `.rising`；Sampler 只为当前内存页排序 Top N=5 维护 `MemoryGrowthTopStore`，`pidLimit = 5`，`seriesLimit = 90`；选中 pid 另有 `selectedMemorySeries` / `ProcessDetail.memorySeries` 服务详情三态，不在 Top 5 时列表不亮；`ProcessRow` 无增长字段；管线是 `rows` → `ProcessNameFilter.apply` → `visibleRows` → `ProcessTableSort.ordered` → `ProcessTablePane.sortedRows`；`List(..., selection: $vm.selectedPid)`；`selectedRow` / `quitSelected` / `forceQuitSelected` 对照完整 `rows`，名称过滤藏行**不**清选中；工具栏右侧已是 `AppFilterField`）。

## 范围（相对一二三四五六七八九十十一期）

| 项 | 一二三四五六七八九十十一期 | 十二期首包 |
| --- | --- | --- |
| 定位 | 九期：列表徽标 = 当前排序 Top N=5 ∩ `.rising`；十一期：菜单栏 Top3 点选开主窗 | **过滤（C）**：内存表加「仅上涨」开关，ON 只投影现有 `.rising` 行 |
| 增长算法 | 三期 `MemoryGrowthSignal.evaluate`；六 / 九期禁止第二套 | **仍只调用这一份**。无 rss 两点差、无新阈值 |
| Sampler series | 九期有界 Top N=5 + 三期选中 pid 详情 ring。禁止无界全表 | **零 Sampler 改动**。不扩 ring、不加第 6 条 series、不改 tick |
| 列表徽标 | 九期：pid ∈ Top 5 且 `.rising` 画「上涨」 | **样式 / 出现条件不改**。过滤不发明第二枚芯片 |
| 详情「内存趋势」 | 三期三态（上涨 / 不足可见 / none 不占位） | **不改** |
| 进程表投影 | `rows` → 名称过滤 → 表头排序 | **做（本刀）**：内存页、开关 ON 时，在名称过滤之后再留 `.rising` |
| 工具栏 | 右侧 `AppFilterField`（「过滤 App」） | **做**：内存 Tab 右侧加轻量开关「仅上涨」。名称过滤保留 |
| 过滤空态 | 名称无匹配：「没有匹配的 App」 | **做**：开关 ON 且无 `.rising` 行 → 主句「Top5 暂无上涨」，下一行次要字「其他进程未做趋势判断」 |
| 选中 / 退出 | `selectedPid`；侧栏读完整 `rows`；名称过滤藏行不清选中 | **名称过滤这条不回退**。本开关把选中行滤掉 → **必须**清 `selectedPid`，侧栏不得留下可点退出 |
| 菜单栏 A / B | 十一期 Top3 可点；十期已用内存行不可点 | **本刀不碰菜单栏** |
| GPU Tab / 进程级 GPU | 灰置 / 不做 | **仍灰置、仍不做** |
| 无界全表 ring | 九期只允许 Top N=5 有界 series | **仍不做**。本刀不碰 series / ring |
| 新 Sampler 周期 | 前台 ~1.5s，后台 ~2–3s | **零新 period / cadence** |
| 新 Tab / 新徽标样式 | 无 | **仍无** |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 / 恐吓文案 | 不做 / 禁止 | **仍禁止**。永不写「泄漏」 |

一二三四五六七八九十十一期验收与公证路径不因本文重开。九期 Top5 徽标、三期详情三态、名称过滤、十一期菜单栏点选不重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

优先**延长**现成列表投影，不要另起 Sampler、不要给 `ProcessRow` 加 `isRising`，也不要第二套增长数学。

- `SwiftUI Views`（内存页 `ProcessTablePane` / 工具栏）←观察→ 同一 `MemoryDashboardVM`
- 开关是 VM 上的一枚轻量布尔（例如 `risingOnlyFilter`），**只在** `selectedPage == .memory` 时参与投影
- 现成管线延长为：`rows` → `ProcessNameFilter.apply` →（内存页且 ON 时）只留现有 `.rising` → `ProcessTableSort.ordered`
- `.rising` 谓词复用 `MemoryGrowthList.badge` / `MemoryGrowthSignal.evaluate(topMemorySeries[pid]) == .rising`——与列表徽标**同一份**输入
- 详情侧栏继续走 `memoryGrowthSlot` / `MemoryGrowthSidebar`——**本刀不改详情三态**
- Sampler 同一 `sample()` tick、同一周期、同一 `MemoryGrowthTopStore`（N=5 硬封顶）
- VM ←订阅快照→ `MemorySampler`（同一 Actor）；过滤**不**调 `sample()`

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询。
- 过滤是只读投影，不是第二条判定，也不是新时序源。
- 不改 `Pulse.entitlements`、不改公证脚本、不改菜单栏 A / B。
- 自身占用仍优先：禁止借「仅上涨」做成无界全表 ring。
- `ProcessLine` 跨 Tab 复用——开关与投影必须按页门控，禁止 CPU / 网络 / 磁盘表被顺手收成「上涨」。
- 增长信号仍不进 `ProcessRow` 采样字段。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `MemoryGrowthSignal.swift`、`MemoryGrowthList`、`MemoryGrowthTopSeries`、`MemoryDashboardVM`、`ProcessTablePane`、`MemorySampler`、`ProcessNameFilter`、九 / 三期 TECH。本刀必须按「已有 / 没有」落笔，**禁止**为了让空态在全表意义上成立再发明一套 series，也**禁止**把「没有 series」标成「非上涨」。

| 现字段 / 调用 | 文件 | 十二期怎么用 |
| --- | --- | --- |
| `MemoryGrowthSignal.evaluate` | `Models/MemoryGrowthSignal.swift` | **原样调用**。`minSamples = 80` / `deltaThreshold = 8 MiB` / `riseFloor = 0.6` 不改。三态：`.insufficient` / `.rising` / `.none` |
| `MemoryGrowthList.badge` | 同上 | **过滤谓词就复用它**（非 nil ⟺ 该行当前是列表「上涨」）。`seriesByPid` 仍是 `topMemorySeries` |
| `MemoryGrowthListCopy` / `MemoryGrowthRisingBadge` | 同上 + `ProcessTablePane` | 文案「上涨」/「近期内存持续上涨」、次要色胶囊 **原样**。不新开样式 |
| `MemoryDashboardVM.topMemorySeries` | `ViewModels/MemoryDashboardVM.swift` + `SampledFrame.topMemorySeries` | **过滤的唯一 per-row 输入**。来自九期有界 Top 5 |
| `MemoryGrowthTopSeries` / `MemoryGrowthTopStore` | `Models/MemoryGrowthTopSeries.swift` + `Sampling/MemorySampler.swift` | **不改**。`pidLimit = 5`；跌出即 drop；不吃名称过滤、不吃本开关 |
| `ProcessDetail.memorySeries` / `selectedMemorySeries` | Sampler 选中 pid ring | **详情唯一输入**。选中但不在 Top 5 时列表本来就不亮——**不要**拿它当第二路过滤源 |
| `ProcessNameFilter` / `visibleRows` / `filter` | `Models/CPUPage.swift` + VM | **保留、先于**上涨投影。名称过滤语义不回退 |
| `ProcessTableSort.ordered` | `Models/CPUPage.swift` | 过滤之后仍走现成表头排序（内存页默认内存降序） |
| `ProcessTablePane.sortedRows` / 空态 | `Views/ProcessTablePane.swift` | 接线吃新投影。开关 ON 且结果空 → 锁定空态句；名称过滤空态句不删 |
| `selectedPid` / `selectedRow` / `quitSelected` | VM + `ProcessDetailSidebar` | 点行仍写 `selectedPid`。`selectedRow` 今日对照完整 `rows`——本开关滤掉选中行时**必须先清选中**，否则侧栏仍可退出已藏行 |
| `AppFilterField` | `Views/SharedUI.swift` + `MemoryDashboardView` 工具栏 `primaryAction` | **保留**。开关另挂内存 Tab 右侧，不要替换搜索框 |
| Sampler `sample()` / `SamplingPace` | `Sampling/MemorySampler.swift`、`SamplingPace.swift` | **不改**。无新字段、不改 tick、不第二路 Mach |

**缺口**：全表绝大多数行**没有** series。九期故意只给当前排序 Top N=5 攒短 ring；`evaluate([])` 是 `.insufficient`，不是 `.none`。这**不是**算法缺口，也**不是**本刀扩采样的理由。

因此本刀：

1. **零 Sampler 改动**（无新字段、不改 tick、不第二路 Mach、**零新 period / cadence**、不把 N 从 5 放开）。
2. **只过滤现有可用的 `.rising`**。ON 表进入的行 = 内存页 + `MemoryGrowthList.badge(...) != nil`，也就是 `pid ∈ topMemorySeries` 且 `evaluate == .rising`。上限 **0–5 行**（九期硬封顶），不是「全机所有正在涨的进程」。
3. **不足 / 无 series / `.none` 都不得标成「非上涨」**。它们只是「当前没有可用的上涨标记」，不进入 ON 表，角标位也不写「—」。
4. 选中但不在 Top 5：详情三态仍可单独评出 `.rising`（三期 ring），列表今日不亮。ON 后该行**不进入**过滤结果——这是九期「选中但不在 Top 5 → 列表不亮」的同一条，不是漏做。此时必须清 `selectedPid`，避免侧栏对已藏行仍可退出。
5. **不要**给 `ProcessRow` 加 `isRising`。**不要**用相邻两帧 `memoryBytes` 冒充上涨。
6. 名称过滤、表头排序、CPU / 网络 / 磁盘投影、菜单栏 Top3（吃完整 `rows`）都不改语义。
7. Top 5 集合**不**跟本开关走（与九期「不吃 `visibleRows`」同一精神）。开关只决定画不画那一行。

#### 覆盖决议（写死，不扩范围）

产品 / 设计已拍板：本刀只过滤**现有可用 `.rising`**——当前内存页排序 Top N=5 有界 series / 九期列表徽标。ON 表最多 **0–5 行**。这是**有界信号子集**，**不是**全机趋势判决。

- 开关标签保持 **仅上涨**。覆盖由空态两行说清，不靠改开关名。
- 过滤空态锁定为两行：主句 **Top5 暂无上涨**；下一行次要字 **其他进程未做趋势判断**。不要写成「当前排序前 5 暂无持续上涨…」整句，也不要用「当前没有持续上涨的进程」这类全机空态句。
- 不为此做全表 ring、第二套增长算法、新 Sampler cadence。若以后产品要「全表仅上涨」，那是另一期，必须先重开九期 N=5。

### 建议工程顺序

信号已经在、徽标已经在、全表 series **没有、也不做**。不需要先开采样 PR。

合并后工程顺序（本文只锁设计；**本 docs PR 不写 Swift**）：

1. **纯过滤 / 投影 + 单测**：`rows` → 名称过滤 →（内存页且 ON）只留 `badge != nil`。钉：ON / OFF；`.rising` 留下；`.insufficient` / `.none` / 无 series 不进且不标成「非上涨」；ON 空表；选中行被滤掉则 `selectedPid` 被清、侧栏不可退出；OFF 恢复全表且名称过滤 / 排序不回退；只走 `evaluate`、无第二套算法。能 `swift test`，不编 App。
2. **工具栏开关 + 空态接线**：内存 Tab 右侧轻量「仅上涨」；ON 空态两行（主句「Top5 暂无上涨」，下一行次要字「其他进程未做趋势判断」）；OFF 走现成名称空态 / 全表。名称过滤、排序、点选、侧栏、CPU / 网络 / 磁盘、菜单栏回归覆盖。
3. **没有硬伤就不开 polish PR**。有硬伤：一个行为一个最小 fix，不要和 GPU / 全表 ring / 新周期捆在一起。

能保持零 Sampler 改动时不要先开采样 PR。不要把本刀和 GPU / 自动杀 / Helper 捆在一起。合并不擅自写代码。

## UI 绑定

结论：只改内存 Tab 的表投影与工具栏右侧一枚开关。徽标视觉锁在六 / 九期，本刀不重开设计。菜单栏不改。

### 工具栏（内存 Tab）

| 表面 | 锁定 | 说明 |
| --- | --- | --- |
| 位置 | 内存 Tab 工具栏**右侧** | 与现成 `AppFilterField` 同侧；不要占 principal Tab 条 |
| 控件 | 轻量开关，标签 **仅上涨** | Toggle / 等价轻控件。不是新列、不是新 Tab |
| ON | 表只留现有 `.rising` 行 | 谓词 = 现成列表徽标非 nil |
| OFF | 完整表（仍受名称过滤 + 表头排序） | 今日行为 |
| 其它 Tab | **不画这枚开关**；投影不生效 | 切到 CPU / 网络 / 磁盘不得被收成「上涨」 |
| 开关状态 | 可随内存页会话保留 | 切走再回来仍 ON 可以；禁止写进 Sampler / 磁盘偏好 |

### 进程表

现成 `List(sortedRows, selection: $vm.selectedPid)` 继续用。ON 时 `sortedRows` 是名称过滤 ∩ 现有 `.rising` 再排序。行仍可点选；徽标仍是九期同一枚「上涨」，不是第二套样式。

| 条件 | 表上的行 |
| --- | --- |
| OFF | 今日：`ProcessNameFilter` + `ProcessTableSort` |
| ON + `evaluate(topMemorySeries[pid]) == .rising` | **留下**（最多 5） |
| ON + `.insufficient`（窗口未满、刚进 Top 5、冷启动） | **不进表**。不是写成「非上涨」 |
| ON + `.none`（窗口够但净增 / 正步不够） | **不进表**。不是写成「非上涨」 |
| ON + pid 不在 `topMemorySeries`（含选中但不在 Top 5） | **不进表**。详情三态不受影响；若该 pid 原是选中 → **清选中** |
| ON + 名称过滤把 rising 行藏掉 | 结果空则走本刀空态；名称过滤本身不改 |
| CPU / 网络 / 磁盘 / GPU | 本开关不存在、不投影 |

切排序 / 名次 churn：跌出 Top 5 的 pid 九期已 drop series，本刀 ON 表同步少那一行，不得残留。新进 Top 5 在不足期间不得因「看起来在涨」混进 ON 表。

### 空态（内存表，采样 / 失败空态仍优先）

| 条件 | 文案 |
| --- | --- |
| 采样中 / 列表失败 / 无进程 | 现成句子，不改 |
| 开关 OFF + 名称无匹配 | **没有匹配的 App**（现成） |
| 开关 ON +（名称过滤 ∩ 现有 `.rising`）为空 | 两行：主句 **Top5 暂无上涨**；下一行次要字 **其他进程未做趋势判断** |
| 两侧栏无选中 | 现成「选择一个进程查看详情」 |

ON 空态主句用默认字重，次要字用次要色。不要复用「没有匹配的 App」，不要写成「当前排序前 5 暂无持续上涨…」整句，也不要写「当前没有持续上涨的进程」（全机误读），也不要在空态上写「泄漏 / 没有泄漏」。不强制加第二颗「关闭仅上涨」按钮；关掉开关就是恢复全表。

### 选中与侧栏

- 留下的行：点选、侧栏、Quit / Force Quit 与今日相同。
- 本开关把当前 `selectedPid` 滤掉（含「选中但不在 Top 5」）：**同一拍** `selectedPid = nil`，`detail` 清掉，侧栏回空态，**禁止**对已藏行 `terminate` / `forceTerminate`。
- 名称过滤把选中行藏掉：今日对照完整 `rows`、侧栏仍可退出——**本刀不改这条**（不回退）。
- 进程离开 `rows`：现成 `tick()` 清选中，不重开。
- 关掉开关：不自动恢复已被本开关清掉的选中。

### 文案默认（可改词不改义）

| 表面 | 锁定用词 | 说明 |
| --- | --- | --- |
| 开关 | **仅上涨** | 产品锁词；与徽标「上涨」同一词根 |
| 徽标本体（不改） | **上涨** | 六 / 九期原词 |
| Hover / accessibility（不改） | **近期内存持续上涨** | 六 / 九期原句 |
| 详情上涨（不改） | **近几分钟持续上涨** | 三期原句 |
| ON 空态 · 主句 | **Top5 暂无上涨** | 默认字重。有界子集，不是全机判决 |
| ON 空态 · 次要字 | **其他进程未做趋势判断** | 主句下一行，次要文字色。见上文覆盖决议 |

禁止出现：泄漏、泄露、leak、危险、告警、异常、中招、需要完全磁盘访问。验收对锁定字符串与实现字符串搜这些词。

### 明确不做（相对本刀）

- GPU Tab；进程级 GPU；新 Tab。
- 无界全表 series / ring；滚动视口「可见行」扫描；把 N 从 5 放开。
- 新徽标样式；第二套斜率；rss 两点差。
- **新 Sampler 采样周期 / cadence**（前台 1.5s、后台 2–3s 不动）。
- 任何菜单栏改动（栏上 A、弹出条 B、Top3 点选）。
- Helper / XPC / 登录项；新 entitlements / TCC 全盘。
- 恐吓文案、「泄漏」、假权限墙、自动杀。
- Electron / App Store 沙盒。
- 给不足 / 无 series 画「非上涨」或「—」。
- 用「当前没有持续上涨的进程」或「当前排序前 5 暂无持续上涨…」整句当空态。
- 用详情 `selectedMemorySeries` 当第二路全表过滤源。
- 名称过滤藏行时顺手改掉今日「侧栏仍可退出」行为。

## 风险

| 风险 | 应对 |
| --- | --- |
| 忍不住做成无界全表 ring / 新周期，好让空态「全机为真」 | 覆盖决议写死：有界子集，最多 0–5 行；空态两行自己说明其他进程未判断；范围表写死零 Sampler |
| 把无 series / `.insufficient` 标成「非上涨」 | 谓词只认 `evaluate == .rising`；不足与缺失都是「无可用标记」 |
| 第二套算法（两点 rss 差） | 只允许 `MemoryGrowthSignal.evaluate`；单测钉无第二套、阈值不改 |
| 选中行被滤掉后侧栏仍可退出 | ON 滤掉 `selectedPid` 必须清选中；单测钉 `quitSelected` 无目标 |
| 用详情 ring 给 Top 5 外的选中行开后门 | 过滤只吃 `topMemorySeries` / `MemoryGrowthList.badge` |
| 名称过滤 / 排序 / 其它 Tab 回退 | 上涨投影按页门控；名称过滤语义不改；回归覆盖 |
| Top 5 集合被开关改写 | 与九期相同：Top 5 吃内存页排序 + 完整 `rows`，不吃本开关 |
| 开关画到 CPU / 网络 / 磁盘或改菜单栏 | UI 绑定写死：仅内存 Tab；菜单栏本刀不碰 |
| 空态复用「没有匹配的 App」或写成全机一句 | ON 空态锁两行：主句「Top5 暂无上涨」+ 次要字「其他进程未做趋势判断」 |
| 恐吓红 / 「泄漏」 | 次要色；验收搜禁词 |
| Helper / 新 entitlement / GPU / 新 Tab | 范围表写死不加 |

## 验收（十二期首包）

产品 Must：

- [ ] 内存 Tab 工具栏右侧有轻量开关 **仅上涨**；其它 Tab 无此开关
- [ ] ON：内存进程表只留当前 `topMemorySeries` 上 `MemoryGrowthSignal == .rising` 的行（与九期「上涨」徽标同一谓词）；行可点选，侧栏现成「退出 / 强制退出」可用
- [ ] OFF：完整表（仍走名称过滤 + 表头排序），与今日一致
- [ ] ON 且无此类行：空态两行，主句恰为 **Top5 暂无上涨**，下一行次要字恰为 **其他进程未做趋势判断**。不得写「当前没有持续上涨的进程」，也不得写成「当前排序前 5 暂无持续上涨…」整句
- [ ] `.insufficient` / `.none` / 无 series：**不进** ON 表，也不标成「非上涨」；角标位不写「—」
- [ ] 选中行被本开关滤掉（含选中但不在 Top 5）：`selectedPid` 已清，侧栏空态，不可对已藏行退出 / 强退
- [ ] 名称过滤、表头排序、点选、侧栏退出、九期最多 5 枚「上涨」徽标不回退
- [ ] 算法仍是三期 `MemoryGrowthSignal.evaluate`；无第二套增长数学、无 rss 两点差、无新徽标样式
- [ ] 无新 Sampler 周期 / 字段 / 第二路 Mach；N=5 硬封顶不放开
- [ ] 永不写「泄漏」/ leak / 「危险」；无自动杀；无假权限墙
- [ ] 菜单栏 A / B / Top3 点选不因本刀改动

明确不做（本包出现即不合格）：

- [ ] 无 GPU Tab、无进程级 GPU、无新 Tab
- [ ] 无无界全表 series / ring；无新 Sampler cadence
- [ ] 无新徽标样式、无第二套算法
- [ ] 无菜单栏改动
- [ ] 无 Helper / XPC / 登录项、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 无恐吓文案、无「泄漏」、无自动杀
- [ ] 无把不足 / 无信号误标成非上涨

共性：

- [ ] 一二三四五六七八九十十一期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏 A / 七期 B / 十期已用内存 / 十一期 Top3 点选、详情增长软信号、九期 Top5∩rising 徽标、退出链路、名称过滤）
- [ ] 冷启动仍默认内存页
- [ ] UI / 单测：ON / OFF；`.rising` 留下；不足 / none / 无 series 不进；ON 空态两行（主句「Top5 暂无上涨」+ 次要字「其他进程未做趋势判断」）；选中被滤掉则清选中；无第二套算法；拷贝无「泄漏」
- [ ] 不改公证脚本与 entitlements

## 工期

小：约 **0.5–1 天**——按「纯过滤 / 投影 + 单测 → 开关 + 空态接线」拆，**不是**更大的采样功能，不要按 Sampler 改造估。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。本 docs 分支**不写 Swift**。

---

# Pulse 十三期技术设计（首包：采样失败手动重试合流）

> 一期至十二期正文不改写。一期写明失败进「采样中 / 失败」态、不假装 0；各资源页失败空态已有次按钮「重新采样」，但 `retrySampling` 会立即清态并另开 unstructured `Task`，与 `loopTask` 的 `SamplingClock` 周期 tick 重叠——**本文只覆盖那条调度缺口**：失败空态冷静重试，手动与定时请求共享同一单在途 sample。不改菜单栏、不开 GPU / 全表 ring / 新 Tab / 新 cadence / 新权限 / 新算法 / 恐吓文案 / 额外持久化。不新增自动定时重试、指数退避或进度条。已有周期循环是产品既有行为，不暗删、不偷偷变间隔。

**已锁定**：十三期 = **采样失败手动重试（合流）**。谁：主窗已落在采样失败冷静空态的人。情境：点次按钮想再采一帧，不要骨架闪一下、不要和后台周期 tick 打成两趟。成功：空态仍显示失败说明（主句不动；指向按钮的「重新采样」改为 **重试**，内存总览副句精确为 **这轮采样没有回来，点重试再试。**），下面次按钮 **重试**；点后同一空态出现 **正在重试…** 且禁止重入；成功回现表；仍失败回同一空态、按钮恢复。说明词与次按钮统一「重试」，**不再**把「重新采样」当失败空态按钮术语。这是十三期已锁范围，不是另核、不是文档以后再改。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`；Sampler / Top5 series / 选中生命周期**不改**。前台 **1.5s**、后台 **3s** 常值不变（`SamplingPace`）。零新 timer、零新 VM、零第二路 Mach。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：用户 + 产品锁定的十三期 Must（十二期② 仅上涨开关已合 #42 / `27482ad`）；对照现实现（`MemoryDashboardVM.start` / `loopTask` / `SamplingClock` / `retrySampling` / `tick`；`MemorySampler.sample()` 为 Actor **同步**方法；`ProcessTablePane` 与各 Overview 失败空态均调 `retrySampling`；`SamplingCore` 能测 `SamplingPace`，测不到 VM）。

## 范围（相对一二三四五六七八九十十一十二期）

| 项 | 一二三四五六七八九十十一十二期 | 十三期首包 |
| --- | --- | --- |
| 定位 | 失败空态有「重新采样」；`retrySampling` 立即清 `loadState` / 快照 / 行 / 历史并另开 `Task tick` | **合流**：同一单在途 sample；空态不闪；旧结果不得盖新状态 |
| 采样周期 | 前台 1.5s、后台 3s；`SamplingClock` 400ms wake 只为 `setForeground` | **常值不改**。不新开 cadence、不新开 timer、不暗删 loop |
| Sampler | 单 Actor、`sample()` 同步返回 `Result` | **零 Sampler 改动**。不取消、不拆内部任务、不以 Actor 串行冒充会话时序 |
| VM 生命周期 | 单 `loopTask` + `started`；`setForeground` 只改 step | **loop 保留**。去掉 retry 的第二路 unstructured `Task` |
| 失败空态 | `loadState == .failed`（及进程表 `processListFailed`）走 `AppEmptyState` +「重新采样」 | **做**：主句不动；说明里指向按钮的「重新采样」→ **重试**（如「点重试再试」）；次按钮 **重试**；重试中 **正在重试…** + 禁重入。非按钮指称不机械替换 |
| 菜单栏 A / B | 失败灰点 /「暂时读不到」 | **本刀不碰**。重试中 `samplingFailed` 仍真，灰点不回绿 |
| 增长 / 仅上涨 / Top5 | 九 / 十二期有界投影 | **不改**。重试点击不双清 `topMemorySeries` / 误清 `selectedPid` |
| GPU / 新 Tab / 全表 ring | 灰置 / 无 / 禁止 | **仍禁止** |
| 自动重试 / 退避 / 进度条 | 无（只有既有周期 loop） | **不新增**。既有 loop 照跑，不是本刀发明的「失败后自动再试」 |
| Helper / entitlements / Electron | 无 | **仍无** |
| 恐吓文案 | 禁止 | **仍禁止** |

一二三四五六七八九十十一十二期验收与公证路径不因本文重开。前期 TECH 正文不改写；主窗失败空态的按钮术语与指向按钮的说明指称以**本文**为准（覆盖「重新采样」按钮及「点重新采样再试」这类指称）。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

本刀落在 **纯 Swift 请求门闩**（与 `SamplingClock` / `SamplingSession` / `SamplingPace` 同层），**不是**新 Actor、不是新 timer、不是 VM 上一个没合流的 `isRetrying` 布尔。

- 现成 `loopTask` **仍是唯一**调用 `sampler.sample()` 的消费者。手动重试只向门闩登记「请现在采」，必要时打断当前 `Task.sleep`，**不**另开 `Task { await tick() }`
- `MemorySampler` 仍是同一 Actor、同一 `sample()`；增长 Top5、选中 pid ring 仍由这一趟写入
- Views 失败空态仍观察同一 VM；重试中 chrome 是门闩状态的投影，不是第二条采样通道
- 菜单栏继续只读 `snapshot` / `samplingFailed`，不调 `sample()`、不画「正在重试…」

约束：

- 快照仍是不可变 `struct`；采样在后台 Actor，主线程只读。不新开第二套 VM、不新开第二路 `proc_listpids` / Mach。
- 不改 `Pulse.entitlements`、不改公证脚本、不改 `SamplingPace` 1.5s / 3s、不改 `SamplingClock.wakeSliceNanoseconds` 的职责（仍只为前后台）。
- 自身占用仍优先：重试不得把在途 sample 加成两趟。
- 增长信号、仅上涨过滤、菜单栏 B **本刀不碰**。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `MemoryDashboardVM`、`SamplingPace.swift`、`MemorySampler.sample()`、`ProcessTablePane`、各 Overview、`Package.swift` 的 SamplingCore 切片。本刀必须按「已有 / 没有」落笔，**禁止**把 Actor 串行读成「已经单在途」，也**禁止**取消 `sample()` 调用方 Task 后假定结果不会回来。

| 现字段 / 调用 | 文件 | 十三期怎么用 |
| --- | --- | --- |
| `loopTask` + `SamplingClock.plan` / `recordSleep` | `MemoryDashboardVM.start` | **保留为唯一消费者**。`plan.sample` 为真才 `tick`；sleep 可被手动重试打断 |
| `SamplingPace` 1.5s / 3s | `Sampling/SamplingPace.swift` | **常值不改**。前后台只换 step，不派生自动重试 |
| `SamplingClock` 400ms wake | 同上 | **仍只服务 `setForeground`**。重试立即采靠打断 sleep + `pendingImmediate`，不拿 wakeSlice 当重试延迟 |
| `SamplingSession.setForeground` | 同上 + `PulseAppDelegate.applyPace` | **不改**。关窗 / 后台只拉长间隔 |
| `retrySampling()` | VM | **今日缺陷**：`loadState = .sampling` 切骨架；清 snapshot / rows / 四条 history / `samplingFailed`；`Task { await tick() }` 与 loop 重叠。十三期改成只 `gate.requestManualRetry()`，不清态、不另开 Task |
| `tick()` | VM | 仍 `await sampler.sample()` 后按今日成功 / 失败规则写回。**加门闩 flight 承认**：过期结果丢弃。成功选中逻辑原样（pid 不在 `rows` 才清） |
| `MemorySampler.sample()` | `Sampling/MemorySampler.swift` | Actor **同步**方法，无内部 Task、无取消令牌。`await sample()` 只是 hop 进 Actor；调用方 Task 被取消**停不了**已开始的 `sample()`。**零改动** |
| Actor 隔离 | 同上 | 两个 `await sample()` 会**排队各跑一整趟**，两份 `Result` 都能回到 MainActor 写 VM。串行 ≠ 单在途，更 ≠ 会话时序 |
| `LoadState` | `MemoryModels` | 仍 `sampling \| ready \| failed`。**不**加 `.retrying`（会把 Overview 切走失败空态）。重试中保持 `.failed` |
| `AppEmptyState` | `Views/SharedUI.swift` | 今日按钮永远可点、无次要行。本刀加：禁重入 + 可选「正在重试…」次要行。**不用 `ProgressView`**。`retryTitle` 与含按钮指称的 message 按锁词表 |
| 失败空态调用 | Overview / CPU / Network / Disk Overview + `ProcessTablePane` 内存失败 / 进程列表失败 / 资源表失败 | **七处都走同一 `retrySampling`**。同一门闩、同一 chrome、**同一「重试」锁词**，不按 Tab 分叉 |
| `CPUPageCopy` / `NetworkPageCopy` / `DiskPageCopy` | `Models/*Page.swift`（已在 SamplingCore） | `retry` → **重试**；`failureMessage` 里「点重新采样再试」→ **点重试再试**。`failureTitle` 不动。内存总览 / 进程列表失败是 Views 内联，接线刀一并改 |
| `MemoryTablePhaseResolver` / `CPUPagePhaseResolver` | `MemoryTablePhase` / `CPUPage` | `loadState == .sampling` 才骨架。重试中必须保持 `.failed` / `.processListFailed`，否则闪骨架 |
| SamplingCore | `Package.swift` | VM / Sampler / Views **排除**。门闩必须 Darwin-free，才能 `swift test` |

**缺口（已核，不是采样算法缺口）**：

1. **双调用方**：loop 的 `tick` 与 `retrySampling` 的 unstructured `Task` 都能 `await sample()` 再 `apply`。旧帧可以晚于新帧写上 VM。
2. **取消语义对不上**：`sample()` 没有可取消的内部任务。取消 loop / retry Task 之后 `sample()` 仍会跑完；今日 `tick` 也不看 `Task.isCancelled` 或代次。**不要**拆活 Sampler 后假定 result 停止。
3. **清态闪烁**：按钮一拍把 `loadState` 打成 `.sampling` 并 `snapshot = nil` / `rows = []` / 历史 `reset`。失败空态被骨架替换；`selectedPid` 虽未直接 nil，行被清空后选择语义已丢。失败帧本身已经是空表——再清一次没有信息增量，只有闪。
4. **Clock 无提前唤醒**：手动 tick 不把 `elapsed` 置到期，也不打断 sleep。loop 醒过来仍可能再 `plan.sample == true`，叠第二趟。

因此本刀：

1. **零 Sampler 改动**（无新字段、不改 `sample()`、不第二路 Mach、**零新 period / cadence**）。
2. **单消费者 loop + 请求门闩**。所有「该采了」（时钟到期、首次 `needsInitialSample`、手动立即）都进同一门闩；已在途则只加入、不 `begin` 第二次。
3. **Flight token 只服务在途这一趟的结果承认**，不是给 VM 每个字段打全局世代，也不是新 timer。
4. **UI 不靠假布尔**：`isRetrying` 若暴露，必须是门闩 `retrying` 的投影；禁止 VM 另写一个与在途无关的 flag。
5. 重试点击**不清** snapshot / rows / 历史 / `selectedPid` / `detail` / `topMemorySeries` / `loadState`。

### 为何是门闩，而不是全局世代 / 新 timer / select 输入

| 候选 | 为何不作为本刀主轴 |
| --- | --- |
| 全局世代（VM 每个 @Published 一个 gen） | 过重。需要防的只是「另一趟 sample 的 Result 写回」。Sampler 内部 ring 已由单 `sample()` 串行推进；选中 / Top5 清语义仍走今日 `tick` 成功支。门闩在 **begin 时发一个 `UInt64` flight id、complete 时对上才 apply** 就够 |
| 新 timer / 失败后自动再试 / 指数退避 | 产品禁止。1.5s / 3s 已有；再开 timer 会变成第二 cadence |
| Go 式 `select` 输入 | Swift 没有廉价的 sleep-vs-retry select。等价保障：**单消费者 loop** + `pendingImmediate` + 打断当前 `Task.sleep`。两个输入（时钟到期、手动）在 `plan` 处收束；在途时两者都变成 join |
| 只加 `isRetrying` | 禁。按钮禁用解决不了双 `tick` 写回 |
| 取消 / 拆 Sampler 内部 Task | `sample()` 根本没有内部 Task。取消调用方不能当会话边界 |
| 依赖 Actor 串行 | 两趟都会跑完，两份结果都会回来 |

Flight id **不是**「全局世代计数」：它只在 `beginSample` 时 +1，只活在这一趟 in-flight 上，complete / 丢弃后回到 idle。首次启动的 `needsInitialSample` 仍走 Clock，origin 为节奏而非手动，**不**显示「正在重试…」。

### 门闩契约（可验收，Linux 可测）

建议名：`SamplingRequestGate`（可与 Clock 同文件或紧邻的 Darwin-free 文件）。形状可改，语义钉住：

| 输入 | 行为 |
| --- | --- |
| `requestManualRetry()` 且 idle | `retrying = true`，`pendingImmediate = true`；调用方打断当前 sleep。**不**清 VM 态。连点幂等 |
| `requestManualRetry()` 且 in-flight | **join**：`retrying = true`，**不** `begin` 第二次，**不**把 complete 后再排一趟。连点仍一 in-flight |
| `plan(clock, step)` 且 in-flight | `sample == false`（loop 此时本就堵在 `await tick`，不得再入） |
| `plan` 且 idle 且（Clock 到期 **或** `pendingImmediate`） | `begin`：发出 `flightId`，清 `pendingImmediate`，Clock 按今日到期规则把 `elapsed` 归零（与现 `plan` 到期支相同，故下一间隔仍是 1.5s / 3s） |
| `plan` 且 idle 且未到期 | `sample == false`，sleep 仍取 `min(wakeSlice, remain)`——既有节奏 |
| `accept(flightId)` | id 对上当前 in-flight → 允许 VM apply，然后 idle、`retrying = false`。不对 → **丢弃**，VM 一字不写 |
| `setForeground` | 只改 `SamplingSession.step`。门闩**不**因此 `begin`，不发明失败自动重试 |
| 首次 `needsInitialSample` | 照旧立即 `begin`；`retrying` 仍 false（冷启动骨架不是重试空态） |

打断 sleep：取消**这一段** `Task.sleep`（或等价 wait），不是取消 `loopTask`，更不是取消 `sample()`。被打断的那截剩余时间**不要** `recordSleep` 成「又到期了」。`begin` 已经把 `elapsed` 归零；下一拍完整 step。

Quit / 未完成 Task：取消 `loopTask` 后，已 hop 进 Actor 的 `sample()` 仍可能返回；`tick` 必须 `accept(flightId)` 失败或 `Task.isCancelled` / `self == nil` 则不 apply。不要泄漏第二条 retry Task（今日的 unstructured `Task` 正是泄漏源，本刀删它）。

### VM / UI 契约（逐项）

`retrySampling()` 只允许做：`gate.requestManualRetry()` + 打断 sleep。下面「点击时」= 这一拍。

| 字段 | 点击时 | `accept` 成功（今日 `tick` 成功支） | `accept` 失败（今日失败支） | 过期 / 取消的 Result |
| --- | --- | --- | --- | --- |
| `loadState` | **保持 `.failed`**（进程列表失败空态保持今日 `.ready` + `processListFailed`，不要改打成 `.sampling`） | `.ready` | snapshot 仍 nil → `.failed`；有 snapshot → 今日一样保持 `.ready` | 不写 |
| `samplingFailed` | **不改**（失败空态保持真，菜单栏继续灰点） | `false` | `true` | 不写 |
| snapshot / 各 host 速率 / rows / `processListFailed` | **不清** | 按帧写入（与今日相同） | **不清**（失败空态本来就是空表） | 不写 |
| `usageHistory` / cpu / network / disk 历史 | **不 `reset` / 不 `record(nil)`** | 按今日成功支 `record` | **不改** | 不写 |
| `topMemorySeries` | **不清** | 按帧覆盖 | **不清** | 不写 |
| `selectedPid` / `detail` | **不直接 nil**。成功支沿用今日：pid 不在新 `rows` 才清；试采期间合理选中保留是工程前提，不新开选择 API | 今日逻辑 | **不额外清** | 不写 |
| `retrying`（门闩投影） | `true`，按钮锁定 | `false` | `false`，按钮恢复，仍可再点 | 不把 UI 卡死在重试中：丢弃时若已 idle 则 `retrying == false` |

按钮锁定时机：`requestManualRetry()` **当下**（join 或即将 begin 都算承认手动意图），不必等 `sample()` hop 进 Actor。这才能禁止重入、并在 sleep 打断前就显示「正在重试…」。

`begin` 与结果代次：只有 `plan` 里那一次 `begin` 发 `flightId`；`tick(flightId)` 拿到 `Result` 后先 `accept`，再 apply。手动 join 的那一趟用的是**已经 begin 的节奏 flight**——这正是「不发起第二次」：结果就是这一趟，旧周期没有第二份回写。

## 建议工程顺序

门闩可测、VM 在 SamplingCore 外、Sampler 取消语义已核完。不要先开 Sampler PR。

合并后工程顺序（本文只锁设计；**本 docs PR 不写 Swift**）：

1. **门闩 + Clock 到期/立即 + 重试 chrome 谓词 + `swift test`**：`SamplingRequestGate` 与（若需要）Clock 的「立即到期」输入；`SamplingRetryChrome`（按钮 **重试**、指向按钮的说明 **点重试再试**、次要行「正在重试…」、`retrying` 时按钮禁用、失败相保持 `.failed` 而非 `.sampling`）。钉文末矩阵 1–8 能在 Linux 钉的部分。`Package.swift` 列入 SamplingCore。零 Sampler、零 AppKit。
2. **VM 单消费者接线 + 七处空态**：`retrySampling` 去掉清态与 unstructured `Task`；loop 用门闩 `plan` / `accept`；sleep 可打断；`AppEmptyState` 加禁用 + 次要行（**无 ProgressView**）；Overview ×4 与 `ProcessTablePane` 三处失败 / 进程列表失败走同一模型与**同一锁词**。成功选中逻辑不重开。

两刀都是小额可审：① 纯调度、Linux 可测；② 只把唯一消费者接到现成 loop / 现成空态。不一步塞进 Sampler。没有硬伤就不开第三条 polish PR。不要和 GPU / 全表 ring / 新周期捆在一起。合并不擅自写代码。

## UI 绑定

结论：只改**已有失败空态**的次按钮、指向按钮的说明指称、以及重试中次要行。各页失败**主句**不动。菜单栏不改。不用 ProgressView / spinner。

### 文案（已锁，工程刀就要改，不是以后另核）

说明词与次按钮统一 **重试**。失败空态不再使用「重新采样」当按钮术语。

只改**指向次按钮的指称**。自然中文，不造第二套词。

| 改 | 不改 |
| --- | --- |
| 次按钮标题「重新采样」→ **重试** | 失败主句（title）一字不改 |
| 副句里「点重新采样再试」→ **点重试再试**（其余字词、标点不动） | 「这轮采样没有回来」等副句其余字 |
| | 磁盘主句「暂时读不到磁盘数据，稍后重试」——这里的「重试」不是按钮标签，**不改** |
| | 「正在采样…」「采样中…」冷启动骨架；菜单栏「暂时读不到」 |
| | 非按钮指称的动作表述（不要见「重新采样」就整句替换） |
| | 函数名 `retrySampling` 等代码标识；一期至十二期 TECH 正文 |

精确锁定（接线与单测钉这些字符串）：

| 表面 | 主句（不动） | 副句（十三期） | 按钮 |
| --- | --- | --- | --- |
| 内存总览 | 暂时读不到内存数据 | **这轮采样没有回来，点重试再试。** | **重试** |
| CPU 总览 / 表失败 | 暂时读不到 CPU 数据 | 这轮采样没有回来，点重试再试。 | 重试 |
| 网络总览 / 表失败 | 暂时读不到网络数据 | 这轮采样没有回来，点重试再试。 | 重试 |
| 磁盘总览 / 表失败 | 暂时读不到磁盘数据，稍后重试 | 这轮采样没有回来，点重试再试。 | 重试 |
| 内存表 `.failed` | 进程列表还没有数据 | 总览还没回来，列表先空着。（无按钮指称，副句不动） | 重试 |
| 内存表 `.processListFailed` | 暂时无法列出进程 | **这轮没读到进程列表，点重试再试。** | 重试 |

重试中次要行仍是 **正在重试…**。`*PageCopy.retry` / `failureMessage` 与 `ProcessTablePane` 内联标题按上表改；这是本包范围。

### 调用点（全部遵循同一模型，不新增入口）

| 表面 | 今日 | 十三期 |
| --- | --- | --- |
| 内存总览 `OverviewSection.failureBody` | 「暂时读不到内存数据」+「这轮采样没有回来，点重新采样再试。」+「重新采样」 | 主句不动；副句 **这轮采样没有回来，点重试再试。**；按钮 **重试**；重试中同一空态 + **正在重试…** + 按钮禁用 |
| CPU / 网络 / 磁盘总览 failureBody | 各页 `*PageCopy.failureTitle` / `failureMessage` +「重新采样」 | 主句不动（磁盘主句「稍后重试」保留）；副句同上「点重试再试」；按钮 **重试** |
| 内存表 `.failed` | 「进程列表还没有数据」+「总览还没回来，列表先空着。」+「重新采样」 | 主句 / 副句不动（无按钮指称）；按钮 **重试** |
| 内存表 `.processListFailed` | 「暂时无法列出进程」+「这轮没读到进程列表，点重新采样再试。」+「重新采样」 | 主句不动；副句 **这轮没读到进程列表，点重试再试。**；按钮 **重试**。今日已有入口，不是新 feature |
| CPU / 网络 / 磁盘表 `.failed` | 各页失败文案 +「重新采样」 | 与对应总览同一锁词 |
| 冷启动 `.sampling` 骨架 | 「采样中…」/「正在采样…」 | **不改**。不是重试空态，不出现「正在重试…」 |
| 就绪表 / 名称过滤空 / 仅上涨空 | 无重试按钮 | **不改** |
| 菜单栏 | 灰点 +「暂时读不到」 | **不改**。重试中仍 `samplingFailed == true` |

重试中：**不要**切骨架、不要 `ProgressView`、不要进度条、不要把失败说明换成「重试中」。主句仍在；副句按上表（已改指称处不再出现「重新采样」）；「正在重试…」是按钮附近一条次要色短句（具体在按钮上 / 下由实现贴在 `AppEmptyState` 里，不新开第三种空态组件）。

有 snapshot 之后的后续 `sample()` 失败：今日 `tick` 只把 `samplingFailed = true`、`loadState` 保持 `.ready`（主窗仍显示旧表）。**本刀不把这条扩成新的失败空态**。既有周期 loop 会按 1.5s / 3s 再采——这是既有行为，不是新增自动重试。

### 明确不做（相对本刀）

- GPU Tab；新 Tab；全表 ring；新 Sampler cadence。
- 改菜单栏 A / B / Top3。
- 新权限 / Helper / XPC / 持久化重试状态。
- 指数退避、失败后额外定时器、ProgressView / spinner / 进度条。
- 恐吓文案、「泄漏」、假权限墙。
- 暗删 `loopTask` 或把 1.5s / 3s 改掉。
- 取消 / 拆 `MemorySampler.sample()` 内部工作。
- 仅加 `isRetrying` 却仍让 retry `Task` 与 loop 双 `tick`。
- 把已有失败说明主句改写成新文案包；见「重新采样」就整句机械替换（非按钮指称不动）。
- 失败空态再造「重新采样」按钮术语，或把说明指称与按钮拆成两套词。

## 风险

| 风险 | 应对 |
| --- | --- |
| Actor 串行被当成已经单在途 | 上文写死：两趟都会跑完；必须门闩 begin/accept |
| 取消 retry Task 后旧 `tick` 仍 apply | 删 unstructured Task；唯一消费者 + `accept(flightId)` |
| 点击清态闪骨架 / 丢选择 | 点击不清；`loadState` 保持失败相；选中只走今日成功支 |
| 打断 sleep 却 `recordSleep` 剩余时间导致立刻又到期 | 打断不记剩余；`begin` 归零 `elapsed`；下一间隔完整 step |
| 用 400ms wakeSlice 冒充「立即」 | 契约写死打断 sleep；wakeSlice 仍只为前后台 |
| 加新 timer / 失败自动再试 | 范围表禁止；既有 loop 不是本刀发明 |
| 菜单栏闪绿或出现重试文案 | 点击不把 `samplingFailed` 打假；B 不接线 |
| 双清历史 / 误清 `selectedPid` | 单 apply；点击路径禁止 reset / nil |
| 漏改按钮指称，或把非指称的「重新采样」动作句一并改掉 | 只改指向按钮的「重新采样」→「重试」；主句与其余字词不动；磁盘主句「稍后重试」不是按钮词 |
| Helper / GPU / 新 cadence | 范围表写死不加 |

## 验收（十三期首包）

产品 Must：

- [ ] 失败空态主句仍是今日句子；指向按钮的说明改为 **点重试再试**（内存总览副句恰为 **这轮采样没有回来，点重试再试。**）；次按钮 **重试**；点击后同一空态出现 **正在重试…** 且按钮不可重入。失败空态不再把「重新采样」当按钮术语
- [ ] 手动成功 → `loadState == .ready`，表回现；手动失败 → 同一空态、按钮恢复、可再点
- [ ] 手动与节奏共享**同一单在途** `sample()`；旧结果不能覆盖新状态
- [ ] 前台 1.5s、后台 3s 常值不变；不新开自动定时重试 / 退避 / 进度条；既有 loop 不暗删
- [ ] 重试点击不清 snapshot / rows / 历史 / `selectedPid` / `detail` / `topMemorySeries`，不切 `.sampling` 骨架
- [ ] Sampler Actor、VM、Top5、菜单栏不因本刀改语义
- [ ] 永不写「泄漏」/ leak / 「危险」；无假权限墙

测试矩阵（实现 PR 必须覆盖能 Linux 测的项；VM / GUI 标 Mac 剩余）：

1. 空闲失败态点重试：只 `begin` 一次；完成后下一间隔仍是 1.5s（前台）或 3s（后台），不是新 cadence
2. 节奏采样已 in-flight（测试里手控延迟未 `accept`）再点重试：不第二次 `begin`，`retrying == true`（join）；这一趟 flight 结算（成功或失败）只 apply 一次。再喂一个过期 / 不同 `flightId` 的 Result，`accept` 拒绝，不得第二次写 VM（这就是「旧周期回写」）
3. Clock 仍在 sleep / `elapsed` 未到期时点重试：下一次 `plan` 立即 `begin`，不等剩余 1.5s / 3s
4. 连点：仍一 in-flight；`requestManualRetry` 幂等
5. 手动失败：`accept` 失败支 → 仍 failed 相、锁词说明（点重试再试）、`retrying == false`、可再点
6. 手动成功：`accept` 成功支 → ready（VM 接线刀验收 apply；门闩刀验收 accept 后 idle）
7. `setForeground` 只换 step；门闩不因此多 `begin`，不新造自动重试
8. 首次 `needsInitialSample` 不是 retrying；`accept` 前取消 / quit：Result 丢弃；无第二条 Task 泄漏
9. 手动与周期同拍：历史 / `selectedPid` 只走一次成功支，不双 `reset`、不误 nil
10. 当前失败空态 / 其它 Tab 失败空态同一模型与同一锁词（按钮「重试」、有指称的副句「点重试再试」）；菜单栏 A / B、仅上涨、Top5 徽标不回退

明确不做（本包出现即不合格）：

- [ ] 无 GPU Tab、无新 Tab、无全表 ring
- [ ] 无新 Sampler cadence / 新 timer / 指数退避 / ProgressView
- [ ] 无菜单栏改动
- [ ] 无 Helper / XPC / 新 entitlements / 额外持久化
- [ ] 无恐吓文案、无「泄漏」、无自动杀
- [ ] 无「只加 isRetrying、仍双 tick」
- [ ] 无拆 Sampler 内部任务当取消
- [ ] 无失败空态「重新采样」按钮术语；无漏改「点重新采样再试」指称；无机械改非按钮指称

共性：

- [ ] 一二三四五六七八九十十一十二期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏 A / B / Top3 点选、详情增长、九期徽标、十二期仅上涨、退出链路）。失败空态按钮术语与指向按钮的说明指称以**本文**为准（覆盖「重新采样」按钮及「点重新采样再试」；四 / 八期 TECH 正文不改写）
- [ ] 冷启动仍默认内存页、仍先骨架再第一帧（不是重试 chrome）
- [ ] Linux：`swift test` 跑门闩 / Clock / chrome 谓词，以及已在 SamplingCore 的 `*PageCopy.retry` / `failureMessage` 锁词；**不声称 VM 测试或 Xcode GUI 已完成**
- [ ] 不改公证脚本与 entitlements

### Linux 可测 vs Mac 剩余

`Package.swift` 的 SamplingCore **排除** `ViewModels/`、`MemorySampler`、Views。门闩必须无 Darwin / 无 AppKit，才能在 Linux CI 实跑矩阵 1–8 的调度部分（用测试替身记录 `begin` 次数、延迟 `accept`、喂过期 `flightId`）。`CPUPageCopy` / `NetworkPageCopy` / `DiskPageCopy` 已在 SamplingCore：实现刀把 `retry` / `failureMessage` 锁词钉进现有 `*PageTests`。内存总览与进程列表失败内联在 Views，标接线刀 / Mac。

本 docs PR **不跑**、也不声称：

- `MemoryDashboardVM` 实例测试（不在 SamplingCore）
- Xcode GUI / 主窗点按钮
- 实机 `HostMemoryReader` 失败

Mac 冒烟（实现合并后、本机；不挡本文档验收）：

- 伪造 / 制造一帧 host 失败，落到失败空态：主句仍在；内存总览副句恰为 **这轮采样没有回来，点重试再试。**；按钮 **重试**；点后出现「正在重试…」、按钮禁用、无骨架闪；空态不再出现「重新采样」按钮术语
- 成功回表；再失败回同一空态
- 重试过程中等待下一周期：不得看到表闪两次或选中无故丢失
- 菜单栏灰点在重试中保持灰，弹出条不出现「正在重试…」
- 过期结果乱序：优先信 Linux 门闩单测；Mac 上若无替身 Sampler，只做「点重试时 loop 仍在跑」的观感确认，不宣称已注入乱序

## 工期

小：按「门闩 + 单测 → VM / 空态接线」拆两个工程 PR，天级，不是周级。调度本身纯 Swift；不要按 Sampler 改造估。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。本 docs 分支**不写 Swift**。

---

# Pulse 十四期技术设计（首包：菜单栏 Top3 与主窗内存排序对齐）

> 一期至十三期正文不改写。七 / 十一期把菜单栏 B Top3 锁成「已采 `rows` 内存降序前 3 + 点选落内存页同 pid」；十二期名称过滤 / 「仅上涨」只收主窗表；九期 Top5 已跟内存页 `ProcessTableSort`——**本文只覆盖那条投影缺口**：主窗内存页改成 CPU / 线程（及现成名称）排序后，菜单栏 Top3 按**同一顺序**取前三。不改 Sampler / 采样频率，不新开排序算法，不改菜单栏布局 / 文案 / 主机压力与已用信息行，不重开十三期重试，不做磁盘趋势 / GPU / 新 Tab / 全表 ring，不改十二期过滤 / 增长算法 / TopN=5，不改主窗排序按钮与默认内存降序，不另加持久化排序设置，不重做 `MenuBarPopoverSnapshot`、不引入第二个状态源。

**已锁定**：十四期 = **菜单栏 Top3 对齐主窗内存排序**。谁：先扫菜单栏的人。情境：主窗内存页已经按 CPU / 线程等列重排，弹出条仍按内存大小取前三，对不上。成功：菜单栏最多 3 行按**同一 comparator / order**显示未过滤 `rows` 的前三；行仍只画 pid 身份 + 名称 + `memoryBytes`；点选仍走十一期 `MenuBarPopoverTap`（dismiss → `selectPidIfPresent` → `focusMemoryPage`）。主窗名称过滤与十二期「仅上涨」**不**灌入菜单栏。失败 / 空态沿用。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`；弹出条**不**调 `sample()`。文案冷静；永不写「危急 / 泄漏 / 危险」。

来源：用户 + 主控锁定的十四期 Must（十三期①#45 / ②#46 已合，基准 `e3fc8b7198ba68a986903fb94b692cd2e961a0a3`）；对照现实现（`ProcessTableSort` 在 `Models/CPUPage.swift`；`MemoryDashboardVM.tableSort` = `navigation.sort`；`ProcessTablePane.sortedRows = vm.tableSort.ordered(vm.visibleRows)`；`setMemoryPageSort` 在 `MemorySampler`，只经 `publishMemoryPageSort()` 在 `selectedPage == .memory` 时触达；`MenuBarPopoverSnapshot.topProcesses` 仍硬编码 `memoryBytes` desc + pid 升序；`menuBarPopover` 已吃完整 `rows`，不吃 `visibleRows`）。

## 范围（相对一二三四五六七八九十十一十二十三期）

| 项 | 一二三四五六七八九十十一十二十三期 | 十四期首包 |
| --- | --- | --- |
| 定位 | 七 / 十一期：Top3 = 已采 `rows` **内存降序**前 3，可点选落内存页 | **投影对齐**：Top3 = 主窗**内存页**当前 `ProcessTableSort` 对未过滤 `rows` 排序后的 `prefix(3)` |
| 菜单栏外观 A / B 槽位 | 栏上色点；压力 + 已用 + Top3 +「打开 Pulse」 | **布局 / 文案 / 主机行不改**。Top3 仍名称 + 内存字节，不改写成 CPU / 线程 / PID 列 |
| Top3 顺序 | 硬编码内存降序 + pid 升序次键（`MenuBarStatus.topProcesses`） | **做（本刀）**：复用主窗内存排序同一 comparator，再 `prefix(3)` |
| 点选 | 十一期 `MenuBarPopoverTap`：dismiss → `selectPidIfPresent` → `focusMemoryPage` | **原样保留**。host block 不可点；「打开 Pulse」只聚焦 |
| 主窗过滤 | 名称过滤 + 十二期「仅上涨」只进 `visibleRows` | **不灌入菜单栏**。投影继续吃完整 `rows` |
| 主窗表排序 | 单份 `navigation.sort`；切 Tab **重置**为该页 default | **不改**切 Tab 重置、不改排序按钮、不另加持久化。菜单栏绑**内存页已发布**的 sort，不绑资源 Tab 当下的 `tableSort` |
| Sampler / Top5 | 九期 `memoryPageSort` + `ProcessTableSort.ordered(rows).prefix(5)` | **零 Sampler 改动、不改 N=5**。只对齐菜单栏那份硬编码副本 |
| 十三期重试 | 单消费者门闩 | **不重开** |
| GPU / 新 Tab / 全表 ring / 新 cadence | 禁止 | **仍禁止** |
| Helper / entitlements / Electron | 无 | **仍无** |

一二三四五六七八九十十一十二十三期验收与公证路径不因本文重开。十一期点选、十期已用内存行、十二期仅上涨、九期 Top5、十三期重试不重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构（现实现，读仓库后的结论）

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

本刀落在 **Darwin-free 排序语义 + 现成 `MenuBarPopoverSnapshot.project` 加 sort 输入**，不是第二套 VM sort，也不是第二套 menu sort。

- 主窗表：`rows` → `MemoryGrowthRisingFilter.apply`（名称 + 仅上涨）→ `visibleRows` → `ProcessTableSort.ordered` → `ProcessTablePane.sortedRows`
- 菜单栏今日：`MenuBarPopoverSnapshot.project(..., rows:)` 内部再 `sorted { memoryBytes desc; pid asc }.prefix(3)`——**故意不跟表头**
- 九期 Top5 已经：`publishMemoryPageSort` → `MemorySampler.memoryPageSort` → `MemoryGrowthTopSeries.pids` = `sort.ordered(rows).prefix(5)`
- 十四期菜单栏应对齐这条「未过滤 `rows` + 内存页 sort + prefix」，只是 N=3、映射现成 `MenuBarPopoverProcess`

约束：

- 不新开第二套 VM、不新开第二路 Mach、不调 `sample()`。
- 不重做 `MenuBarPopoverSnapshot` 类型、不引入第二个弹出条状态源；只给现成 `project` 加 sort 输入。
- 不改 `Pulse.entitlements`、不改公证脚本、不改十三期门闩。
- 自身占用仍优先：排序是纯投影，不是重采样。

### 现模型里有什么（必须按「已有 / 没有」落笔）

| 现字段 / 调用 | 文件 | 十四期怎么用 |
| --- | --- | --- |
| `ProcessTableSort` / `ProcessSortColumn` | `Models/CPUPage.swift`（SamplingCore） | **唯一 comparator**。列：`name` / `cpu` / `memory` / `threads` / `disk`。**没有 PID 列** |
| `ProcessTableSort.ordered` / `.selecting` / `.defaultSort(for:)` | 同上 | 主窗表已经在用。菜单栏改为调用同一份，禁止 piece-meal 再写一套 |
| `ProcessTableSort.defaultSort(for: .memory)` | 同上 | 冷启动 / 切回内存页默认：**内存降序** |
| `DashboardNavigation.sort` / `.select` / `.focusMemoryPage` / `.updateSort` | 同上 | **单份**当前表排序。切到另一可点页会 `sort = defaultSort(for: newPage)`；同页再选保持用户排序 |
| `MemoryDashboardVM.tableSort` | `ViewModels/MemoryDashboardVM.swift` | `navigation.sort` 的只读投影。主窗按钮写的就是它 |
| `MemoryDashboardVM.visibleRows` / `.rows` | 同上 | 菜单栏**继续吃 `rows`**。禁止改吃 `visibleRows` |
| `MemoryDashboardVM.setTableSort` / `ProcessTablePane` 表头 | VM + `Views/ProcessTablePane.swift` | 内存页可点：名称 / CPU / 内存 / 线程。点列 = `tableSort.selecting(column)` |
| `publishMemoryPageSort()` | VM private | `guard selectedPage == .memory` 才 `sampler.setMemoryPageSort(tableSort)`。注释原文：*Only the memory-page sort drives Top 5. Other tabs keep the last memory sort.* |
| `MemorySampler.setMemoryPageSort` / `memoryPageSort` | `Sampling/MemorySampler.swift`（**不在** SamplingCore） | 已有「上次内存页排序」。切走 CPU / 网络 / 磁盘**不**改它。本刀零 Sampler 改动；VM 接线复用这条发布门闩，**不**新造 `@Published lastMemorySort` |
| `MenuBarPopoverSnapshot.project` / `.topProcesses` | `MenuBar/MenuBarStatus.swift`（SamplingCore） | **延长**：加 `ProcessTableSort` 输入；`processListFailed` 仍 `[]`；否则 `sort.ordered(rows).prefix(3)` 再映射现成 `MenuBarPopoverProcess` |
| `MenuBarPopoverProcess` | 同上 | 仍 `pid` / `name` / `memoryBytes`。不改行字段、不改弹出条画法 |
| `MenuBarPopoverTap` | 同上 | **十一期步骤一字不改** |
| `MemoryGrowthRisingFilter` / `filter` / `risingOnlyFilter` | Models + VM | **不进**菜单栏投影 |
| `MemoryGrowthTopSeries.pids` | Models | **对照模式、不改 N=5**。菜单栏是同一 `ordered(rows)` 的 `prefix(3)` |
| Sampler `rows.sort`（内存降序 + pid 升序） | `MemorySampler.sample()` | **不改**。这是采样输出的默认排列，不是菜单栏第二套 sort |

**缺口（已核，不是采样缺口）**：

1. 菜单栏 `topProcesses` 仍硬编码内存降序，与主窗内存页 `tableSort` / 九期 `memoryPageSort` 脱节。
2. `ProcessTableSort.ordered` 主键 `.orderedSame` 时 `return false`；菜单栏与 Sampler 默认内存降序另有 **pid 升序次键**（`testEqualMemoryBreaksTiesByPidAscending`）。
3. `navigation.sort` **不是**跨 Tab 持久的 last memory sort：切到 CPU / 网络 / 磁盘会重置为该页 default；切回内存页会重置为**内存降序**（`CPUPageTests.testColdStartStaysOnMemoryAndCPUSelectionChangesTheDefaultSort`）。
4. 内存页表头**没有 PID 排序按钮**。产品口中的「CPU / 线程 / PID 排序」= 现成 CPU / 线程列 + 已有 pid 升序次键，**不**新开 PID 列。

因此本刀：

1. **零 Sampler 改动**（不改 `sample()` / tick / cadence / `setMemoryPageSort` 语义）。
2. **一份 comparator**：把已有 pid 升序次键收进 `ProcessTableSort.ordered`（主键相等之后、**不受** `descending` 翻转）。这是消掉菜单栏硬编码副本，不是新指标、不是第二套 menu sort。
3. **`project` 加 sort 输入**。VM 传入 `publishMemoryPageSort` 最后一次发出的 `ProcessTableSort`（在内存页上就是当下 `tableSort`）。禁止绑定资源 Tab 上 live 的 `navigation.sort`。
4. 切片：`sort.ordered(rows).prefix(MenuBarPopoverShell.maxProcessRows)`，不足 3 不补 0。
5. 不要新建第二个 `MemoryDashboardVM`，不要重做 Snapshot 类型。

### 其它 Tab 是否 maintain last memory sort（必须如实回答）

**表上的 `navigation.sort`：不 maintain。** 内存页与资源 Tab **共享同一份** `DashboardNavigation.sort`（不是 per-page map）。`select(.cpu / .network / .disk)` 会写成该页 `defaultSort`（CPU / 网络 = CPU 降序；磁盘 = 合计磁盘速率降序）。切回内存页会写成内存降序，用户在内存页点过的 CPU / 线程 / 名称排序**丢掉**。同页再点同一 Tab、或已在内存页时 `focusMemoryPage()`，才保持当前 sort。

**Sampler `memoryPageSort`：maintain。** `publishMemoryPageSort()` 只在内存页发布；切走资源 Tab 早退。这就是九期 Top5 用的「上次内存排序」。注释与 `setMemoryPageSort` 已写死：*Leaving memory does not follow CPU / disk sort.*

**十四期菜单栏绑哪一份：** 绑 **`publishMemoryPageSort` 已发布的那份**（与 Top5 同源），**不是**资源 Tab 当下的 `tableSort`。禁止为了「跟随任一 Tab」让弹出条在用户点 CPU Tab 时改成 CPU 默认序。禁止硬造平行的 `lastMemorySort` 状态机——发布门闩已经存在，接线只是把它传给 `project`。

切 Tab **不**重设这条已发布的内存序（菜单栏 / Top5 保持）。切回内存页走现成 `DashboardNavigation.select` → 表与发布值都回到内存降序——这是现行为，本刀不改、不另加持久化。

从资源 Tab 点 Top3：十一期 `focusMemoryPage()` 若从其它页回来，会把表 sort 重置为内存默认并发布；菜单栏随之回到内存降序。已在内存页时点 Top3 不重置。

## 映射规则

「主窗内存排序」= 内存页最后一次经 `setTableSort` / 冷启动 / 切回内存默认 发布的 `ProcessTableSort`。Top3 = 该 order 下未过滤 `rows` 的前三，**不是** Top 3 by memory，也**不是**把内存列改写成 CPU / 线程 / PID 数值。

| 内存页当前 sort | 主窗未过滤序（同一 comparator） | 菜单栏 Top3 | 行上仍显示 |
| --- | --- | --- | --- |
| 默认 / 切回内存页 | `column == .memory`，`descending == true` | 内存降序前 3 | 名称 + `ByteFormat.memory` |
| 再点内存列 | 升序翻转 | 同一升序前 3 | 同上 |
| 点 CPU | `selecting(.cpu)`：首点降序；`cpuSortKey`（`cpuPercent ?? -1`） | CPU 序前 3，**不是**内存最大的 3 个 | 同上，不画 CPU% |
| 再点 CPU | 升序 | 同一升序前 3 | 同上 |
| 点线程 | 首点 `threadCount` 降序 | 线程序前 3 | 同上，不画线程数 |
| 点名称 | 首点升序（`column != .name` 才默认降序） | 名称序前 3 | 同上 |
| **PID** | **无表头按钮** | 只作主键相等时的 **pid 升序次键**（现菜单栏 / Sampler 默认内存序已有；收进共享 comparator） | 身份仍是 pid，不新开 PID 列 |

升降序规则沿用现成 `selecting`：同一列再点翻转；换列时名称升序、指标列降序。不新开按钮，不改默认内存降序。

| 主键相等 / 缺值 | 现测（以现 comparator 测试为准，不写新指标） | 十四期 |
| --- | --- | --- |
| 内存相等 | 菜单栏 `testEqualMemoryBreaksTiesByPidAscending`：pid 升序；`ProcessTableSort.ordered` 今日 `false` | 共享层收进 pid 升序次键，**不放宽**该菜单栏测试 |
| CPU `nil` vs `0` | `CPUPageTests.testNilCPUSortsBelowARealZero`：`cpuSortKey == -1`，真实 0% 在缺失之上 | **原样** |
| 线程相等 | 无独立次键测试；`compare` 到 `.orderedSame` | 走同一 pid 升序次键 |
| 磁盘列 | 仅磁盘 Tab 表头；内存页 UI 点不到 | 不把磁盘 Tab 的 `.disk` default 灌进菜单栏 |
| 不足 3 条 | 现测：有几条画几条，不补 0 | **原样** |
| `processListFailed` | 现测：`processes == []`，「暂无进程」 | **原样** |
| 采样失败主机行 | 压力 / 已用 `nil`，灰点，「暂时读不到」；进程切片仍可按 `rows` 投 | **原样**。本刀不碰主机行 |

| 切 Tab / 过滤（现行为，菜单栏映射） | 主窗表 | 菜单栏 Top3 |
| --- | --- | --- |
| 内存页点 CPU / 线程 / 名称 | `visibleRows` 按新 sort | 跟随刚发布的内存页 sort |
| 切到 CPU / 网络 / 磁盘 | `navigation.sort` **重置**为该页 default；`publishMemoryPageSort` 早退 | **保持**上次内存页 sort（与 Top5 相同）。**不**改成 CPU / 磁盘 default |
| 切回内存页 | **重置**为内存降序并发布 | 跟随发布，回到内存降序 |
| 已在内存页 `focusMemoryPage` | 不重置当前 sort | 不重置 |
| 从其它页 `focusMemoryPage`（含点 Top3） | 重置为内存降序 | 跟随发布 |
| 名称过滤 ON / OFF | 只改 `visibleRows` | **IDs / 顺序不变** |
| 「仅上涨」ON / OFF | 只改内存页 `visibleRows` | **IDs / 顺序不变** |
| `selectedPid` / Top5 series | 选中与九期 ring 照旧 | **不**灌入投影 |

## VM / UI 契约

`menuBarPopover` 今日：

```
MenuBarPopoverSnapshot.project(
    pressure: snapshot?.pressure,
    usedBytes: snapshot?.usedBytes,
    samplingFailed: samplingFailed,
    rows: rows,
    processListFailed: processListFailed
)
```

十四期只加 **sort 输入** = `publishMemoryPageSort` 最后一次发出的 `ProcessTableSort`（冷启动已是内存降序）。`rows` / 失败旗标 / 主机行语义不动。

| 项 | 锁定 |
| --- | --- |
| 投影源 | 完整 `rows`，不是 `visibleRows` |
| 顺序 | 上述 sort 的 `ordered(rows).prefix(3)` |
| 行模型 | 现成 `MenuBarPopoverProcess`（pid / name / memoryBytes） |
| 行 UI | 现成 `MenuBarPopoverView`：名称 + `ByteFormat.memory`；不改宽度、不加数值标签 |
| 点选 | `MenuBarPopoverTap.steps`：`.dismissPopover` → `.selectPidIfPresent(pid)` → `.focusMemoryPage` |
| 「打开 Pulse」 | dismiss + `focusMemoryPage`，不写 `selectedPid` |
| host block | 不可点 |
| 最多行数 | `MenuBarPopoverShell.maxProcessRows == 3` |
| 空态 | `processListFailed` 或 0 行 →「暂无进程」，无行可点 |
| 采样 | 不调用 `sample()`；不另开 timer |

`AppEmptyState` / 十三期「重试」 / 仅上涨空态 / 九期徽标：**本刀不碰**。

### 明确不做（相对本刀）

- 改 Sampler / 采样源 / 频率 / `setMemoryPageSort` 发布门闩。
- 新排序算法、新 PID 列、新指标、第二套 VM sort / menu sort。
- 改菜单栏布局 / 文案 / 主机压力与已用行 / 栏上 A。
- 重开十三期重试 / 调度。
- 磁盘趋势 / GPU / 新 Tab / 全表 ring。
- 改十二期过滤 / 增长算法 / TopN=5。
- 改主窗排序按钮、默认内存降序、所需字段。
- 另加持久化排序设置、per-page sort map、`@Published lastMemorySort`。
- 重做 `MenuBarPopoverSnapshot` 或第二个状态源。
- 让菜单栏跟随 CPU / 网络 / 磁盘 Tab 当下的 only-page sort。
- 把名称过滤 / 仅上涨 / 选中 pid / Top5 series 灌进菜单栏。
- 把 Top3 内存列改写成 CPU / 线程 / PID，或加第二列数值。
- 声称 Linux 测了 VM / Xcode / 真菜单栏 / 点击表头的 SwiftUI 行为。

## 建议工程顺序

单刀，不要拆成另一套 VM sort。合并后（本文只锁设计；**本 docs PR 不写 Swift**）：

1. **共享纯排序 + `project` 加 sort 输入 + Linux `swift test`**：`ProcessTableSort.ordered` 收进已有 pid 升序次键；`MenuBarPopoverSnapshot.project` 接收 `ProcessTableSort`，对未过滤 `rows` `ordered` 后 `prefix(3)`。钉文末矩阵能在 SamplingCore 钉的部分。零 Sampler、零 AppKit。
2. **VM 接线**：`menuBarPopover` 把 `publishMemoryPageSort` 已发布的 sort 传入 `project`。在内存页上与 `tableSort` 是同一份；切走资源 Tab 不得改传 live `navigation.sort`。

没有硬伤就不开第三条 polish PR。不要和 GPU / 全表 ring / 十三期重试 / 新周期捆在一起。合并不擅自写代码。

## 风险

| 风险 | 应对 |
| --- | --- |
| 把 live `tableSort` 绑到菜单栏，切 CPU Tab 后 Top3 变成 CPU default | 契约写死：只吃 `publishMemoryPageSort` 已发布值；单测钉切 Tab 后菜单栏 IDs 不变 |
| 硬造 `lastMemorySort` / 第二套 menu sort | 复用已有发布门闩 + 同一 `ProcessTableSort`；禁止平行状态 |
| 吃 `visibleRows`，名称过滤 / 仅上涨改 Top3 | 投影继续吃 `rows`；单测 ON/OFF IDs 不变 |
| 把内存列改写成 CPU% / 线程 / PID | 行模型与 View 不改字段 |
| 放宽菜单栏 pid 次键或主窗 ordered 测试 | 次键收进共享 comparator；**不改**现测断言 |
| 当成重采样 / 新 cadence | 范围表零 Sampler |
| 重开点选 / 十三期重试 | Tap 步骤与门闩本刀不碰 |
| Helper / GPU / 新 Tab / 恐吓文案 | 范围表写死不加 |

## 验收（十四期首包）

产品 Must：

- [ ] 内存页默认内存降序时，菜单栏 Top3 与今日相同（含 pid 升序次键）
- [ ] 内存页按 CPU / 线程 / 名称排序后，菜单栏前三 = 同一 comparator 对未过滤 `rows` 的前三，**不是**内存最大的三行
- [ ] 行仍只显示名称 + 内存字节；不改写成 CPU / 线程 / PID
- [ ] 名称过滤、「仅上涨」ON/OFF 不改变菜单栏 pid 顺序
- [ ] 切到 CPU / 网络 / 磁盘：菜单栏保持上次内存页顺序，不改成该 Tab default
- [ ] 切回内存页：现成重置为内存降序；菜单栏跟随
- [ ] 点选步骤同十一期；host block 不可点；「打开 Pulse」只聚焦
- [ ] `processListFailed` / 空列表：「暂无进程」；不足 3 不补 0；采样失败主机行 nil / 灰点不改
- [ ] 无新 Sampler cadence；菜单栏不调 `sample()`
- [ ] 永不写「泄漏」/ leak / 「危险」

测试矩阵（实现 PR 必须覆盖能 Linux 测的项；VM / GUI 标 Mac 剩余）：

1. 默认内存降序 + 同内存 pid 升序：与现 `MenuBarPopoverSnapshotTests` 相同，**不放宽**
2. 内存页 CPU 降序 / 升序：Top3 pid = `sort.ordered(rows).prefix(3)`，与内存最大三行可以不同
3. 线程降序 / 升序：同上
4. 名称升序：同上（现成表头，不是新列）
5. 同主键 tie-break：内存相等 / 线程相等走 pid 升序；CPU nil 沉底低于真实 0（现 `CPUPageTests`）
6. 名称过滤 ON/OFF：菜单栏 IDs / 顺序不变
7. 「仅上涨」ON/OFF：菜单栏 IDs / 顺序不变
8. 切到 CPU / 网络 / 磁盘：投影仍用上次内存页 sort（可用 `DashboardNavigation` + `project(sort:)` 钉，不必起 VM）
9. 切回内存 / 从其它页 `focusMemoryPage`：sort 回内存默认；已在内存页的 `focusMemoryPage` 不重置（现 `CPUPageTests`）
10. `processListFailed` / 空 / 1–2 条；采样失败主机行
11. `MenuBarPopoverTap` 步骤与十一期测试相同，**不放宽**
12. 原 `ProcessTableSort` / Top5 `MemoryGrowthTopSeries.pids` / 菜单栏主机行测试**不放宽**

明确不做（本包出现即不合格）：

- [ ] 无 GPU / 新 Tab / 全表 ring / 新 cadence
- [ ] 无第二套 VM sort / menu sort / `lastMemorySort` 状态机
- [ ] 无菜单栏布局 / 主机行 / 点选改写
- [ ] 无 Helper / 新 entitlements / 持久化排序
- [ ] 无恐吓文案、无「泄漏」
- [ ] 无「跟随任一 Tab 当下排序」
- [ ] 无把过滤 / 仅上涨灌进菜单栏

共性：

- [ ] 一二三四五六七八九十十一十二十三期验收不回退
- [ ] 冷启动仍默认内存页 + 内存降序
- [ ] Linux：`swift test` 跑共享 ordered + `project(sort:)` + 现成菜单栏 / Tap / CPU ordered 测试
- [ ] 不改公证脚本与 entitlements

### Linux 可测 vs Mac 剩余

`Package.swift` 的 SamplingCore **已含** `Models/CPUPage.swift` 与 `MenuBar/MenuBarStatus.swift`，**排除** `ViewModels/`、`MemorySampler`、Views、`MenuBarPopoverView`。共享 comparator 与 `project(sort:)` 必须无 Darwin / 无 AppKit，才能在 Linux CI 实跑矩阵 1–11 的投影部分。

本 docs PR **不跑**、也不声称：

- `MemoryDashboardVM` 实例测试（不在 SamplingCore）
- Xcode GUI / 真菜单栏弹出 / 点击表头设 sort 的 SwiftUI 行为
- 实机 Sampler 发布时序

Mac 冒烟（实现合并后、本机；不挡本文档验收）：

- 内存页点 CPU / 线程，打开菜单栏：前三 pid 与主窗未过滤表一致，行上仍是内存字节
- 打开名称过滤 / 「仅上涨」：菜单栏三行不动
- 切到 CPU Tab 再打开菜单栏：仍是离开内存页前的那一序，不是 CPU 表当下序
- 点 Top3：仍落内存页同 pid；从其它 Tab 点选后表回到内存降序（现 `focusMemoryPage`）
- 失败空态 / 灰点 /「暂无进程」不回退

## 工期

小：天级。主因是复用现成 `ProcessTableSort` + 有界 `prefix(3)` 投影，不是重采样、不是新排序算法。按「共享 comparator + `project` 输入 + Linux 单测 → VM 接线」拆；没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。本 docs 分支**不写 Swift**。

