# ADR-0012：CPU 功耗和频率只在 CPU 页读 Energy Model

状态：已采纳（#192）。补充 [ADR-0004](0004-gpu-accelerator-stats.md)，不放开它对 `IOServiceOpen`、SMC、Metal 计数器和 `powermetrics` 的禁止。GPU 页仍不订阅 Energy Model，仍不把渲染器或分块器的百分比平均成使用率，仍不显示功耗、频率或温度。

## 背景

CPU 页已经有整机百分比、最忙一核，以及进程上的能耗影响。整机这一刻用了多少瓦、性能核和能效核跑在多少赫兹，还没有来源。活动监视器这一块来自 IOReport 的 Energy Model 和 CPU Stats。把读不到写成 0 会把缺失假装成关机。

频率表列的是可能的档位。最高一档不是当前频率。

## 决定

- 只在 CPU 页被选中时读。离开这一页不再读。冷启动停在内存页，不读。不放进每一页都打开的 GPU 采样里。
- 用 `dlopen` 打开 `/System/Library/PrivateFrameworks/IOReport.framework/IOReport`，`RTLD_LAZY | RTLD_LOCAL`。不把 IOReport 加进链接阶段，不调用 `IOServiceOpen`。
- 功耗订阅组名 `Energy Model`。第一拍只做基线。之后用样本差里的能量除以经过的秒。单位按该通道自己的标签：`mJ` 或 `nJ`。通道名不含 `CPU` 的不计入 CPU 功耗。单位不认识、差为负、或不是有限数，这一拍是「—」，不是 0。真实 0 瓦仍显示 `0.0 W`。
- 频率订阅组名 `CPU Stats`。性能核认 `Performance`、`P-Cluster`、`P-Core`，能效核认 `Efficiency`、`E-Cluster`、`E-Core`。当前频率是这一拍驻留最多的那个状态。只有这个状态的名字写着 GHz、MHz，或本身就是赫兹、兆赫兹数字时才显示。名字只是档位标签时保持「—」。不用频率表里的最大值。
- 三行都在 CPU 总览，文案是「CPU 功耗」「性能核」「能效核」。不写入 CPU 曲线，也不写入本机历史。

## 后果

- CPU 页在最忙一核下面多三行。读不到保持「—」。
- GPU 页的使用率来源不变。
- 不要为了补一个数去打开 SMC，也不要把最高频率显示成当前频率。
