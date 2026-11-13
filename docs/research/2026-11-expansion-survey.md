# Pulse 扩展方向调研（2026-11）

> 这是一份调研记录，不是决定。按 AGENTS.md 的规则，事实依据的优先级依次是：`main` 上的代码、`docs/adr/`、`docs/TECH.md` / `docs/PRD.md`，最后才是本文。要落地其中任何一项，都要先走 issue 或 spec，需要改口径的还要先写 ADR。
>
> 调研日期：2026-11-13。本机探测用的是 MacBookPro18,3（M1 Pro，6P+2E，14 核 GPU），系统 macOS 26.6.2，管理员账户，App 不开沙盒。所有探测只读、不用 sudo，临时探针用完已删除。凡写「未核实」的内容，都没有找到一手来源。

## 1. 结论速览

- **光靠多加指标，已经拉不开差距。** iStat Menus、Stats、mactop 的指标都比 Pulse 多。Pulse 能和它们拉开差距的，是「冷静、可信、缺数不造假」的诊断能力：讲清楚为什么慢、为什么热、为什么不睡眠，并告诉用户能不能安全处理。这正好接在现有的进程说明、上涨信号、退出后释放量和散热建议后面。
- **同类产品普遍有、Pulse 明显缺的功能，按普遍程度排序**：
  1. 全部温度传感器和风扇
  2. 可配置的告警规则
  3. 每个进程的网络速率
  4. 几小时到几个月的历史
  5. 桌面小组件
  6. 导出、命令行和 API
  7. 功耗与频率
  8. 磁盘空间分布
- **不用 root、也不违反现有 ADR 就能做的事，比预想的多。** 包括：每个进程的 GPU 时间；CPU、GPU、神经网络引擎（ANE）和内存（DRAM）的功耗与频率；全部 HID 温度传感器；电池健康；谁在阻止睡眠；内存压缩与换页；进程签名和 Rosetta 状态；启动项；诊断报告。
- **风扇转速技术上能读，但 ADR-0003 和 ADR-0007 明确禁止。** 本机不用 root 调用 `IOServiceOpen("AppleSMC")` 就能读到风扇转速和整机功率（PSTR）。这两条 ADR 禁止 `IOServiceOpen` 和读 SMC。要做风扇，必须新写一条 ADR 推翻这条禁令，这是产品层面的取舍。
- **长期历史是后面很多方向的地基。** 原因排序、规则告警、「和昨天比」、诊断报告都要建立在本地时序库上。

## 2. 现状与同类产品对照

图例：Y 有，P 部分有，N 没有，? 未核实。

| 类别 | 活动监视器 | iStat Menus 7 | Stats | mactop / macmon | Little Snitch / TripMode | App Tamer | **Pulse** |
|---|---|---|---|---|---|---|---|
| CPU / 内存 | Y | Y | Y | Y | N | P | Y |
| GPU | P（历史窗口） | Y | Y | Y（含每个进程） | N | N | P（只有整机两个数） |
| ANE、功耗与频率 | P | Y | P | Y | N | N | P（只有每个进程的瓦特） |
| 温度传感器与风扇 | N | Y（可控风扇） | Y | Y | N | N | P（只有芯片温度） |
| 电池 | P | Y | Y | P | N | N | Y |
| 磁盘空间分布 | N | Y | Y | P | N | N | P（只有剩余量） |
| 每个进程的网络 | Y? | Y | Y（nettop） | N | Y | N | **N** |
| 暂停、降优先级、限速 | P（可发信号） | ? | ? | P | P（限网络） | **Y** | P（只能退出） |
| 启动项 | N | N | N | N | N | N | N |
| 长期历史 | P（12 小时） | Y（30 天?） | P | P | Y（12 个月） | N | P（能耗页 4 小时） |
| 告警规则 | N | Y | ? | N | Y | Y | P（只有内存压力） |
| 小组件 | N | P? | Y | N | N | N | N |
| 命令行 / API / 快捷指令 | N | N | P | Y（JSON、Prometheus） | Y | N | N |
| 诊断引导 | P | N | N | N | P | P | **Y** |

各产品的要点和出处见第 9 节。值得特别注意的新产品：

- **MacPulse**：有规则型的 Insights 解释，也能录制一段性能数据。
- **Taskglass**：公开了一个 213 个进程的进程库，每条都写了「能不能退出」。
- **Bytetally**：每个 App 的流量，能穿透 VPN 算到真实的 App 上，上传和下载分开统计。

