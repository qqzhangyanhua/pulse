# Pulse 二期技术设计（首包）

> 归档：这是第 2 期落地前的设计稿，写完后不再修改。当前实现以 [TECH.md](../TECH.md) 为准，后续期数可能已经改动这里的范围或口径。

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
