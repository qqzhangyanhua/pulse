# Top 卡片命令揭示映射可见组（未实现）

> 已被取代：已经发出的 Top 揭示在命中时滚动当前可见同名组的代表。当前行为以 [TECH.md](../TECH.md) 为准。下面的正文是落地前的约定，不再改。

> 落地前的技术约定。它不是实现授权，也不是 `main` 上已经改变的滚动。当前「占用最多的 App」仍以 [TECH.md](../TECH.md) 里的 `revealTopApp` 为准：`sortedRows` 含有 `request.pid` 才滚动这个 pid，否则不滚。
>
> 产品验收已锁定，范围是「Top卡片命令揭示映射可见组」。对照提交 `4994c241e1df0ce6df38815f5715f8cbd1f3c295`。开写前核对过该提交仍是 `origin/main`，父提交 `2df17a296291a42fb386a90a6c1296ac74bbe7d8`。没有更晚提交。文件号 `37` 只用来接在 `36` 之后，不是期次立项。
>
> 产品没有另行核对下面的 9 / 4 链。数字来自这一提交上的源码阅读。落地前若 `>=` 或 `combine` 的并列比较变了，先重读再写测试。落地后改写 TECH.md 的现状句。本文到那时停改。本机冒烟清单的勾选这次不动。本文档 PR 没有跑 Mac 滚动、List 是否保住选择，或 VoiceOver。没有把行滚进视口，就不能把端到端验收说成通过。本文不保证一次滚动，也不保证 `scrollTo` 成功。

## 今天的卡片命令

点内存总览就绪态里的「占用最多的 App」，`OverviewSection` 把 `TopConsumer.leading(in: vm.rows)` 的 `name` 和 `pid` 交给 `locateMemoryTopApp`。`TopAppLocation.plan` 在页面不是 `.memory`、pid 不在完整 `rows`、或该 pid 的 `name` 与卡片名不是 Swift `==` 时返回空。空计划什么都不写。

计划成立时，`Reveal.pid` 就是 `acceptedPid`，也就是传入的卡片 pid。`generation` 是 `(previousReveal?.generation ?? 0) &+ 1`。同一次 pid 再点，generation 仍加一。

`locateMemoryTopApp` 按计划替换名称过滤，然后写 `risingOnlyFilter = false`、`windowedOnlyFilter = false`，再 `selectPidIfPresent(plan.acceptedPid)`，最后把 `topAppLocateReveal` 设为这份 `Reveal`。代表 pid 不写入 `selectedPid`。

`ProcessTablePane` 只在 `onChange(of: vm.topAppLocateReveal)` 里调用 `revealTopApp`。函数先要求 `sortedRows` 含有 `request.pid`。没有就返回，不调用 `scrollTo`。有的话，现有的 `DispatchQueue.main.async` 再 `scrollTo(request.pid, anchor: .center)`。减少动态效果时直接跳，否则用 0.28 秒的缓动。

`sortedRows` 是 `tableSort.ordered(AppGroupProjection.apply(...))`。内存页按 App 打开时，行 id 是 `combine` 的代表。

普通揭示是另一条。`processListScrollTarget` 仍是 `ProcessSelection.scrollTarget(selectedPid:rows:)`。列表 `onAppear` 和它的 `onChange` 仍走 `revealProcessListTarget`，空目标不滚，有值时已经映射到可见组代表。本期不改这条，也不新增监听。

## 9 与 4 从哪来

`TopConsumer.leading` 在 `Pulse/Views/OverviewCards.swift`。同名桶里 `row.memoryBytes >= bucket.bestMemory` 就改写桶的 pid。内存相等时，这次 `rows` 遍历中较后的行留下。桶之间用内存合计最大的名字做卡片。`Package.swift` 排除了 `Views/`，这个类型又 `import SwiftUI`。`swift test` 编译的 SamplingCore 里没有 `TopConsumer`。测试若直接写这个类型名，失败原因是缺类型，不能当成下面的红。

`AppGroupProjection.combine` 用 `members.max`：内存更大者优先；内存相等时比较函数是 `lhs.pid > rhs.pid`，较小 pid 成为代表。`MemoryMagnitudeVisibleGroup.row` 在内存页、合并为真、且 pid 在本帧未合并可见行里时，按该行当前 `name` 调用这个 `combine`。N 为 1 仍返回这一行，pid 就是它自己。

