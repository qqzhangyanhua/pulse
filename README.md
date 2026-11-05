# Pulse

好看的 Mac **内存诊断器**（一期 MVP）。外表像活动监视器，任务按诊断走：约 30 秒内找到吃内存的进程并安全退出。

## 一期范围

- 单页：用量大数 → 分类条（App / Wired / Compressed / Cached）→ 压力档与曲线 → 按内存降序的进程表 → 侧栏曲线 + 退出 / 强制退出
- 技术：SwiftUI 原生、单 Target、无 Helper/XPC；Hardened Runtime 已在工程打开
- Bundle：`Pulse` / `com.qqzhangyanhua.pulse`（可改）

## 明确不做（一期）

- 磁盘 / 网络 / GPU 深页、菜单栏常驻
- 自动判泄漏、增长斜率
- Electron / 多平台
- App Store 沙盒、TCC 全盘、内核扩展
- 侧栏分享、耗电 / GPU / 磁盘 / 网络小格

## 工程结构

```
Pulse.xcodeproj          macOS 14+ 单 Target
Pulse/
  PulseApp.swift
  Models/                MemorySnapshot / ProcessRow / Dashboard 状态
  Sampling/              MemorySampler Actor、host_statistics64、proc_listpids
  Actions/               NSRunningApplication.terminate / forceTerminate
  ViewModels/            MemoryDashboardVM
  Views/                 总览、进程表、侧栏
  Pulse.entitlements     空 dict（非沙盒）；Hardened Runtime 由 build setting 打开
```

前台每 1.5s 在后台 Actor 采一帧不可变快照；切后台暂停。采样失败进入空态，不写假 0。

## 在 Mac 上本地验证

此仓库可在 Linux CI 上审源码与工程文件，但 **无法在 Linux 上编译 / 签名 macOS App**。请在 macOS 14+、Xcode 15+ 上：

1. 打开 `Pulse.xcodeproj`，选 Pulse scheme → My Mac。
2. Debug 已设 `CODE_SIGN_IDENTITY = "-"`（ad-hoc）。Signing Team 可留空。
3. Run。冷启动应落在内存页；CPU / 磁盘 / 网络 / GPU Tab 灰置。
4. 按 [docs/PRD.md](docs/PRD.md) 验收：
   - 用量大数、分类条、压力「正常 / 偏高」+ 曲线
   - 进程表默认内存降序；名称过滤；无结果空态
   - 点选侧栏：内存主曲线 + CPU 辅曲线；切进程后曲线重采
   - 「退出」走 `terminate()`；失败后再「强制退出」，系统 `NSAlert` 确认
   - 文案无「危险」类恐吓措辞
5. Release / 公证：把 `CODE_SIGN_IDENTITY` 换成 Developer ID Application，填 `DEVELOPMENT_TEAM`，再 `notarytool`。一期不做 App Store 沙盒。

建议对照活动监视器看总用量数量级是否接近；第一帧 CPU 列显示「—」是预期（要两帧才有差值）。