这三家说明「会解释的监视器」已经有人在做，Pulse 要尽快把诊断这条线做深。

## 3. 数据层：能拿到什么

### 3.1 便宜且安全（公开 API 或只读注册表，与现有 ADR 不冲突）

| 数据 | 方式 | 本机探测 | 可以用在哪 |
|---|---|---|---|
| 谁在阻止睡眠 | `IOPMCopyAssertionsByProcess`，加上 NSWorkspace 的睡眠和唤醒通知 | 8 个进程持有断言，包括 caffeinate、bluetoothd 和 powerd | 「不睡眠」诊断、时间线事件 |
| 内存细节 | `host_statistics64`（压缩器、可清除、文件页、换页）、`kern.memorystatus_vm_pressure_level`、`DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`、`ri_lifetime_max_phys_footprint` | 压缩器约 113 万页，压力档 1 | 内存页、详情侧栏显示「峰值」 |
| 电池健康 | 只读 AppleSmartBattery 注册表，以及 `IOPSCopyExternalPowerAdapterDetails` | 设计容量 6075，原始最大容量 4590（约 75.6%），循环 479 次，充电器 65 W | 本机页、能耗页 |
| 蓝牙外设电量 | 注册表里的 `BatteryPercent*` 键（不调用 IOBluetooth，不弹权限框） | 读到一台外设 23% | 本机页 |
| 磁盘容量 | `volumeAvailableCapacityForImportantUsage` 和 `…Opportunistic…`，以及 `tmutil listlocalsnapshots` | 可用 96.3 GB，「重要用途」可用 108 GB，差额就是可清除空间 | 磁盘页「可清除空间」 |
| 每核 CPU 和性能核 / 能效核 | `host_processor_info`、`hw.perflevelN` | 6 个性能核、2 个能效核 | CPU 页 |
| 进程身份 | `KERN_PROC_PID`（启动时间、P_TRANSLATED 即 Rosetta 标记），以及 `SecCodeCopyGuestWithAttributes`（签名和 team ID） | 所有进程都能读 | 详情侧栏、进程表列 |
| 本用户进程的细节 | `KERN_PROCARGS2`（启动参数和环境变量）、`PROC_PIDLISTTHREADS`、`PROC_PIDLISTFDS` 和 `PROC_PIDFDSOCKETINFO`（打开的文件和端口）、`SIGSTOP` / `SIGCONT`、`setpriority` | root 进程返回 EPERM | 详情侧栏、端口视图、暂停和降优先级 |
| 启动项 | 枚举三个 LaunchAgents / LaunchDaemons 目录，再用 `SMAppService.statusForLegacyPlist(at:)` 查状态 | — | 启动项一览，「退出后为什么又回来」 |
| 显示与 GPU 静态信息 | 注册表的 `gpu-core-count`、`CGDisplayCopyDisplayMode`、`MTLDevice` | GPU 14 核，3 块屏 | GPU 页、本机页 |
| 网络接口与 VPN | `NET_RT_IFLIST2`（64 位计数）、SCDynamicStore（DNS、utun） | — | 网络页 |

### 3.2 可行，但要新写 ADR、申请权限或依赖私有接口

