# ADR-0007：芯片温度只读 HID 温度传感器

状态：已采纳（#169）。只取代 [ADR-0003](0003-thermal-state-api.md)「不提供数值温度，也不画温度曲线」这一条。ADR-0003 对 `IOServiceOpen` 和 SMC 的禁止仍然有效。不改变 [ADR-0001](0001-process-memory-footprint.md) 的内存占用，不改变 [ADR-0002](0002-process-energy-wakeups.md) 的能耗和唤醒，不改变 [ADR-0004](0004-gpu-accelerator-stats.md) 的 GPU 读数，不改变 [ADR-0005](0005-manual-public-ip-request.md) 的公网 IP 查询，不改变 [ADR-0006](0006-location-for-wifi-name.md) 的定位权限。

## 背景

本机页要一个当前温度。ADR-0003 当时不提供数值温度，因为 SMC 要 `IOServiceOpen`，而且 Apple Silicon 的 SMC 键不稳定。HID 事件系统会公布温度传感器。这是私有接口，不是 ADR-0003 当时希望的公开温度 API。未签名、非 root 的进程可以读到。系统更新后可能消失。

## 决定

- 数值温度只读 HID 事件系统的温度传感器。符号用 `dlopen` / `dlsym` 解析，不加进链接阶段。只读。
- 不调用 `IOServiceOpen`，不读 SMC，不使用 powermetrics，不安装 Helper。打不开框架、符号缺失、没有服务或读出非有限值，读数缺失，不改用别的来源。
- 卡片叫「芯片温度」：产品名以 `PMU tdie` 开头（大小写敏感）的传感器里，丢掉非有限值后取最高的当前值。显示为整数摄氏度，0.5 远离零。读不到是「—」，不是 0。
- 这张卡只在本机页。跟着现有采样节奏，只在这一页可见时读。不进菜单栏、快照、进程表、GPU 页和散热建议。
- 风扇转速不做：只能从 SMC 读，而 `IOServiceOpen` 仍被禁止。风扇控制不做：要写 SMC，还要 root 权限的 Helper。
- 以后给新芯片加传感器前缀，改代码和 TECH.md，不新写 ADR。

## 后果

- 有这些传感器的机器显示一个整数温度。没有的机器（包括 Intel）卡片仍在，显示「—」。
- 接口消失时显示「—」，不回退到 SMC。
- 散热建议仍只读 `ProcessInfo.thermalState`。
