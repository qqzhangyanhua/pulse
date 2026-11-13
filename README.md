# Pulse

好看的 Mac **资源诊断器**。外表像活动监视器，任务按诊断走：约 30 秒内找到吃内存的进程并安全退出。

- 产品范围与验收：[docs/PRD.md](docs/PRD.md)
- 当前实现与冒烟清单：[docs/TECH.md](docs/TECH.md)
- 公证与发布：[docs/RELEASE.md](docs/RELEASE.md)
- 各期设计稿归档：[docs/specs/](docs/specs/README.md)；口径决定：[docs/adr/](docs/adr/)

## 功能

- **内存页**（默认）：用量大数、分类条、压力档与曲线、可用 / 交换 / 换入 / 换出 / 占用最多的 App。换入 / 换出是每秒字节数，没有曲线；缺数是「—」，真实 0 仍是 0。进程表按内存占用降序，支持名称过滤、仅上涨、仅窗口 App、按 App 合并。
- **详情侧栏**：内存主曲线、CPU 辅曲线、近期上涨软信号、常见系统进程说明，说明下方显示可安全退出判断和一句理由，没有条目的不显示；进程树 / 启动链；退出 / 强制退出，退出后显示已用内存变化。
- **CPU / 磁盘 / 网络页**：主机读数与历史曲线，进程表按对应资源排序。CPU 页另有能耗影响（瓦特）和唤醒。网络页另有连接状态、类型和 Wi-Fi 信号强度，公网 IP 只在点击后查询，Wi-Fi 名称需点击「允许」取得定位权限后才显示。
- **能耗页**：CPU 之后。运行中进程的平均功率和唤醒（次/秒），可在最近 1 分钟和最近 1 小时之间切换，可排序、可搜索，可按 App 合并。1 小时把有读数的分钟耗电量相加，再除以这些分钟的实际时长，缺的分钟不补 0。1 小时排行保留已退出进程，标「已退出」，不能结束。点行打开详情并可结束进程。缺读数是「—」，真实 0 仍是 0。不是活动监视器的能耗影响分数。有内置电池时，表上方有电池卡，显示电量、电源和剩余或充满时间；没有电池则隐藏。表上方另有最近 4 小时、240 分钟的进程能耗合计曲线，缺读数留空；有电池时叠加电量。CPU 页原有两列和本机页电池仍在。
- **本机页**：机型、芯片、系统、容量、开机时间、芯片温度、电源（有内置电池时含循环次数、健康度、功率）、磁盘剩余与当前负载。
- **GPU 页**：本机之后。整页显示「GPU 使用率」「GPU 占用内存」和一条使用率曲线，注册表有核心数时另显示「N 核 GPU」，以及与本机页相同的散热建议卡片。读数来自加速器已发布性能统计里的设备使用率和已用系统内存；缺数是「—」，真实 0 仍是 0。曲线在每一页持续记录，最多约 90 点，只在应用重启后清空。没有进程表和过滤。视图菜单没有 GPU，`⌘1`–`⌘5` 不变。
- **菜单栏**：压力色点，默认栏上无文字；设置里可改为同时显示已用内存或 CPU。轻量条显示压力、已用内存、Top3 进程，点一下打开主窗并选中，也可打开设置。压力偏高时发一条系统通知（默认开），点一下打开内存页。
- **设置**：可让 Pulse 在登录时打开，默认关闭，只注册自己。
- **保存当前快照**：把最近一帧已发布采样冻成只读预览，再存成一份本机 HTML。可隐藏进程名。没有历史列表，回看就是打开那个文件。
- 降频提示：`serious` / `critical` 时，内存、CPU、网络、磁盘、本机、GPU 总览在顶排指标上方显示散热建议卡片（CPU 最高的 3 个进程，可直接退出）；`⌘1`–`⌘5` 切页、`⌘F` 过滤、`⌘⌫` 退出选中进程、`⌘C` 或右键复制选中进程行。GPU 页不把进程行写入剪贴板。

读不到的数据显示「—」或「暂时读不到」，不会显示成 0。文案不用「危险 / 泄漏」类措辞。

## 工程结构

```
Pulse.xcodeproj          macOS 14+ 单 Target
Package.swift            SamplingCore：Darwin 无关的模型与投影，供 swift test 使用
Pulse/
  PulseApp.swift         窗口、命令菜单、快捷键
  Models/                快照、进程行、各页投影与文案
  Sampling/              MemorySampler actor 与各主机 / 进程读数
  ViewModels/            MemoryDashboardVM（唯一 VM）
  Views/                 各页总览、进程表、详情侧栏
  MenuBar/               状态项、轻量条、主窗锚点、AppDelegate
  Actions/               NSRunningApplication.terminate / forceTerminate
  Pulse.entitlements     非沙盒；定位权限用来显示 Wi-Fi 名称。Hardened Runtime 由 build setting 打开
  Assets.xcassets        AppIcon（从 docs/design/app-icon-master.jpg 导出）
Tests/SamplingCoreTests/ XCTest
scripts/notarize.sh      Developer ID archive → notarytool → staple
scripts/make-dmg.sh      可选 DMG（可再公证）
```

一个后台 `MemorySampler` actor 产出不可变快照，主窗和菜单栏读同一帧。前台每 1.5 秒采一次，主窗不在前台、或启动时就没有主窗时降到 3 秒，不另开轮询。

## 构建与测试

```bash
swift test                                   # 只编译并测试 SamplingCore，不编译 App
swift test --filter SamplingPaceTests        # 跑单个测试类
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug build
```

CI（`.github/workflows/ci.yml`，运行在 `macos-15`）会跑 `swift test`，再在不签名的情况下构建 App。推送 `v*` 标签时，`.github/workflows/release.yml` 会构建 Release 并上传未公证的 zip。

## 在 Mac 上本地运行

需要 macOS 14+、Xcode 15+。

1. 打开 `Pulse.xcodeproj`，选 Pulse scheme → My Mac。
2. Debug 已设 `CODE_SIGN_IDENTITY = "-"`（ad-hoc），Signing Team 可以留空。
3. Run。冷启动应落在内存页。
4. 按 [docs/TECH.md「本机冒烟清单」](docs/TECH.md#本机冒烟清单) 检查。第一帧 CPU 列显示「—」是预期行为，要两帧才有差值。

公证直装不要改工程里的 ad-hoc 设置。装好 Developer ID Application 证书后，按 [docs/RELEASE.md](docs/RELEASE.md) 执行 `./scripts/notarize.sh`。

## 维护文档

改了用户可见行为或数据口径时，在同一个 PR 里：

- 更新 `docs/TECH.md` 对应段落（必要时更新冒烟清单）；
- 范围变了就更新 `docs/PRD.md` 和上面的功能列表；
- 推翻了以前的口径就在 `docs/adr/` 加一条 ADR。

`docs/specs/` 里的设计稿是历史记录，不回头改。