只放两行、名字都是 Chrome、内存都是 100、顺序先 pid 4 再 pid 9：

- 现有 `>=` 留下卡片 pid 9。合计最大的名字就是这一个名字。
- `plan(name: "Chrome", pid: 9, …)` 的 `acceptedPid` 和 `reveal.pid` 都是 9。
- `selectPidIfPresent` 经 `ProcessSelection.acceptedPid` 写下的仍是 9。`ProcessSelection.applying(pid: 9, …)` 在这两行里也是 9。
- `AppGroupProjection.apply` 得到的那一行 pid 是 4。`MemoryMagnitudeVisibleGroup.row` 在 `selectedPid: 9` 时的 pid 也是 4。
- 因此这帧 `sortedRows` 的 pid 只有 4。`sortedRows.contains { $0.pid == 9 }` 为假。`revealTopApp` 在 `scrollTo` 之前返回。今天这条命令的揭示目标是空，没有把 9 交给 `scrollTo`。

行序改成先 9 再 4 时，两套并列都留下 4，分叉消失。本约定的夹具保持先 4 再 9。内存一边严格更大时，卡片 pid 和代表是同一个数，今天的门已经能滚到它。那不是这组夹具。

`TopAppLocation.plan` 不调用 `TopConsumer`。现有 `TopAppLocationTests` 把 43 当作阅读 `>=` 之后的输入，也没有在 Linux 上编译视图类型。本约定同样不把 `TopConsumer` 搬进 SamplingCore，不在测试里另写一套并列规则，也不改 `>=` 或 `combine` 的比较。

## 锁定的行为

只改已经发出的、非空的 Top `Reveal` 要滚动到哪个 id。

命中：页面是 `.memory`、按 App 合并生效、并且 `request.pid` 还在本帧 `visibleRows` 里。这时复用 `MemoryMagnitudeVisibleGroup.row`，按该可见行当前名字取组。`scrollTo` 用返回行的 pid。N 为 1 时就是该 pid。本帧改了名，就用新名字的那一组。命中时直接用这个组 id，不先要求 `sortedRows` 含有原来的 pid。上面的夹具里，组 id 是 4，而 `sortedRows` 不含 9。

未命中才走今天的整道门：`sortedRows` 含有 `request.pid` 就用这个原 id；不含就不调用 `scrollTo`，目标是空。未命中包括合并关闭、页面不是内存、以及 `request.pid` 不在本帧 `visibleRows`。不借旁边的同名进程，也不记住上一帧的代表来填这个空。

id 在调用揭示函数的同一次同步里记下，然后仍由现有的那一个 `DispatchQueue.main.async` 带上这个 `Int32`。不把查找挪进异步块，不加第二次派发，不加失败后再追的调度。锚点仍是 `.center`。减少动态效果和 0.28 秒都不改。

`plan` 的页、pid、名字三道门保持，空计划仍什么都不写。generation 的加一保持。名称过滤的保持或替换、关掉「仅上涨」、关掉「仅窗口 App」、`selectPidIfPresent(plan.acceptedPid)` 保持。曲线和退出仍跟着这个卡片 pid 的现有选中路径。pid 数值真的变化时，现有 `selectedPid` 的 `didSet` 仍会清曲线；那不是把选中改成代表。

`processListScrollTarget`、`revealProcessListTarget`、列表 `onAppear`、`onChange(of: processListScrollTarget)` 和 `onChange(of: topAppLocateReveal)` 的触发关系不改。不新增对代表、`visibleRows`、排序或合并开关的监听。

## 过滤发布和派发之后

`locateMemoryTopApp` 先写过滤和选中，再发布 `Reveal`。`revealTopApp` 读的是它被调用时的 `visibleRows` 和 `sortedRows`。SwiftUI 在 `onChange` 里是否已经看见这些写入，源码不能证明。不改过滤时序来证明它。

异步闭包里的 id 是调用时记下的数。派发出去之后，下一轮界面仍可能选出另一个代表。这次滚动不会再跟。这个间隔没有在 Mac 上验证。不改 `DispatchQueue` 的写法来排除它。

选中 pid 若从别的值变成卡片 pid，普通揭示的 `onChange` 也会跑，并且已经会映射到组代表。Top 命令随后还可能再 `scrollTo` 一次。同 PID 再点时，普通目标的 `Int32` 不变，只有 Top 这条会发。本文不把这两种时序说成最后只滚一次，也不说滚进了视口。

