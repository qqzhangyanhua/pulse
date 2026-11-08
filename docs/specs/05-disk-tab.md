# Pulse 五期技术设计（首包：磁盘 Tab）

> 归档：这是第 5 期落地前的设计稿，写完后不再修改。当前实现以 [TECH.md](../TECH.md) 为准，后续期数可能已经改动这里的范围或口径。

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