| 数据 | 方式 | 和 ADR 的关系 | 风险 |
|---|---|---|---|
| **每个进程的 GPU 时间** | 只读 `AGXDeviceUserClient` 的属性：用 `IOUserClientCreator` 拿到 pid，读 `AppUsage[].accumulatedGPUTime` 两次取差 | 不打开用户客户端，符合 ADR-0004 的禁令。但这是在整机口径之外新增一个口径，要补一条 ADR | 私有属性，只有 Apple 芯片才有。一个进程可能有多个 client，要按 pid 合并。计数回退时按缺失处理。本机共 83 个 client |
| CPU、GPU、ANE、DRAM 的功耗与频率 | 订阅 IOReport 的「Energy Model」和「CPU Stats」，用和 GPU 页相同的 dlopen；频率表从 pmgr 注册表读 | 新指标，要新写 ADR。TECH.md 里 GPU 页目前写着「不订阅 Energy Model」 | 通道名随芯片代际变化。各通道单位不同，本机 GPU 是纳焦，CPU 是毫焦 |
| 全部温度传感器 | 放宽 ADR-0007 的 `PMU tdie` 过滤条件 | 扩展 ADR-0007 | 本机有 64 个温度传感器，没有电流传感器，电压只有 1 个 |
| 更细的热压力档 | `notify_register_dispatch` 订阅 `kOSThermalNotificationPressureLevelName` | 和 ADR-0003 的 thermalState 并存，要写清楚两者的关系 | 档位多出 heavy、trapping 和 sleeping |
| **每个进程的网络** | 运行 `/usr/bin/nettop -L 1 -P -x`（Stats 的做法，能看到 root 进程）；或者私有的 NStatManager | 新增「调用外部命令」的模式，建议写 ADR | nettop 跑一次约 5 秒，只能在网络页可见时运行，或改成常驻读取输出流 |
| 监听端口（包括 root 进程的） | 解析 `netstat -anv`，或读 `net.inet.tcp.pcblist_n` | 同上 | root 进程的端口能否全部看到，未核实 |
| 诊断报告与日志 | `~/Library/Logs/DiagnosticReports`、`/Library/Logs/DiagnosticReports`（管理员可读）、`OSLogStore.local()` | 新数据源 | 非管理员账户读不到系统目录，要显示缺失。日志查询很重，只能在用户需要时查 |
| 完整的后台项列表 | `sfltool dumpbtm`（本机 macOS 26 不用 sudo 也能运行） | 调用没有文档的命令，要写 ADR | 输出格式随系统版本变化。macOS 14 和 15 是否也不需要 sudo，未核实 |
| 大目录扫描 | 遍历文件系统 | 需要完全磁盘访问权限，要写 ADR 并设计引导流程 | 磁盘读写量大，只能手动触发 |
| 小组件、快捷指令 | WidgetKit 扩展、App Intents | 新增 target | 小组件扩展必须开沙盒，App Group 要带 team ID 前缀。刷新大约每 15 到 60 分钟一次，不能实时 |
| 主动 ping、强制门户探测 | ICMP、captive.apple.com | 会产生出站流量，参照 ADR-0005 只能手动触发 | — |

### 3.3 需要特权 Helper、root，或要推翻核心禁令：建议不做

- **SMC 风扇转速和 PSTR**：本机读取成功，但违反 ADR-0003 和 0007 的 `IOServiceOpen` 禁令。风扇控制还要 root Helper，Stats 的 SMC Helper 就出过本地提权漏洞 CVE-2025-21606。
- **NVMe SMART**：要打开插件的用户客户端，等于调用 `IOServiceOpen`。
- **像活动监视器那样对进程采样（Sample）**：需要 `task_for_pid`，本机对用户自己的进程也失败了。
- **每个进程的压缩内存**：需要 task port。
- **root 进程的打开文件、启动参数和线程**：EPERM，统一显示「—」。
- **`powermetrics`**：需要 sudo，ADR-0004 已经排除。

## 4. 产品方向

价值和成本分高、中、低三档。

