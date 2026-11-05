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

**已锁定**：同进程菜单栏（无 Helper / XPC）；复用 `MemorySampler` 快照，不第二路 Mach 轮询；CPU 列表用现有 `ProcessRow.cpuPercent`（两帧差值）。压力 UI 仍只暴露 `normal | elevated`。分发仍走 `docs/RELEASE.md` 的 Developer ID + 公证直装。

来源：用户 + 产品锁定的二期首包；对照一期实现（`MemorySampler` Actor → `MemoryDashboardVM` → Views；`ResourceTab` 仅内存可点；窗体后台现停采）。

## 范围（相对一期）

| 项 | 一期 | 二期首包 |
| --- | --- | --- |
| 菜单栏 | 明确不做 | 做：压力档 + 已用内存（或同等短度量）；点击回主窗内存页 |
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
- 菜单栏不是采样源，只绑 `snapshot`（及格式化后的压力 / 已用内存）。
- 关主窗可留菜单栏；退出 App（⌘Q）卸菜单栏项。
- 自身占用仍优先于刷新华丽度。

### 建议模块 PR 顺序

1. **采样 / 模型增量（若有）**：`SampledFrame` 可带系统 CPU（可空）；VM 在主窗后台改为降频续采（菜单栏与 CPU 页共用）。能复用现字段则本步可空。
2. **菜单栏**：进程内 `MenuBarExtra` + 点击打开 / 聚焦主窗内存页。
3. **CPU Tab UI**：`ResourceTab.cpu` 解灰并切换；默认 cpu% 排序；总览大数；侧栏与退出复用。

不要把菜单栏与 CPU Tab 塞进同一个功能 PR。合并不擅自写代码。

## 菜单栏

结论：进程内状态项，读现成快照，点击回内存页。不做常驻守护、不做权限墙。

### 进程模型（不拆 Helper）

优先 SwiftUI `MenuBarExtra`（部署目标 14+ 已具备），与 `WindowGroup` 同属 `PulseApp`，注入同一 `@StateObject` VM。

不引入 Helper / XPC / Login Item / `LSUIElement`。首包不要求「退出 App 后仍占菜单栏」；退出即卸项，系统回收同进程 `NSStatusItem`。特权分离、沙盒逃逸也不适用（本 App 非沙盒、无特权操作）。

若实现时 `MenuBarExtra` 在关掉最后一个窗口后无法保活或无法可靠回前台：退到**同进程** `NSStatusItem` + 保持 regular `activationPolicy`，仍不拆进程。不要为「实现方便」上 XPC。

| 方案 | 何时用 | 代价 |
| --- | --- | --- |
| `MenuBarExtra` 同进程 | 默认 | 与主窗共享 VM；关窗保活行为需实机确认 |
| `NSStatusItem` 同进程 | MenuBarExtra 关窗/聚焦不稳 | 多一点 AppKit，架构不变 |
| Helper + XPC | **首包不用** | 签名、生命周期、双采样风险；只有「退出后仍常驻」才值得，而首包明确不要 |

### 展示与点击

- 菜单栏可见：压力档（`PressureLevel.title`「正常 / 偏高」，或同等冷静短词）+ 已用内存短度量（复用 `ByteFormat.memory(snapshot.usedBytes)`）。空间不够可压成「偏高 · 18 GB」一类，不新造恐吓色。
- 点击：打开或聚焦主窗，并落到**内存页**（不是 CPU 页）。实现可用 `openWindow` / `NSApp.activate` + 既有 `WindowGroup("Pulse")`；VM 需有可写的当前 Tab（内存为默认）。
- 不做：独立设置窗、登录项勾选、假「需要完全磁盘访问」墙、菜单栏内退出任意进程。

### 采样

一期 `MemoryDashboardVM` 仅在 `scenePhase == .active` 时 `tick()`，后台只 sleep——菜单栏会无数据。二期改：

- **仍只有一个** `MemorySampler.sample()` 循环。
- 主窗前台：保持 ~1.5s。
- 主窗在后台或已关、进程因菜单栏仍在：继续采，频率可相同或略降（约 2–3s）。菜单栏刷新不得快过 Sampler。
- 失败态与一期相同：不假装 0；无快照时菜单栏显示「—」或隐藏数字，不写假用量。

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

侧栏：继续 `ProcessDetail` 的内存主曲线 + CPU 辅曲线；切进程仍清空重采。退出 / 强制退出仍 `ProcessActions.terminate` → `forceTerminate` + 系统 `NSAlert`。

明确不做（相对本 Tab）：功耗小格、GPU / 磁盘 / 网络侧栏、自动高 CPU 告警、逐核深挖页。

## 风险

| 风险 | 应对 |
| --- | --- |
| 菜单栏 + 主窗双订阅同一 `@Published` | 快照不可变、主线程只读；后台略降频；禁止第二套 VM / 第二路 Mach 轮询 |
| 第一帧 CPU「—」 | 已有 `Double?` 与 `ByteFormat.cpu`；列表与系统大数都保持「—」，验收视为合法 |
| App Nap / 窗体后台停采 | 二期改为后台降频续采。若菜单栏长时间冻住，再评估短生命周期 `ProcessInfo` activity；不做常驻防休眠 |
| 关窗 vs ⌘Q | 关窗留项、退出卸项。`MenuBarExtra` 不稳则同进程 `NSStatusItem`，不拆 Helper |
| 系统 CPU API / tick 回绕 | 失败或回绕当 `nil`，不写 0；不要用第一帧当 100% |
| 自身占用 | 前台 1.5s 不变；后台只降频不加倍采样；列表继续虚拟化（一期已有） |

## 验收（二期首包）

菜单栏：

- [ ] 菜单栏能读到压力档 + 已用内存（或同等短度量）；无快照时不装 0
- [ ] 点击打开或聚焦主窗，并落在内存页
- [ ] 退出 App 后状态项消失
- [ ] 无第二路 Mach 轮询；无 Helper/XPC；无新 entitlements；UI 无假 TCC 墙

CPU Tab：

- [ ] CPU Tab 可点；磁盘 / 网络 / GPU 仍灰置
- [ ] 冷启动仍默认内存页
- [ ] 进程表默认按 cpu% 降序；第一帧「—」合法，不装 0
- [ ] 系统 CPU 有数或「—」（未采 / 第一帧均可「—」）
- [ ] 侧栏内存主 + CPU 辅；`terminate` → `forceTerminate` 与一期相同

共性：

- [ ] 文案无恐吓措辞；压力仍两档
- [ ] 前台占用克制；后台菜单栏可略慢，不可另起采样器
- [ ] 不改公证脚本与 entitlements

## 工期

小：按「采样增量 → 菜单栏 → CPU Tab」拆三个工程 PR，天级，不是周级。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认后再动 Swift、采样实现、entitlements 与脚本。
