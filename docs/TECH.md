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
