# ADR-0003：热状态只读 ProcessInfo.thermalState

数值温度改由 [ADR-0007](0007-chip-temperature.md) 决定。本文件对 `IOServiceOpen` 和 SMC 的禁止仍然有效。

状态：已采纳（#157）。不改变 [ADR-0001](0001-process-memory-footprint.md) 的内存占用，也不改变 [ADR-0002](0002-process-energy-wakeups.md) 的能耗和唤醒。

## 背景

降频提示需要一个稳定来源。数值温度和风扇转速通常来自 SMC，而 SMC 要 `IOServiceOpen` 打开用户客户端。这条调用是禁止的：现有 IOKit 读数只查注册表属性，不打开用户客户端。Apple Silicon 的 SMC 键也不稳定，不是可以依赖的公开接口。

`ProcessInfo.thermalState` 是系统提供的热状态。它只有档位，没有摄氏度。

## 决定

- `serious` / `critical` 的文案来自 `ProcessInfo.thermalState`。`nominal`、`fair` 和未知档位不显示。
- 不读 SMC 温度，不读风扇转速。原因是禁止 `IOServiceOpen`，而且 SMC 键不稳定。
- 只保留定性状态。不提供数值温度，也不画温度曲线。数值温度改由 ADR-0007 决定，这一句不再有效。

## 后果

- 用户看到的是降频与否，不是风扇转速。多少度在本机页，由 [ADR-0007](0007-chip-temperature.md) 决定。
- 部分机型没有风扇。不要用转速缺失当作去读 SMC 的理由。
- 以后若有公开温度 API，另写 ADR。不要把这次决定改回 `IOServiceOpen`。
