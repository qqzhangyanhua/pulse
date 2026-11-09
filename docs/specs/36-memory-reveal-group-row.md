# 普通揭示触发时映射到内存可见组行（未实现）

> 已被取代：普通揭示在门开着时已经映射到当前可见同名组行。当前行为以 [TECH.md](../TECH.md) 为准。下面的正文是落地前的约定，不再改。

> 落地前的技术约定。它不是实现授权，也不是 `main` 上已经改变的滚动。当前普通揭示仍以 [TECH.md](../TECH.md) 里的 `ProcessSelection.scrollTarget` 为准。
>
> 产品验收已锁定，范围是「普通揭示触发时映射到内存可见组行」。对照提交 `129bc173bc92ec3d13a1798bed6015827ef2329b`。开写前核对过该提交仍是 `origin/main`，父提交 `15e618e870384672fb6579f547c5cf27362aef54`。没有更晚提交。文件号 `36` 只用来接在 `35` 之后，不是期次立项。
>
> 落地后改写 TECH.md 的现状句。本文到那时停改。本机冒烟清单的勾选这次不动。本文档 PR 没有跑 Mac 滚动、List 是否保住选择，或 VoiceOver。没有把行滚进视口，就不能把端到端验收说成通过。

## 今天的普通揭示

`processListScrollTarget` 只调用 `ProcessSelection.scrollTarget(selectedPid:in: rows)`。没有选中，或该 pid 不在完整 `rows` 里，结果是空。

`ProcessTablePane` 的列表有两处调用 `revealProcessListTarget`：列表 `onAppear`，以及 `onChange(of: vm.processListScrollTarget)`。函数先 `guard let target = vm.processListScrollTarget else { return }`。值为空就不调用 `scrollTo`。有值时，现有的 `DispatchQueue.main.async` 再 `scrollTo(target, anchor: .center)`。减少动态效果时直接跳，否则用 0.28 秒的缓动。行选中底色自己的 0.16 秒动画不在这里。

`revealTopApp` 是另一条。它看 `sortedRows` 里有没有 `request.pid`，再在同样的 `DispatchQueue.main.async` 里 `scrollTo(request.pid, anchor: .center)`。本期不改它，也不改 `TopAppLocation` 的 `generation`。

列表行的 `id` 是 `row.pid`。内存页按 App 合并后，这个 id 是 `combine` 的代表。普通揭示今天交给 `scrollTo` 的仍是原 pid。代表已经换成别人时，这两个数不同。

## 锁定的行为

先留下今天这道门。`processListScrollTarget` 为空时，`revealProcessListTarget` 仍然直接返回，不调用组查找，也不因此造出一个滚动目标。

门开着时，才做映射。只在页面是 `.memory`、按 App 合并生效、并且这个原 pid 还在本帧 `visibleRows` 里时，复用 `MemoryMagnitudeVisibleGroup.row`。它用该可见行本帧的 `name` 取组。普通 `scrollTo` 改用返回行的 pid，也就是代表。

取值和今天捕获 `target` 在同一次同步调用里完成，然后仍由现有的那一个 `DispatchQueue.main.async` 闭包带上这个 `Int32`。不把查找挪进异步块，不加第二次派发。锚点、缓动、减少动态效果和这道派发的先后都不改。

N 为 1 时代表就是该 pid。原 pid 本来就是代表时，参数也不变。本帧改了名，就用新名字的那一组。

查找为空时保留原来的 `scrollTarget`，不借旁边的同名进程，也不记住上一帧的代表。隐藏、缺席、合并关闭，以及不是内存页，都是这条。本文不承诺旧目标仍在列表里，也不承诺 `scrollTo` 会成功。

`processListScrollTarget` 的计算不改。`onAppear` 和它的 `onChange` 仍是仅有的两处普通触发，不新增对代表、`visibleRows`、排序或合并开关的监听。因此只承诺不新增触发。同一次选中变化如果让这两处都跑到，或再碰上 Top 的命令，本文不承诺最后只滚一次。

映射不写 `selectedPid`，不调用 `setSelectedPid`，不换曲线，不改退出。

## 调用之后的竞态

闭包里的 id 是调用 `revealProcessListTarget` 时读到的代表。派发出去之后，下一轮界面仍可能因为内存读数变化而选出另一个代表，列表 id 也就换了。这次滚动不会再跟。这个间隔没有在 Mac 上验证。不改 `DispatchQueue` 的写法来排除它，也不把它说成已经排除。

## 明确不做

- 不改 Top 的计划、`generation` 和 `revealTopApp`。
- 不改点击写入、`List` 绑定、读屏标签和选中特征。
- 不改大数、高亮和复制。
- 不改采样、过滤、排序和清选中。
- 不改上涨徽标，不把内存页 CPU 改成合计。
- 不做稳定的组 id，不做失败后自动再追一次。
- 不把逐行 `combine` 合成一次。

## 测试

先用已经存在的函数证明今天的揭示 id 和组 id 不同。缺一个新符号导致的编译失败，不能当成这个差异已经复现。

在当前 `main` 上能编译、并且应当失败的断言：两个同名进程，选中较轻的 pid，内存页且合并为真。`ProcessSelection.scrollTarget` 是较轻的 pid。`MemoryMagnitudeVisibleGroup.row` 的 pid 是较重的那个。二者不等。这就是今天 `scrollTo` 拿到的数和列表行 id 的差别。不要把 `scrollTarget` 改成代表 pid 来让它相等。

新的映射函数先原样返回这道门给出的 pid，让「它等于组 pid」失败。然后再在命中时返回代表。门本身的空值测试不依赖这个新函数：`scrollTarget` 在没有选中或不在 `rows` 里时已经是空。

映射至少覆盖：

- 传入的普通目标是空：结果是空，并且不因为可见集合里另有同名进程而变成某个 pid。
- N 为 1：结果是该 pid。
- 原 pid 就是代表：结果不变。
- 代表已是另一个同名 pid：结果是那个代表。调用不产生新的 `selectedPid`。
- 本帧改名：结果是新名字那一组的代表。
- 原 pid 不在 `visibleRows`，旁边另有同名行：结果仍是原来的 `scrollTarget`。
- 合并关闭，或页面不是内存：结果仍是原来的 `scrollTarget`。

接线只读源码：`processListScrollTarget` 的函数体仍是 `ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows)`。`onAppear` 和 `onChange(of: vm.processListScrollTarget)` 仍调用 `revealProcessListTarget`，没有第三处普通触发。`scrollTo` 仍在 `DispatchQueue.main.async` 之后，锚点仍是 `.center`。减少动态效果的分支仍在。`revealTopApp` 仍先看 `sortedRows` 是否含有 `request.pid`，再 `scrollTo(request.pid, anchor: .center)`。行底色仍是原来的 0.16 秒。`applySample` 不因此调用 `setSelectedPid`。

这些测试不是 Mac 滚动验收，也不是 List 保住选择或 VoiceOver 验收。
