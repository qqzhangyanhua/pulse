# Pulse

好看的 Mac **内存诊断器**（一期 MVP）。外表像活动监视器，任务按诊断走：约 30 秒内找到吃内存的进程并安全退出。

技术设计：[docs/TECH.md](docs/TECH.md)（二期首包见文末「二期」；三期增长软信号见「三期」；四期网络 Tab 见「四期」；五期磁盘 Tab 见「五期」；六期列表上涨角标见「六期」；七期菜单栏轻量条 B 见「七期」；八期 polish / 本机冒烟见「八期」；九期内存列表上涨徽标密度 Top N=5 见「九期」；十期菜单栏 B 主机已用内存一行见「十期」；十一期菜单栏 B Top3 点选→开主窗选中进程见「十一期」；十二期内存列表「仅上涨」过滤见「十二期」；十三期采样失败手动重试合流见「十三期」；十四期菜单栏 Top3 跟随主窗内存页四列排序（已锁定 A）见「十四期」；十五期内存页过滤空态双清（已锁定 B）见「十五期」；十六期退出结果按 pid 留存与原处重试见「十六期」）。公证直装：[docs/RELEASE.md](docs/RELEASE.md)。

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
  Assets.xcassets        AppIcon（从 docs/design/app-icon-master.jpg 导出）
scripts/notarize.sh      Developer ID archive → notarytool → staple
scripts/make-dmg.sh      可选 DMG（可再公证）
```

前台每 1.5s 在同一个后台 Actor 采一帧不可变快照（含可空的系统 CPU）；主窗不在前台时降到约 3s 续采，不另开轮询。采样失败进入空态，不写假 0。`swift test` 跑这几条采样单测（不编译 App）。

## 在 Mac 上本地验证

此仓库可在 Linux CI 上审源码与工程文件，但 **无法在 Linux 上编译 / 签名 macOS App**。请在 macOS 14+、Xcode 15+ 上：

1. 打开 `Pulse.xcodeproj`，选 Pulse scheme → My Mac。
2. Debug 已设 `CODE_SIGN_IDENTITY = "-"`（ad-hoc）。Signing Team 可留空。
3. Run。冷启动应落在内存页；CPU / 网络 / 磁盘 Tab 可点（网络总览用主机上/下行，进程网络列「暂不可用」；磁盘总览用主机读取/写入，进程缺速率「—」，默认按合计磁盘速率降序）；GPU 仍灰置。
4. 按 [docs/PRD.md](docs/PRD.md) 验收：
   - 用量大数、分类条、压力「正常 / 偏高」+ 曲线
   - 进程表默认内存降序；名称过滤；无结果空态
   - 点选侧栏：内存主曲线 + CPU 辅曲线；切进程后曲线重采
   - 「退出」走 `terminate()`；失败后再「强制退出」，系统 `NSAlert` 确认
   - 文案无「危险」类恐吓措辞
5. 公证直装不要改工程里的 ad-hoc 设置。装上 Developer ID Application 证书后按 [docs/RELEASE.md](docs/RELEASE.md) 执行 `./scripts/notarize.sh`。一期不做 App Store 沙盒。

建议对照活动监视器看总用量数量级是否接近；第一帧 CPU 列显示「—」是预期（要两帧才有差值）。

八期收尾：本机对照 [docs/TECH.md](docs/TECH.md)「八期」冒烟清单勾选（矩阵以 TECH 为准）。设计侧 4 条不可少：详情「内存趋势」三态、列表「上涨」徽标、菜单栏 B、网络 / 磁盘空加载失败文案。无 Developer ID 时公证标 blocked，不挡功能勾选。

## 出货清单

验收以 [docs/PRD.md](docs/PRD.md) 为准，签名与直装以 [docs/RELEASE.md](docs/RELEASE.md) 为准。采样、权限和界面不在这条发布路径里改。

- [ ] PRD：冷启动在内存页，进程表按内存降序
- [ ] PRD：用量大数、分类条、压力「正常 / 偏高」和压力曲线
- [ ] PRD：名称过滤，无结果有空态
- [ ] PRD：侧栏内存主曲线 + CPU 辅曲线，切换进程后重采
- [ ] PRD：退出走 `terminate`；失败后可 `forceTerminate`，强制退出有系统确认
- [ ] PRD：前台采样约 1–2 秒；文案无恐吓措辞；约 30 秒能定位并退出
- [ ] 本机 Debug 冒烟：`CODE_SIGN_IDENTITY=-`（工程已这样设），Xcode Run；八期清单见 TECH「八期」（设计侧 4 条 + 一期～七期回归）
- [ ] 登录钥匙串有 Developer ID Application；`DEVELOPMENT_TEAM` 与 `NOTARY_KEYCHAIN_PROFILE`（或 Apple ID + app 专用密码）只放在环境里
- [ ] `./scripts/notarize.sh` 得到已装订的 `build/export/Pulse.app`，并拷到 `/Applications` 后能打开
- [ ] 可选：`./scripts/make-dmg.sh --notarize` 得到可分发的 DMG