## 明确不做

- 不改 `TopConsumer` 的 `>=`，不改 `combine` 的并列比较，不改卡片上的 pid、名称、内存合计和进程数。
- 不把 `cardPID == groupPID` 当成这条修复的通过条件。9 与 4 的分叉要留下来。
- 不合并普通揭示和 Top 这两次滚动，不加失败后的再调度。
- 不改 `List` 绑定、读屏标签和选中特征。
- 不改大数、高亮、复制、上涨徽标，不把内存页 CPU 改成合计。
- 不改采样、名称谓词、上涨谓词、窗口谓词、排序和清选中。
- 不做组曲线，不把逐行 `combine` 合成一次，不做稳定的组 id。
- 不改退出确认文案。

## 测试

先让现有函数把分叉编译出来，并让旧的整道 `contains` 门给出空。缺一个新符号导致的编译失败，不能当成目标已经复现。绕开 `contains`、把旧行为写成直接滚动 9，也不能当成已经复现。

夹具就是上一节的两行：先 pid 4，再 pid 9，同名，内存相等。下面这些断言在改映射之前和之后都成立，它们不是修绿目标：

- 卡片 pid、`plan.acceptedPid`、`reveal.pid` 都是 9。`ProcessSelection.applying(pid: 9, …)` 的结果是 9，`selectPidIfPresent` 写入的就是这个数。
- `AppGroupProjection.apply` 与 `MemoryMagnitudeVisibleGroup.row` 的 pid 都是 4。
- `XCTAssertNotEqual` 证明 9 与 4 不同。
- 把卡片输入改成 4，或改 `>=` / `combine` 让两边变成同一个数，这条不等就会失败。不允许靠那种改动让后面的滚动断言变绿。

可编译的旧路径先抽成一个纯函数，函数体只有今天的门：`sortedRows` 含有 `request.pid` 就返回这个 pid，否则返回空。入参里的 `sortedRows` 用 `AppGroupProjection.apply` 的结果，不手写一个「含有 9」的数组来绕过这道门。在这组夹具上，这个函数返回空。此时断言「Top 最终揭示目标等于 4」编译通过、运行失败。失败值是空，不是 9。不要把这条断言改成等于 9，也不要用 `XCTAssertNil` 换掉它来得到通过。

然后才在这道门之前加上命中。同一条「最终揭示目标等于 4」变为通过。`XCTAssertNotEqual(9, 4)` 和 `acceptedPid == 9` 仍通过。

映射至少再覆盖：

- N 为 1：最终目标是该 pid。这不是 9 等于 4 的夹具。
- 本帧可见行改了名：最终目标是新名字那一组的代表。计划入口上的名字失配仍让 `plan` 为空并且什么都不写，那一条不产生揭示目标。
- 未命中且 `sortedRows` 含有原 pid：目标是原 pid。合并关闭、原 pid 仍在未合并的 `sortedRows` 里，属于这一条。
- 未命中且 `sortedRows` 不含原 pid：目标是空。原 pid 不在 `visibleRows`、旁边另有同名行时，不返回那个同名行的 pid。
- 页面不是内存：查找未命中，接着走上面的旧门。CPU 页按 App 合并后的 `sortedRows` 若只有代表 4，目标是空。
- 同一 pid 再调用 `plan`：generation 加一，`reveal.pid` 仍是 9。`ProcessSelection.scrollTarget(selectedPid: 9, rows:)` 仍是 9。

接线只读源码：`revealTopApp` 仍由 `onChange(of: vm.topAppLocateReveal)` 进入，不调用 `revealProcessListTarget`。非空 id 仍在 `DispatchQueue.main.async` 之后 `scrollTo`，锚点仍是 `.center`，减少动态效果和 0.28 秒仍在。`onAppear` 与 `onChange(of: vm.processListScrollTarget)` 仍只调用 `revealProcessListTarget`。`processListScrollTarget` 的函数体仍是 `ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows)`。`locateMemoryTopApp` 仍调用 `selectPidIfPresent(plan.acceptedPid)`。`applySample` 不因此调用 `setSelectedPid`。

这些测试不是 Mac 滚动验收，也不是 List 保住选择或 VoiceOver 验收。
