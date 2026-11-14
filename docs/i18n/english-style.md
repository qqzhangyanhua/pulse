# 英文风格指南

给把 Pulse 译成英文的人。开发语言是简体中文，键就是中文原文。英文是译文，不是另一套界面。只填英文，不改中文。决定见 [ADR-0017](../adr/0017-english-localization.md)。

测试只锁简体中文，不锁英文。译文好不好，以本指南为准。

## 声音

冷静、具体、短。写出读数。不催用户去做什么。

- 陈述事实。「Headroom is tight.」不要写成「Your Mac is almost out of memory!」
- 不加感叹号。不堆 please。不写赶紧、必须、马上，除非中文原文就是在说这一下会发生什么。
- 一句能说完就不要两句。不补充用户没问的原因。
- 压力只有两档：Normal、Elevated。没有第三档。

## 缺数

读不到是「—」。这个符号不翻译，也不换成词。

- 不要写成 0、N/A、n/a、unknown、unavailable，也不要留空。
- 真实的 0 仍是 0。「0 字节」是「0 bytes」，不是「—」。
- 不要为了补齐一行而编一个进程或一个数。

## 不要用的英文

这些词不用，嵌在更长的词里也不用：leak、danger、dangerous、urgent、critical、junk、bloat、suspicious、infected、kill。

- 内存高不是 leak。没有签名不是 suspicious，也不是 infected。
- 不写 junk files、bloat、critical memory。
- 存盘用的热状态记号（里面有 critical 这个原始值）不显示在界面上。界面只说正在降频。
- Force Quit 只用作「强制退出」这个动作的名字。菜单栏里不用。不要写成 Kill。
- 告警规则是 Notice rules，不是 Alerts、Alarms 或 Warnings。通知是 notify，不是 alert。

## 动作

| 中文 | 英文 | 说明 |
|---|---|---|
| 退出 | Quit | 普通退出 |
| 退出 Pulse | Quit Pulse | 退出本应用，不是 Force Quit |
| 强制退出 | Force Quit | 只此动作。菜单栏不用 |
| 立即退出 | Quit Now | 确认按钮。不要写成 Force Quit 或 Kill |
| 暂停 / 继续 | Pause / Resume | 不是挂起，也不是冻结 |
| 降低优先级 | Lower priority | 不是限速，也不是节流 |

## 句子

- 数字、单位和舍入留在代码里。GB、MB、KB、W、°C、% 保持不变，不改成 GiB。只译旁边的词。
- 中文不分单复数。英文用目录里的复数变体：一个进程是 “1 process”，多个是 “2 processes”。
- 省略号用 …。「正在退出…」译成 “Quitting…”。
- 读屏标签和同一颗按钮一起译，用同一套术语。
- 不翻译：应用名 Pulse、进程名、路径、主机名、IP、偏好设置的键、历史里的原始值、导出文件里不展示的字段。用户读到的句子要译。

## 术语

以 `GLOSSARY.md` 为准。英文栏是唯一译法。避开栏里的说法，中英文都不要拿来替换。

| 中文 | 英文 | 含义 | 避开 |
|---|---|---|---|
| 内存占用 | Memory footprint | 进程的内存占用。不是驻留内存 | 不要写成 memory usage 或 RAM。也不是 GPU 占用内存 |
| 正常 / 偏高 | Normal / Elevated | 压力只有这两档 | 不要加 Critical、Warning、Danger |
| 余量充足 / 余量紧张 | Plenty of headroom / Headroom is tight | 这两档下面的说明 | 不要写成 low memory 或 memory leak |
| 芯片温度 | Chip temperature | 芯片上最热的一处当前温度，单位摄氏度。不分 CPU 和 GPU，也不是平均值 | CPU 温度、GPU 温度、核心温度、SMC 温度。不要写成 CPU temperature 或 GPU temperature |
| GPU 使用率 | GPU utilization | 整机 GPU 的设备级占用，一个 0–100 的百分比 | 渲染器利用率、分块利用率、Metal 计数器 |
| GPU 占用内存 | GPU memory in use | GPU 正在占用的统一内存字节。不是独立显存，也没有总量 | 显存、VRAM、分配内存、内存占用 |
| GPU 核心数 | GPU cores | 整机 GPU 的核心个数。有读数时是 “N-core GPU”，没有就不显示。不是使用率 | 显存、GPU 温度、核心温度 |
| GPU 占比 | GPU share | 最近一个采样间隔里，单个进程占用 GPU 的时间占墙钟时间的比例 | 进程 GPU 使用率、GPU%。不是市场份额 |
| 阻止睡眠 | Preventing sleep | 进程持有断言，让 Mac 或显示器不进入睡眠 | 防休眠、唤醒锁。不要写成 sleep lock |
| 换入 / 换出 | Page-ins / Page-outs | 每秒从磁盘读进内存、或从内存写到磁盘的内存页，包括交换和文件页 | 页面错误、交换速率。不要写成 page faults 或 swap rate |
| 内存占用峰值 | Peak footprint | 进程自启动以来达到过的最高内存占用 | 最大内存、峰值驻留 |
| 暂停 / 继续 | Pause / Resume | 暂时停止运行，可以用继续恢复。不是退出 | 挂起、冻结。不要写成 suspend 或 freeze |
| 降低优先级 | Lower priority | 以更低的优先级调度，可以恢复 | 限速、节流。不要写成 throttle |
| 启动项 | Startup items | 登录或开机时自动启动某个程序的条目 | 自启动、持久化项 |
| 历史 | History | 本机保存的、比实时曲线留得更久的读数 | 时序库、日志、记录。不要写成 logs |
| 告警规则 | Notice rules | 由对象、指标、阈值和持续时长组成，条件满足时发一条系统通知 | 警报、监控规则。不要写成 Alerts |
| 可安全退出 | Safe to quit | 进程说明里对能否退出的三档判断 | 安全等级、风险评分。不要写成 safety rating 或 risk score |

界面上若出现「驻留内存」，只译成 Resident memory。那是读数回退时的标注，不是内存占用，也不是内存占用峰值。「按驻留内存计算」译成 “Calculated from resident memory”。「部分按驻留内存计算」译成 “Partly calculated from resident memory”。

可安全退出的三档句子：

| 中文 | 英文 |
|---|---|
| 可以退出 | Can quit |
| 退出后会自动重启 | Restarts after quit |
| 不建议退出（系统进程） | Not advised (system process) |

第三档不要写成 dangerous，也不要写成 kill。

## 例子

| 中文 | 英文 |
|---|---|
| 压力偏高时通知 | Notify when pressure is elevated |
| 系统正在降频以控制温度 | The system is slowing down to limit temperature |
| 应用没有响应正常退出。系统将立即结束该进程。 | The app did not respond to Quit. The system will end the process now. |
| 选一个进程看详情 | Select a process to see details |
| 历史只保存在这台 Mac 上 | History stays on this Mac |
