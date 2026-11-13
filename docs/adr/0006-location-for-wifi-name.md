# ADR-0006：Wi-Fi 名称使用定位权限

状态：已采纳（#165）。不改变 [ADR-0001](0001-process-memory-footprint.md) 的进程内存占用，不改变 [ADR-0002](0002-process-energy-wakeups.md) 的能耗和唤醒，不改变 [ADR-0003](0003-thermal-state-api.md) 的热状态来源，不改变 [ADR-0004](0004-gpu-accelerator-stats.md) 的 GPU 读数，不改变 [ADR-0005](0005-manual-public-ip-request.md) 的公网 IP 查询。

## 背景

macOS 读当前 Wi-Fi 名称需要定位权限。Hardened Runtime 打开时，非沙盒应用还要在 entitlements 里声明 `com.apple.security.personal-information.location`，否则用户点了「允许」也读不到名称。此前 `Pulse.entitlements` 保持空 dict，这一行显示不出来。

信号强度不读名称，也不走这条权限。

## 决定

- 唯一的 entitlement 是 `com.apple.security.personal-information.location`。应用保持非沙盒。
- 系统定位提示只从「允许」发出。启动时不请求。
- 信号强度不使用这则权限。
- 不要再加其它 TCC entitlements。

## 后果

- 没点「允许」之前，名称是「—」。
- 不要把 entitlements 改回空 dict，也不要为信号强度或其它读数再加权限。
