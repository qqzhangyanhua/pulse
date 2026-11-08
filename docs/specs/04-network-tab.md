# Pulse 四期技术设计（首包：网络 Tab）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 4 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。

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
