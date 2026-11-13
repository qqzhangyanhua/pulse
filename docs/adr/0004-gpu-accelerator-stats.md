# ADR-0004：整机 GPU 读加速器已公布的性能统计

状态：已采纳（#159）。不改变 [ADR-0001](0001-process-memory-footprint.md) 的进程内存占用，不改变 [ADR-0002](0002-process-energy-wakeups.md) 的能耗和唤醒，不改变 [ADR-0003](0003-thermal-state-api.md) 的热状态来源。

## 背景

GPU 页要的是整机使用率，以及 GPU 正在占用的内存。Metal 性能计数器只能看见本进程提交的 GPU 工作。`powermetrics` 的 GPU 使用率需要提权。Apple Silicon 没有独立显存。

GPU 加速器在注册表里公布性能统计。设备级百分比和正在占用的系统内存都不需要打开用户客户端。

## 决定

- 整机 GPU 只读加速器已经公布的性能统计。使用率优先用设备级百分比。这个键不存在时，才读同一加速器的 IOReport 设备通道。
- 不使用 Metal 性能计数器，不使用 `powermetrics`，不调用 `IOServiceOpen`，不读 SMC。
- GPU 占用内存取加速器正在占用的系统内存字节。不取已分配字节，不把物理内存当成显存总量。

## 后果

- 读数覆盖的是整机 GPU，不是 Pulse 自己的绘制。
- 没有这些键的机器显示缺失，不另做一套独显显存条。
- 不要把渲染器和分块器的百分比平均成使用率，也不要把采样改回 Metal 或提权。
