# ADR-0012：CPU、GPU、ANE、DRAM 的功耗和频率读 Energy Model

状态：已采纳（#192、#211）。补充 [ADR-0004](0004-gpu-accelerator-stats.md)，不放开它对 `IOServiceOpen`、SMC、Metal 计数器和 `powermetrics` 的禁止。GPU 页显示这一条订阅读到的 GPU 功耗和 GPU 频率。使用率仍不把渲染器或分块器的百分比平均成使用率，仍不显示温度，仍不调用 `IOServiceOpen`。能耗页显示 ANE 和 DRAM 功耗。

## 背景

CPU 页已经有整机百分比、最忙一核，以及进程上的能耗影响。整机这一刻用了多少瓦、性能核和能效核跑在多少赫兹，还没有来源。活动监视器这一块来自 IOReport 的 Energy Model 和 CPU Stats。把读不到写成 0 会把缺失假装成关机。

频率表列的是可能的档位。最高一档不是当前频率。

## 决定

- CPU 功耗和簇频率只在 CPU 页被选中时读。GPU 功耗和 GPU 频率只在 GPU 页被选中时读。ANE 和 DRAM 只在能耗页被选中时读。离开对应页不再读。冷启动停在内存页，不读。不放进每一页都打开的 GPU 使用率采样里，也不用 `setGPUSampling` 当作 Energy Model 的页面开关。
- 用 `dlopen` 打开 `/System/Library/PrivateFrameworks/IOReport.framework/IOReport`，`RTLD_LAZY | RTLD_LOCAL`。不把 IOReport 加进链接阶段，不调用 `IOServiceOpen`。
- 功耗订阅组名 `Energy Model`。第一拍只做基线。之后用样本差里的能量除以经过的秒。单位按该通道自己的标签：`mJ` 或 `nJ`。通道名不含 `CPU` 的不计入 CPU 功耗。单位不认识、差为负、或不是有限数，这一拍是「—」，不是 0。真实 0 瓦仍显示 `0.0 W`。
- 频率订阅组名 `CPU Stats`。性能核认 `Performance`、`P-Cluster`、`P-Core`，能效核认 `Efficiency`、`E-Cluster`、`E-Core`。当前频率是这一拍驻留最多的那个状态。只有这个状态的名字写着 GHz、MHz，或本身就是赫兹、兆赫兹数字时才显示。名字只是档位标签时保持「—」。不用频率表里的最大值。
- 三行都在 CPU 总览，文案是「CPU 功耗」「性能核」「能效核」。不写入 CPU 曲线，也不写入本机历史。
- GPU 功耗把通道名含 `GPU` 的有限瓦特相加。一个都对不上是「—」。ANE 认 `ANE` 或 `Neural`，不区分大小写。DRAM 认 `DRAM`。单位仍是该通道自己的 `mJ` 或 `nJ`。未知单位、负差或非有限数不计入；全都不是有限数则该项是「—」。真实 0 仍是 `0.0 W`。
- GPU 频率用同一只读取器里的 `GPU Stats` 样本差，不在 `HostGPUReader` 里再订一份。当前频率是驻留最多且驻留大于 0 的那个状态，而且只解析这个状态的名字。名字只是档位标签时保持「—」。不用频率表里的最大值。真实 0 是 `0.00 GHz`。
- ANE 和 DRAM 放在能耗页电池卡旁边，不放进 `EnergyBattery.card`。没有内置电池时卡片为 nil，这两项仍显示。
- 这些读数不进菜单栏、快照或进程表。

## 后果

- CPU 页在最忙一核下面多三行。读不到保持「—」。
- GPU 页在使用率和占用内存之外显示「GPU 功耗」和「GPU 频率」。使用率来源不变，仍不平均渲染器或分块器，仍不显示温度，仍不调用 `IOServiceOpen`。
- 能耗页显示「ANE 功耗」和「DRAM 功耗」，台式机没有电池卡也看得到。
- 不要为了补一个数去打开 SMC，也不要把最高频率显示成当前频率。