| # | 方向 | 核心功能 | 价值 | 成本 | 与原则的关系 |
|---|---|---|---|---|---|
| 1 | **按症状诊断** | 「我遇到了……」入口，分慢、热、风扇响、掉电快、磁盘满、不睡眠六种症状。每种列出最可能的 3 个原因，附依据和可做的事；看不出原因时直接说看不出 | 高 | 中 | 最契合原则。必须给出依据，用「可能」这类措辞 |
| 2 | **扩充进程说明库** | 基于现有的 `ProcessGlossary` 扩到 80–150 条，每条写清是什么、为什么会高、怎么办、能不能退出，附出处 | 高 | 低到中 | 文字要自己写，引用只放链接 |
| 3 | **长期历史与时间线** | 分层保留：1 秒精度保留 1 小时，1 分钟精度保留 7 天，15 分钟精度保留 90 天。标出睡眠和唤醒、App 启动、热状态、压力档、崩溃等事件。可以回放，可以和昨天对比 | 高 | 中到高 | 要写 ADR，明确保留期和隐私。Pulse 没运行的时段留空，不补 0 |
| 4 | 告警规则 | 规则由对象、指标、阈值、持续时长组成，带冷却时间、安静时段和专注模式过滤。动作只有「通知」和「确认后退出」 | 中到高 | 中 | 默认少发，避免打扰用户 |
| 5 | **开发者视图** | 列出监听中的端口和对应进程，确认后可以按端口结束；把 Docker / OrbStack 虚拟机、模拟器、node、Xcode 和浏览器辅助进程归到一组；解释虚拟机内存为什么看起来很大 | 高（面向细分人群） | 低到中 | 结束前要显示完整命令行并让用户确认 |
| 6 | 退出之外的进程操作 | 降低优先级、暂停和恢复、重启 App、在 Finder 中显示 | 中 | 低 | 暂停后要有明显标记，并能一键恢复 |
| 7 | 磁盘空间洞察 | 「磁盘满」诊断；开发者缓存（DerivedData、模拟器、Docker）；Time Machine 本地快照；删除的文件一律进废纸篓 | 中到高 | 中 | 申请完全磁盘访问时要按需引导。文案要克制，避免像清理软件那样制造焦虑 |
| 8 | 启动项与签名 | 列出后台项及其来源和签名，**并和进程表关联**，回答「为什么退出后又回来」。进程表加一列「签名」，只陈述签名情况，不下结论 | 中 | 低到中 | 「未签名」不等于「有问题」，文案要说明这一点 |
| 9 | 诊断报告与分享 | 在 HTML 快照上加症状、证据和最近 1 小时的时间线；默认隐去进程名、路径、主机名和 IP；可以复制为 Markdown；可以对比两份快照 | 中 | 低到中 | 默认隐去敏感信息，导出前先给预览 |
| 10 | 自动化 | App Intents（读取压力、前 N 名进程、保存快照）、URL scheme、命令行工具、JSON 导出、仅监听本机的 Prometheus 端点 | 中 | 低到中 | 开本机端口要写 ADR，默认关闭 |
| 11 | 其它入口 | 桌面小组件、Dock 角标、浮动迷你窗、控制中心控件（macOS 26 及以上） | 中低 | 低到中 | 小组件需要一个开沙盒的扩展 |
| 12 | 端侧 AI 解释 | 用 Foundation Models（macOS 26 及以上）把规则引擎找到的证据写成通俗的话；模型不能用时退回规则原文 | 中 | 中 | 只用设备上的模型。截至 2026 年 9 月，Apple Intelligence 在中国大陆仍不可用，只能作为锦上添花 |
| 13 | 发布与商业化 | 英文本地化、Sparkle 自动更新、无障碍基线、首次启动引导；免费版加 Pro 版，或上架 Setapp | 高（决定能否持续投入） | 中 | Sparkle 和授权校验都会联网，要写 ADR。Mac App Store 走不通，沙盒内无法强制退出，也拿不到其它进程的信息 |

## 5. 差异化机会：同类产品几乎都没做好

1. **把耗资源的进程和启动项关联起来。** 比如告诉用户「这个进程退出后又回来了，是因为 LaunchAgent X 会重新启动它」。KnockKnock 只列启动项，各家监视器只看资源，没有人把两者连起来。
2. **验证处理效果。** Pulse 已经能显示退出后释放了多少内存，可以扩展到 CPU、能耗和温度。目前没有竞品做这件事。
3. **先暂停，再退出。** 可以像 App Tamer 那样，用风险更低的暂停代替退出，符合 Pulse 冷静、安全的调性。
4. **在详情侧栏里直接显示进程打开的端口和文件。** 活动监视器要打开 Inspect 窗口才能看，macmon 要在终端里输入过滤条件。
5. **诊断「为什么不睡眠」和「睡眠时掉电」。** 活动监视器只有一列「阻止睡眠」。
6. **进程说明里给出「能不能安全退出」的判断。** 目前只有 Bytetally 在网络场景里做了。
7. **长时间的上涨信号，加上时间线上的事件关联。** iStat Menus 的历史只存平均值，看不到峰值。
8. **给技术支持用的诊断报告。** sysdiagnose 普通用户读不懂，EtreCheck 证明了这个场景有人需要。

## 6. 建议路线图

### 近期（1–2 个月）：充实现有页面，基本不改口径

1. **GPU 页补强**：
   - 显示每个进程的 GPU 时间（要给 ADR-0004 补一条每个进程的口径）。
   - 离开 GPU 页后曲线继续在后台记录，回来时直接有数据（要改 TECH.md 的规则）。
   - 显示 GPU 核心数。
