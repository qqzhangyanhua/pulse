# ADR-0002：能耗读能量计数，唤醒列改名为「唤醒」

状态：已采纳（#107）。不改变 [ADR-0001](0001-process-memory-footprint.md) 的内存占用决定。

## 背景

CPU 页的能耗影响原来读 `proc_pid_rusage`（`rusage_info_v4`）的 `ri_billed_energy`。这是记账余额。满载一核时它仍接近 0，列几乎恒为 0.0 W。

「空闲唤醒」读的是 `ri_pkg_idle_wkups`。大量进程上这个计数长时间没有差值，列几乎恒为 0.0 次/秒，列名还把它说成空闲唤醒。

`ri_energy_nj` 不在 v4 里，也不是 `ri_billed_energy`。它在 `rusage_info_v6` 中，位于 `ri_flags`、`ri_user_ptime`、`ri_system_ptime`、`ri_pinstructions`、`ri_pcycles` 之后。`ri_interrupt_wkups` 从 v0 起就在结构里，和 `ri_pkg_idle_wkups` 是相邻的两个字段。部署目标是 macOS 14，v6 已可用。

## 决定

- 同一次 `proc_pid_rusage` 改为 `rusage_info_v6`（flavor 6）。能量读 `ri_energy_nj`（纳焦），唤醒读 `ri_interrupt_wkups`。
- `ri_phys_footprint` 和磁盘字节仍从这一次结果取。不增加调用。v6 失败后不补一次 v4。失败时内存仍回退驻留内存，能耗和唤醒为缺失。
- 速率公式不变：瓦特 = 纳焦差 / 秒 / 1e9，唤醒 = 次数差 / 秒。两个计数都得不减小才出速率，否则两项都缺失。按 App 合并仍是有值成员求和，部分缺失标「部分读数」。
- 用户可见名称从「空闲唤醒」改为「唤醒」。表头、排序、详情、复制、帮助一起改。
- 瓦特不是活动监视器的能耗影响分数。界面不声称两者相等。

## 后果

- 满载进程的能耗影响可以出现瓦特量级数字；有活动的进程，唤醒列不再整列是 0。
- 对照活动监视器时不能按能耗分数对齐。
- 不要按 ADR-0001 决定段里的 `rusage_info_v4` 把这次调用改回去。内存占用仍是 `ri_phys_footprint`。
