# ADR-0014：桌面小组件只读主应用写下的压力和前 3 名

状态：提议（#196）。不改变 [ADR-0001](0001-process-memory-footprint.md) 的内存占用，不改变 [ADR-0005](0005-manual-public-ip-request.md)（不新增出站请求），不改变 [ADR-0006](0006-location-for-wifi-name.md)（定位权限仍只在主应用），也不放开 [ADR-0003](0003-thermal-state-api.md) 与 [ADR-0007](0007-chip-temperature.md) 对 `IOServiceOpen` 和 SMC 的禁止；主应用保持非沙盒。在改为已采纳之前，本文不是 `docs/TECH.md` 里的现行行为。

## 背景

不打开 Pulse，也要能看到内存压力档和占用最高的几个进程。桌面小组件是一个新的 WidgetKit 扩展。扩展必须开沙盒。主应用不能跟着开：强制退出和读取其它进程都依赖现在的非沙盒。分发仍是 Developer ID 加上 `scripts/notarize.sh` 公证，不是 Mac App Store。

系统掌握小组件的刷新，大约 15 到 60 分钟才给一次，跟不了现在大约 1.5 秒的采样。扩展自己去采样，在沙盒里也读不到其它进程。

直装的 App Group 要把 Team ID 放进标识。Team ID 只在签名时从环境取得，和 `DEVELOPMENT_TEAM` 同一处，不能写进仓库。

## 决定

- 新增一个小组件扩展 target。扩展开沙盒。主应用保持非沙盒。不改用 Mac App Store 证书。
- App Group 标识以 Team ID 为前缀：`{TeamID}.group.com.qqzhangyanhua.pulse`。拼法是 `$(TeamIdentifierPrefix)` 接上 `group.com.qqzhangyanhua.pulse`。Team ID 仍在签名时取自 `DEVELOPMENT_TEAM` 所在的环境，不提交写死的团队编号。主应用和扩展用同一串。不是 `group.{TeamID}.com.qqzhangyanhua.pulse`，也不是不带 Team ID 的 `group.com.qqzhangyanhua.pulse`。
- 主应用的 entitlements 在现有定位权限之外加上这个 App Group，沙盒仍关。扩展的 entitlements 只有沙盒和这个 App Group。定位权限仍只在主应用。
- 主应用在一次采样成功之后，把一份小读数写进这个 App Group：压力档，加上按内存占用降序的前 3 名。内存占用相同则 pid 较小的在前。没有内存占用读数的进程不进这三名，也不当成 0。不足 3 个就少写几行，不编造进程补满。写不进 App Group 时不改放到别处。
- 压力只有现有两档：「正常」和「偏高」。没有第三档。压力缺失，或某一行的名称缺失，是「—」，不是 0，也不是编出来的名字。这一行的内存占用若缺失，同样是「—」。
- 小组件只读这份读数。它不采样，不退出、不暂停、不降低优先级。不新开采样器，也不把小组件放进现有采样循环。发布由现有的 DashboardCore 在成功的一拍之后做出。
- 采样失败不发布假读数：不写成「正常」，不写成 0，也不用空行补满三名。从未成功过就没有这份读数。失败不覆盖上一份成功的读数。
- 刷新走 WidgetKit 时间线。下一条不早于 15 分钟。不按采样拍请求重载。不承诺 1 秒刷新，也不承诺刚好 15 分钟一定换一帧；系统可以把间隔拉长到大约 60 分钟。
- 扩展和主应用用同一张 Developer ID Application 证书，打进同一次 `scripts/notarize.sh` 归档。主应用仍走现在的非沙盒检查。不为了扩展把主应用的沙盒打开。
- 这份读数不是诊断快照，也不是历史。不因此新增出站请求。

## 后果

- 桌面上能看到「正常」或「偏高」，以及最多三行进程。读不到是「—」。行数可以少于 3，不是永远三行。
- 小组件上的数可以比主应用旧，旧到系统下一次允许刷新。它不是菜单栏，也不是 1 秒监视器。
- 主应用继续能强制退出，继续能读其它进程。扩展做不到这两件事，也不做。
- 公证脚本今天会拒绝沙盒打开的主应用。这条保留。扩展单独带沙盒；脚本和 `docs/RELEASE.md` 要等本 ADR 改为已采纳再改。
- 状态仍是提议。不要把本文当成 `docs/TECH.md` 的现行行为。

## 不考虑

- Dock 角标、浮动窗口、控制中心控件。这三件不在本 ADR。
- 小组件自己采样，或在小组件上退出、暂停、降低优先级。
- 跟采样拍走的刷新，或任何 1 秒小组件。
- 为了上架把主应用放进沙盒，或改用 Mac App Store 证书。
- 把定位权限加到扩展上，或把 Team ID 写进仓库。
- 用 0、空名或凑满的三行代替缺失。
- 用这份读数代替诊断快照或历史库。

## 后续实现 ticket

### 1. 小组件读数的纯编解码

- 阻塞：无
- 交付：压力档和最多 3 个进程可以编码再解回来。缺失仍是缺失，不会变成 0，也不会多出进程。
- 测试接缝：纯解码器。抓住缺失被保住、超过 3 行不被接受。放掉扩展 target、App Group、时间线和界面。

### 2. 成功采样才发布小组件读数

- 阻塞：第 1 张
- 交付：一次成功采样之后，读数是这一拍的压力档和按内存占用的前 3 名。采样失败不发布假读数，也不把缺失写成 0。
- 测试接缝：DashboardCore。抓住只有成功才发布、失败不编造、不覆盖上一份成功读数。放掉 WidgetKit 时间线、签名，以及扩展是否真的显示。

### 3. 下一条时间线至少隔 15 分钟

- 阻塞：第 2 张
- 交付：下一条时间线条目不早于 15 分钟。用户能加上小组件，看到压力档和最多三行；它不是 1 秒刷新。扩展 target 和 App Group 是这条的交付，不是被测单元。
- 测试接缝：纯策略。抓住间隔下限。放掉扩展能否安装、公证，以及系统实际有没有把刷新再拖后。

### 4. 公证纳入扩展并写明沙盒拆分

- 阻塞：第 3 张。本 ADR 仍是提议时不做；改为已采纳之后才改公证脚本和 `docs/RELEASE.md`。
- 交付：同一次归档用同一张 Developer ID 签上扩展。主应用仍非沙盒。RELEASE.md 写明标识的拼法：`$(TeamIdentifierPrefix)` 接上 `group.com.qqzhangyanhua.pulse`，得到 `{TeamID}.group.com.qqzhangyanhua.pulse`。沙盒只在扩展上。定位权限仍只在主应用。不写死团队编号。
- 测试接缝：WiringSourceTests。抓住主应用没有打开沙盒、定位权限没有落到扩展，以及文档里的标识是 `{TeamID}.group.com.qqzhangyanhua.pulse`，也就是 `$(TeamIdentifierPrefix)` 加上 `group.com.qqzhangyanhua.pulse`。不是 `group.{TeamID}.com.qqzhangyanhua.pulse`，也不是不带 Team ID 的 `group.com.qqzhangyanhua.pulse`。放掉没有证书时公证能不能真的通过。