2. **「谁在阻止睡眠」**：在本机页或能耗页列出持有睡眠断言的进程，同时把睡眠和唤醒事件记下来，为以后的时间线做准备。
3. **内存页细节**：显示压缩器用量、换页速率，详情侧栏显示内存占用峰值。
4. **详情侧栏补齐进程信息**：显示启动时间、Rosetta 状态、签名和 team ID，以及本用户进程打开的端口和文件；加「在 Finder 中显示」。
5. **扩充进程说明库**，每条加上「能不能安全退出」的判断。
6. **低风险的进程操作**：降低优先级、暂停和恢复。

### 中期（3–6 个月）：诊断成为主线

1. 本地时序库和事件时间线（新 ADR：保留期、占用空间、隐私）。
2. 「按症状诊断」入口，建立在时序库和规则之上。
3. 告警规则第一版。
4. 每个进程的网络速率（nettop），以及开发者端口视图（新 ADR：调用外部命令）。
5. 功耗与频率：CPU、GPU、ANE、DRAM，GPU 页同时补上频率（新 ADR：订阅 Energy Model）。
6. 启动项一览，并和进程表关联。
7. 诊断报告升级：默认隐去敏感信息，可以复制为 Markdown。
8. App Intents 第一批动作。

### 长期 / 探索

1. 磁盘空间洞察和开发者缓存清理（新 ADR：完全磁盘访问）。
2. 桌面小组件（开沙盒的扩展，加 App Group）。
3. 端侧 AI 解释层。
4. 命令行工具，以及仅监听本机的 Prometheus 端点。
5. 英文本地化、Sparkle、商业化（新 ADR：联网）。
6. **待决定**：要不要推翻 `IOServiceOpen` 禁令、开放「只读 SMC」来显示风扇转速。这件事要先做取舍，再决定做不做。

## 7. 不建议做

- **「一键释放内存」或 `purge`**：在 Apple 芯片上收益很小，反而会清空文件缓存，而且需要 sudo。这是清理软件制造焦虑的套路。
- **不经确认就自动强制退出，或所谓「智能优化」**：可能让用户丢数据。
- **杀毒或恶意软件评分**：要联网获取威胁情报，误报会吓到用户。最多中性地展示签名信息。
- **Endpoint Security 或网络过滤系统扩展**：需要特殊授权和系统扩展，与 Pulse 的定位不符。
- **Mac App Store 版本**：沙盒内无法强制退出，也拿不到其它进程的信息。
- **把内存精确算到浏览器的每个标签页**：Safari 没有公开途径，Chrome 只有 dev 渠道的扩展 API。
- **远程监控另一台 Mac，或做 iPhone 伴侣 App**：要开入站网络服务，还要多维护一个产品。
- **风扇控制**：要写 SMC，还要 root Helper，有安全风险，参见 Stats 的 CVE-2025-21606。

## 8. 落地前需要的 ADR 清单

| 主题 | 涉及的现有 ADR | 关键问题 |
|---|---|---|
| 每个进程的 GPU 时间 | 补充 ADR-0004 | 私有属性；按 pid 合并；计数回退时按缺失处理 |
| IOReport Energy Model 的功耗与频率 | 补充 ADR-0004 | 推翻 TECH.md 里「不订阅 Energy Model，不显示功耗和频率」 |
| 全部温度传感器、更细的热压力档 | 补充 ADR-0007 和 ADR-0003 | 两套热状态口径如何并存 |
| 调用外部命令（nettop、netstat、sfltool） | 新写 | 输出格式不稳定时显示缺失；运行频率；能耗 |
| 本地时序库 | 新写 | 保留期、占用空间上限、可清空、隐去进程名 |
| 完全磁盘访问 | 新写 | 按需申请；没有授权时显示「—」 |
| 联网（Sparkle、授权、本机端口） | 补充 ADR-0005 | 默认询问用户，可以关闭 |
| 只读 SMC（如果决定做风扇） | 推翻 ADR-0003 和 0007 的禁令 | 只读不写，SMC 键不稳定时显示缺失 |

## 9. 未核实事项

- netstat 或 `pcblist_n` 能否看到 root 进程的全部套接字。
- 在 macOS 14 和 15 上，`sfltool dumpbtm` 是否也不需要 sudo。本机只有 macOS 26。
- 连上 Wi-Fi 后，CoreWLAN 的 RSSI、noise 和 tx rate 是否受定位权限限制。本次探测时机器走有线，这三项读数都是 0。
- iStat Menus 7 是否仍有 30 天历史和通知中心小组件（只在版本历史里看到过）。
- 活动监视器的 Inspect 窗口和每个进程的网络列，只有第三方来源。
- 直装版 App 能否使用 Private Cloud Compute；中国大陆的 Mac 能否使用 Foundation Models。
- macOS 27 是否修复了第三方控制中心控件不显示的 bug。
- Little Snitch、Lingon Pro 的现价，以及 Sensei 的现价是否有变化。

## 10. 主要来源

同类产品：

- 活动监视器使用手册：https://support.apple.com/guide/activity-monitor/view-information-about-processes-actmntr1001/mac ，能耗页：https://support.apple.com/guide/activity-monitor/view-energy-consumption-actmntr43697/mac
- iStat Menus：https://bjango.com/mac/istatmenus/ ，规则：https://bjango.com/help/istatmenus7/rules/ ，历史曲线：https://bjango.com/help/istatmenus7/historygraphs/
- Stats：https://github.com/exelban/stats ，用 nettop 读网络的代码：https://raw.githubusercontent.com/exelban/stats/master/Modules/Net/readers.swift ，CVE-2025-21606：https://github.com/exelban/stats/security/advisories/GHSA-qwhf-px96-7f6v
- macmon：https://github.com/vladkens/macmon ；mactop：https://github.com/metaspartan/mactop ；asitop：https://github.com/tlkh/asitop
- TG Pro：https://www.tunabellysoftware.com/tgpro/ ；App Tamer：https://www.stclairsoft.com/AppTamer/ ；KnockKnock：https://objective-see.org/products/knockknock.html ；BlockBlock：https://objective-see.org/products/blockblock.html
- Little Snitch：https://www.obdev.at/products/littlesnitch/index.html ；TripMode：https://tripmode.ch/ ；Bytetally：https://bytetally.app/en/per-app-bandwidth-monitor-mac/
- DaisyDisk：https://daisydiskapp.com/ ；coconutBattery：https://www.coconut-flavour.com/coconutbattery/ ；AlDente：https://apphousekitchen.com/aldente-overview/pricing/
- MacPulse：https://www.macpulse.app/ ；Taskglass：https://www.taskglass.app/processes/docker-desktop ；MacMonitor：https://github.com/ryyansafar/MacMonitor ；Glances：https://github.com/nicolargo/glances

系统接口与平台限制：

- XNU `bsd/sys/proc_info.h`、`bsd/sys/resource.h`：https://github.com/apple-oss-distributions/xnu
- IOPMLib（睡眠断言）：https://developer.apple.com/documentation/iokit/1557072-iopmcopyassertionsstatus
- `SMAppService.statusForLegacyPlist(at:)`：https://developer.apple.com/documentation/servicemanagement/smappservice/statusforlegacyplist(at:)
- `OSLogStore`：https://developer.apple.com/documentation/oslog/oslogstore
- WidgetKit 刷新预算：https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date ；没有沙盒的小组件不显示：https://developer.apple.com/forums/thread/685166
- App Intents：https://developer.apple.com/documentation/appintents ；专注模式过滤：https://developer.apple.com/documentation/appintents/setfocusfilterintent
- Foundation Models：https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel ；中国大陆可用性：https://www.macobserver.com/news/apple-intelligence-16-languages-chinese-not-china-mainland/
- App Store 审核指南 2.4.5（沙盒要求）：https://developer.apple.com/app-store/review/guidelines/ ；沙盒内强制退出会失败：https://developer.apple.com/forums/thread/664479
- Sparkle：https://sparkle-project.org/documentation/ ；Setapp 分成：https://docs.setapp.com/docs/setapp-membership-revenue

诊断知识：

- Apple「如果 Mac 运行缓慢」：https://support.apple.com/guide/mac-help/if-your-mac-runs-slowly-mchlp1731/mac ；kernel_task：https://support.apple.com/en-us/102172
- eclecticlight 对 WindowServer 的解释：https://eclecticlight.co/2025/12/13/explainer-windowserver-2/ ；进程 CPU 过高怎么办：https://eclecticlight.co/2023/06/15/what-to-do-when-a-process-uses-too-much-cpu/
- EtreCheck 报告的使用场景：https://discussions.apple.com/docs/DOC-6172
