# Pulse 二十期技术设计（首包：内存页「占用最多的 App」定位）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 20 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。
>
> 已被取代：定位时除了改名称过滤、关「仅上涨」，#80 起还会关掉「仅窗口 App」；「按 App」不受影响。

> 一期至十九期正文不改写。本节只覆盖内存页已经存在的那张「占用最多的 App」卡片：点它时，把列表定位到这张卡片所代表的那一行。不新采样、不改 Top 聚合、不改退出存储、不改名称过滤谓词、不改「仅上涨」谓词。

**已锁定**：用户点的是这张卡片，不是「清空过滤」。动作只从内存总览 `readyBody` 里现有的那一处 `TopAppCard` 进入。纯函数先读一次快照；pid 不在当前 `rows`，或该行 raw `name` 与卡片组名不是 Swift `==`，则整次不写。通过之后才处理名称、关掉「仅上涨」、`selectPidIfPresent`，然后发出恰好一条这张卡片专用的揭示命令。

名称怎么写，只按下面两条，不把「换成组名」推广到空白查询：

1. 当前 `filter` 做 `trimmingCharacters(in: .whitespacesAndNewlines)` 后为空：保持这份 raw 字符串，不写成卡片组名。`""` 与用户留下的空白都保持原样。
2. trim 后非空：目标是 `filter =` 卡片组名。这份 raw 字符串已经与组名 Swift `==` 时，保持原字符串，不重写。其余非空 raw 才写成组名。

每条通过门的动作接着都做：`risingOnlyFilter = false`，`selectPidIfPresent(acceptedPid)`，再发一条揭示。已经选中同一个 pid，不能因此省掉 OFF，也不能省掉揭示。其它点击、键盘、名称输入、页切换、两处现有清空按钮，都不发这条揭示。

来源：二十期主控已锁的定位契约；对照 `c1f3587d1478e40d8f6d4eafdf2008cbdf3f4af4`（十九期实现 #62 所在的 `main`）。本节开写前读过的是这份树上的源码。

本 PR 只追加本节，并在根 `README.md` 的期次索引里加半句导航。不写 Swift、不写测试、不跑 `swift test`、不合并、不改生产代码。下面的红绿步骤是实现 PR 的设计，不是本 PR 的执行结果。下一期不在本文开写，也不在本文锁范围。

## 已读源码（本 SHA）

| 位置 | 今天的事实 |
| --- | --- |
| `OverviewSection.readyBody` | 内存就绪总览才创建 `TopAppCard(consumer: TopConsumer.leading(in: vm.rows))`。闭包是 `vm.selectedPid = pid`（约 157–159 行）。采样骨架与失败空态没有这张可点卡片 |
| `MemoryDashboardView` | `selectedPage == .cpu / .network / .disk` 各走自己的总览；`default` 才是 `OverviewSection()`。CPU / 网络 / 磁盘总览没有 `TopAppCard` |
| `TopConsumer.leading` | 按 `row.name` 做字典键，精确 raw 分桶。桶内 `memoryBytes` 用 `&+` 相加，`processCount` 计数。`row.memoryBytes >= bestMemory` 时覆盖代表 `pid`（同内存时，本次 `rows` 迭代里较后的行留下）。桶之间 `memoryBytes` 最大的一组成卡片。类型在 `Views/OverviewCards.swift`，不在 SamplingCore |
| `TopAppCard` | `onSelect: (Int32) -> Void`。`onTapGesture` 只在 `if let consumer` 时把 `consumer.pid` 交给闭包。`consumer == nil` 没有动作 |
| `ProcessNameFilter.apply` | `trimmingCharacters(in: .whitespacesAndNewlines)` 后为空则原样返回各行；否则 `name.localizedCaseInsensitiveContains`。文件在 `Models/CPUPage.swift` |
| `MemoryDashboardVM.filter` | `@Published var filter = ""`，没有 `didSet` |
| `risingOnlyFilter` | `@Published`，默认 `false`。`didSet` 在 `oldValue != risingOnlyFilter` 时调用 `applyRisingOnlySelection()` |
| `selectedPid` | `@Published`。`didSet` 在值变化时调用 `ProcessQuitSession.followListSelection`，必要时把 `selectedPid` 写回合法 pid；然后 `detail = nil`，`Task { await sampler.setSelectedPid(pid) }`。同值直接返回 |
| `selectPidIfPresent` | `ProcessSelection.acceptedPid(pid, in: rows)` 非 nil 才写 `selectedPid`。缺失 pid 不写 |
| `processListScrollTarget` | `ProcessSelection.scrollTarget(selectedPid:rows:)`，只问完整 `rows` 里有没有这个 pid。不读 `filter`、`visibleRows`、上涨徽标 |
| `visibleRows` / `sortedRows` | `visibleRows` 在 VM，是 `MemoryGrowthRisingFilter.apply`。`sortedRows` 在 `ProcessTablePane`（约 28–30 行），私有计算属性，右值是 `vm.tableSort.ordered(vm.visibleRows)`。不是 VM 成员，也不是 `@Published`。`List` 用的是它 |
| `ProcessTablePane.processList` | `.onAppear` 与 `.onChange(of: vm.processListScrollTarget)` 调用 `revealProcessListTarget`。该函数在 `processListScrollTarget` 非 nil 时 `DispatchQueue.main.async` 再 `scrollTo(target, anchor: .center)` |
| `MemoryGrowthRisingFilter.selectedPid` | 显式丢掉 `rows` 与 `nameQuery`。只有 `risingOnly && page == .memory` 且当前 pid 没有列表徽标时才返回 nil。名称把行藏起来时，选中仍留着。OFF 时返回 `current`，不复活、也不因没徽标而清 |
| `MemoryGrowthList.badge` | 内存页、`seriesByPid` 里有该 pid、且 `evaluate == .rising` 才有徽标。缺 series 就是 nil |
| `applyRisingOnlySelection` | 由上涨开关的 `didSet`、`selectPage`、`focusMemoryPage`，以及 `applySample` 里接受且成功的那一支（`applyRisingOnly = true`）调用。失败、未接受的 flight 不置这个标志 |
| `clearMemoryPageFilters` | 方法体就是 `filter = ""` 与 `risingOnlyFilter = false`。资源页空态仍是 `vm.filter = ""` |
| `followListSelection` | 合法列表 pid 成为 `sidebarSubjectPid`。函数不接收 quit store |
| `risingOnlySelection` | 只由 `applyRisingOnlySelection` 使用。缺席且有记录的主体可以留在侧栏。store 参数不被修改 |
| `@Published` | `MemoryDashboardVM.swift` 上 22 处。`didSet` 两处（上涨开关、`selectedPid`）。类上的 `@MainActor` 一处。十五期源码测试把这三个数钉死 |
| 包布局 | `Package.swift` 的 SamplingCore `sources` 是显式清单，并排除 `Views/` 与 `ViewModels/`。`project.pbxproj` 按文件引用登记模型。新模型文件两处都要登记，否则 Linux 测试与 Xcode App 都看不到它 |

`processListScrollTarget` 非 nil 只说明选中 pid 还在完整 `rows` 里。它不说明这一行正在 `List` 的可见数据里，也不说明它已经滚进视口。已选中 43、名称查询仍是 Safari 时，只要 43 还在 `rows`，`scrollTarget` 就是 43，不是 nil。`selectedPid` 同值时 `didSet` 不跑。只改 `filter` 也不会让这个 `Int32?` 变成另一个值，所以现有 `onChange(of: processListScrollTarget)` 不会因此再揭示一次。

## 今天的缺口

内存就绪时，卡片用完整 `vm.rows` 做 `TopConsumer.leading`，闭包把代表 pid 直接写进 `selectedPid`。

这一写绕过 `selectPidIfPresent`。它不改 `filter`，也不改 `risingOnlyFilter`。名称查询若对不上该行，`visibleRows` 立刻可以不含它；`MemoryGrowthRisingFilter.selectedPid` 又忽略名称，所以选中可以仍然合法。列表用的是过滤后的 `sortedRows`，不是完整 `rows`。

上涨开着、该 pid 没有列表徽标时，这一拍的 `selectedPid = pid` 不会清掉它：`selectedPid` 的 `didSet` 不调用 `applyRisingOnlySelection`。之后某一次会调用那个函数、并且上涨仍是 ON 时，没徽标的当前 pid 才会被清掉。接受且成功的样本会走那条路径；`selectPage`、`focusMemoryPage`、上涨开关的值变化也会走。失败样本和未接受的 flight 不因为这条路径去清。本文不把「点一下卡片」写成「当拍就抹掉选中」。

滚动同一事实：目标 pid 若本来就已选中，`processListScrollTarget` 不变，现有 `onChange` 不能保证这次显式点卡再揭示一次。`onAppear` 只在这份 `List` 出现时跑，列表本来就在层次里时不会重跑。

## 范围

| 项 | 今天 | 二十期首包 |
| --- | --- | --- |
| 点内存页这张卡 | `vm.selectedPid = pid` | **做**：唯一入口改调用 `locateMemoryTopApp(name:pid:)` |
| 空白名称查询 | 卡片不改 `filter` | **保持 raw**。不写成组名 |
| 非空查询 | 卡片不改 `filter` | trim 后非空且 raw 还不是组名时写成组名；raw 已经 `==` 组名则保持 |
| 「仅上涨」 | 卡片不关 | 通过门的动作都写 `risingOnlyFilter = false` |
| 选中 | 直接赋值 | `selectPidIfPresent`。不写 `selectedPid =` |
| 揭示 | 只有 `processListScrollTarget` 变化或 `List` 首次出现 | **加** `revealTopApp(request:proxy:)`，只接这条卡片的 `onChange`。同步门确认 `request.pid` 在现有 `sortedRows` 里，再在 `main.async` 里 `scrollTo` 该 pid。旧 helper 原样留给旧的 `onChange` 与 `onAppear` |
| 无 consumer 的卡 | 不调用 `onSelect` | **保持**。不加新手势 |
| pid 消失或改名 | 直接赋值没有组名门 | **整次不写**，含不发揭示。不改挑同组另一个 pid |
| 列表点选、键盘、名称框、页切换、两处清空 | 现有绑定 | **不发**这条揭示，不改那些绑定 |
| 退出 store、`ProcessQuitSession` | 选中变化时走现成 `followListSelection` | **不改这些类型** |
| `@Published` | 22，`didSet` 两处 | 见下文揭示命令。允许只多这一处可选发布属性，成为 23。`didSet` 仍是两处 |

一二至十九期验收不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 纯函数

新文件 `Pulse/Models/TopAppLocation.swift`，进 SamplingCore。不放进 `ProcessNameFilter`、`TopConsumer`、`MemoryGrowthRisingFilter`、`ProcessQuitSession` 或 `ProcessQuitOutcome`。不引用 `TopConsumer`，也不调用 `leading`。

函数同步、无 `@MainActor`。一次调用的参数就是这一帧快照：卡片组名、卡片代表 pid、当前 `rows`、当前页、当前 `filter` raw、当前 `risingOnly`、上一条揭示命令。返回 nil，或一份计划。计划含名称写入、`risingOnly == false`、`acceptedPid`、下一条揭示。

```swift
enum TopAppLocation {
    enum NameFilterWrite: Equatable, Sendable {
        case keep
        case replace(String)
    }

    struct Reveal: Equatable, Sendable {
        var pid: Int32
        var generation: UInt64
    }

    struct Plan: Equatable, Sendable {
        var nameFilter: NameFilterWrite
        var risingOnly: Bool
        var acceptedPid: Int32
        var reveal: Reveal
    }

    static func plan(
        name: String,
        pid: Int32,
        rows: [ProcessRow],
        page: DashboardPage,
        currentFilter: String,
        currentRisingOnly: Bool,
        previousReveal: Reveal?
    ) -> Plan?
}
```

门的顺序固定，并且在任何 `NameFilterWrite` 之前：

1. `page == .memory`，否则 nil。
2. `ProcessSelection.acceptedPid(pid, in: rows)` 非 nil，否则 nil。
3. `rows.first { $0.pid == accepted }?.name == name`（Swift `==`），否则 nil。同 pid 的重复行不另找。组里另有同名进程也不换 pid。

`currentRisingOnly` 只作为这次快照的一员被读入，不参与分支。实现用 `_ = currentRisingOnly` 留住参数。ON 与 OFF 得到的计划，除调用者自己传入的 `previousReveal` 外必须相同，并且都带 `risingOnly: false` 和一条揭示。函数体不出现 `selectedPid`，因此不能以「已经选中」省掉 OFF 或揭示。

通过门之后才决定名称：

- `currentFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` → `.keep`
- 否则 `currentFilter == name` → `.keep`
- 否则 `.replace(name)`

不把存储中的 `filter` trim 后再写回。trim 后非空、又与组名不是 `==` 的 raw（例如前有空格的 `" Chrome"`）走 `.replace(name)`。不把「trim 之后像这个名字」当成保持。

不增加 `!name.isEmpty`。组名可以为空字符串；门仍只看 pid 在场且该行 `name ==` 传入名。当前 filter trim 后为空时仍然 `.keep`，不因为组名是空的而改写。当前 filter trim 后非空且与这个空字符串不相等时，`.replace("")` 是这条规则的结果，不是额外特判。本文不用一个新 pid 把空组名写成数字验收。

揭示：`generation` 为 `(previousReveal?.generation ?? 0) &+ 1`，`pid` 为通过门的那个 pid。一次非 nil 计划恰好一条。nil 不增加 generation。赋值替换上一条可选值，不追加历史，也不复制一份 `selectedPid`。

计划不带排序、页、publication、`topMemorySeries` 或 sampler 写入。可见性由测试在计划之外调用现成 `MemoryGrowthRisingFilter.ordered` 检查。VM 发布揭示之前不再查一次 `ordered` 来决定发不发。

## VM 写入顺序

`MemoryDashboardVM` 已是 `@MainActor`。新方法是这个类上的同步方法，不再标第二个 `@MainActor`。方法开始时把当前 `rows`、`selectedPage`、`filter`、`risingOnlyFilter`、`topAppLocateReveal` 传入 `plan`。这一读就是快照。方法里没有 `await`，也不在 `Task` 里再读 `rows` 来决定组名或 pid。

`plan` 为 nil 则 return，此时还没有写 `filter`、上涨、选中或揭示。

非 nil 时按这个顺序：

1. `.replace(let nextName)` 才 `filter = nextName`。`.keep` 不写 `filter`。
2. `risingOnlyFilter = false`。这一句不包在「值已经是 false」或「pid 没变」的条件里。现有 `didSet` 的 `oldValue !=` 会在值没变时返回，选中没有副作用。
3. `selectPidIfPresent(plan.acceptedPid)`。不写 `selectedPid =`。
4. `topAppLocateReveal = plan.reveal`。

`selectPidIfPresent` 仍是现成的同步在场检查。它发生在同一次 MainActor 周转、名称决定之后，中间没有 `await`。`filter` 与上涨赋值不改 `rows`。这不是点选之后再异步抓一帧 `rows` 来重算目标。

方法体不调用 `clearMemoryPageFilters`、`sample`、`retrySampling`、`setSelectedPid`、`setTableSort`、`setMemoryPageSort`、`publishMemoryPageSort`、`selectPage`、`focusMemoryPage`、`applyRisingOnlySelection`，不写 `quitOutcome`、`sidebarSubjectPid`、`navigation`、`publication`、`topMemorySeries`。

视图把 `TopConsumer.leading(in: vm.rows)` 绑定一次，卡片和闭包共用这个值。闭包把该值的 `name` 与 `TopAppCard` 传来的 `pid` 交给 `locateMemoryTopApp`。不在闭包里再调用 `leading`。SamplingCore 不接收 `TopConsumer`。不新增 `SharedSelection`。

`TopAppCard` 的 `onSelect` 仍是 `(Int32) -> Void`。`consumer == nil` 时仍不调用它。

## 数字例子

字节用 `ByteFormat` 已有的 1 GiB = `1_073_741_824`。3 GiB = `3_221_225_472`，5 GiB = `5_368_709_120`。两行 3 GiB 相加是 6 GiB = `6_442_450_944`。

夹具按这个顺序构造，只供说明现有 `leading` 与投影。纯函数的输入是已经取出的组名和 pid，它不重跑聚合：

| 顺序 | pid | raw name | memoryBytes |
| --- | --- | --- | --- |
| 1 | 42 | Chrome | 3 GiB |
| 2 | 43 | Chrome | 3 GiB |
| 3 | 9 | Safari | 5 GiB |

按今天的 `>=`，Chrome 桶的代表 pid 是 43，`processCount` 是 2，和是 6 GiB。Safari 单行 5 GiB 小于这个和，所以卡片组名是 Chrome、pid 是 43。两组的和不相等，本文不锁 `Dictionary.max` 在和相等时的顺序。

投影若要观察子串，夹具可以再加一行 raw 名为 `Chrome Helper`。那一行的 pid 只为构成 `ProcessRow`，不是动作输入，也不是第二个代表。验收不锁这个 pid。

动作快照只认传入的 name 与 pid。下面各条都不从「当前还选着哪一行」推导过滤结论。`plan` 不读取 `selectedPid`。

### 1. Safari 查询，上涨 ON

`page == .memory`，`currentFilter == "Safari"`，`currentRisingOnly == true`，`name == "Chrome"`，`pid == 43`，`seriesByPid` 为空（43 没有列表徽标）。

计划：`.replace("Chrome")`，`risingOnly == false`，`acceptedPid == 43`，揭示一条且 pid 为 43。

写完后的投影用这份查询、`risingOnly: false`、调用方原来的 `tableSort`、原来的 `seriesByPid`、`page: .memory` 调用 `ordered`，结果包含 43。同名的 42 也符合 `ProcessNameFilter`。`Chrome Helper` 因现有 `localizedCaseInsensitiveContains` 对 `"Chrome"` 为真而可以留下。Safari 9 对不上这个查询。排序列、升降和 `selectedPage` 都不用这份计划去改。

VM 侧选中结果是 `selectPidIfPresent(43)`。这是动作的 accepted pid，不是「Chrome 42 那一行改变了某条合法规则」。

同一输入把 `currentRisingOnly` 换成 `false`，计划除调用者持有的 `previousReveal` 外相同。

`currentFilter` 已经是 `"Chrome"` 时，名称是 `.keep`，raw 仍是 `"Chrome"`。计划仍是 `risingOnly: false` 加一条揭示。这是规则 2 的保持分支，单独断言，不并进 Safari 那一组充数。

### 2. 空白查询，上涨 OFF

`currentFilter` 为 `""`，以及另一次为仅由空白字符组成的 raw（断言保持那一份原文，而不是写成 `""` 或 `"Chrome"`）。`currentRisingOnly == false`。pid 43、组名 Chrome 通过门。

计划：`.keep`，`risingOnly == false`，`acceptedPid == 43`，揭示一条。

VM 在 `.keep` 分支不写 `filter`。仍写 `risingOnlyFilter = false`，仍 `selectPidIfPresent(43)`，仍发布揭示。若调用前 `selectedPid` 已是 43，现有同值 `didSet` 返回，选中仍是 43，且不因此 `setSelectedPid`。空白查询下 `ProcessNameFilter` 返回全部行，投影包含 43，也包含 Safari。本文不把这一态说成「列表里只剩 Chrome」。

### 3. 空白查询，上涨 ON

与 2 相同，只是 `currentRisingOnly == true`，并且 43 没有徽标。计划仍是 `.keep` 与 `risingOnly: false`，揭示一条。不把空白写成 Chrome。

OFF 写在 `selectPidIfPresent` 之前。上涨从 true 变成 false 时，`didSet` 里的 `MemoryGrowthRisingFilter.selectedPid` 看到的已经是 OFF，返回当时的 `current`，不会因为没徽标把选中清掉。然后再 `selectPidIfPresent`。写完后的 `ordered(..., risingOnly: false)` 包含 43。

### 4. 同一个 pid 被名称藏住

`currentFilter == "Safari"`，`currentRisingOnly == false`，传入 pid 43、组名 Chrome。计划仍是 `.replace("Chrome")`、`risingOnly: false`、一条新揭示。不因为上涨已经是 OFF、也不因为 pid 将与选中相同而返回 nil。

动作前 `selectedPid` 若已是 43：`scrollTarget` 在 43 仍在 `rows` 时就是 43，不是 nil；现有 `onChange(of: processListScrollTarget)` 不会因这次赋值而跑。揭示命令的 generation 变了，所以 `revealTopApp` 会接到这一次。写完后查询为 Chrome、上涨为 false 的 `sortedRows` 含 43，同步门通过，`scrollTo` 的参数是 `request.pid`（43）。若这次 `sortedRows` 仍不含 43（例如门看到的查询还是 Safari），函数在 `scrollTo` 前返回，不改滚当前选中。选中仍是 43。

### 5. pid 已不在 rows

传入 pid 43，但 `rows` 里没有 43。即使 42 仍叫 Chrome，计划也是 nil。不写 filter、上涨、选中，不发揭示，不把 42 升成代表。

### 6. pid 还在，raw name 已不是该组

43 仍在 `rows`，该行 `name` 已不是 `"Chrome"`。组里可以还有别的 Chrome 行。计划是 nil。原来的 `filter`、上涨、`selectedPid` 都不写，不发揭示。不把 filter 改成当前另一组的名字。

### 7. 组、子串、排序、投影

用 1 的写后状态调用现成 `ordered`：查询 `"Chrome"`，上涨 false，`page: .memory`，sort 用调用方持有的内存页现有排序（测试里传 `ProcessTableSort.defaultSort(for: .memory)`，不另造比较器）。

两行 raw 名 Chrome 都在结果里。它们内存相同，现有「主列相等则 pid 升序、升降不翻转」会把 42 排在 43 前。这是现有比较器的结果，不是新 tie 规则。`Chrome Helper` 留在结果里。Safari 不在。`plan` 的类型没有 sort 字段。`TopAppLocation.swift` 不调用 `leading`，也不写 `tableSort`。

名称过滤仍是 trim 空白与换行，再 `localizedCaseInsensitiveContains`。本文不为这句 API 增加变音、Unicode 规范化或区域等价的验收表。普通 raw 名作为查询时，按这句现有 API 匹配自身。分组键与门的比较仍是 Swift `==`，不改成大小写不敏感。

## 揭示与滚动

VM 顺序不变：计划的门失败就返回；通过之后才是 filter 写入（需要时）、`risingOnlyFilter = false`、`selectPidIfPresent`，最后发布 `topAppLocateReveal`。同 pid 仍靠 generation 让这次显式动作发出一条命令。`@Published` 仍只从 22 增到 23，这一处就是该命令。`selectedPid` 数值变化时，原有 `onChange(of: vm.processListScrollTarget)` 与 `List.onAppear` 保留。

`processListScrollTarget` 保持今天的完整 `rows` 语义，不改成可见行，也不把 generation 塞进这个 `Int32?`。它继续只服务旧 helper。普通选中变化时，它仍会随 pid 变化。

同 pid 只改 filter 或上涨时，这个 `Int32?` 不变，现有 `onChange` 不能作为「每点一次卡都揭示」的依据。pid 单独做 `Equatable` 也一样。因此增加一处窄的可选发布属性：

```swift
@Published private(set) var topAppLocateReveal: TopAppLocation.Reveal?
```

没有 `didSet`。没有第二份选中，没有历史数组，没有钉住的 sampler pid，也没有待重试队列。generation 存在这条命令里，不另做发布字段。属性留在 VM 内存中，被下一次显式定位替换。不写入 `navigation`、publication、偏好或采样。之后的样本、退出和再次点卡都不会把它当成持续覆盖 filter 的模式；filter 只在当次 `.replace` 时写一次。不把旧 filter 存下来做回退。

这是 `@Published` 从 22 变成 23 的唯一一处发布属性。十五期 `MemoryPageFilterClearWiringSourceTests` 当时已知断言计数为 22、`didSet` 为 2、`@MainActor` 为 1，并断言 `clearMemoryPageFilters` 的语句就是 `filter = ""` 与 `risingOnlyFilter = false`。实现期把这一 VM 总数改为 23，并点名 `topAppLocateReveal` 是唯一新增。同一总数的 22→23 还映射到另外四个既有源码测试，见文末勘误，不是第二处发布属性。`didSet` 仍是 2。`@MainActor` 仍是 1：计的是 `@MainActor` 属性字面出现次数；注释里的 `MainActor` 不是这条约束，也不新增属性。清空方法的两条语句不改。VM 源码仍不含 `onChange` 这个词。`sortedRows` 不是新的 `@Published`。

`sortedRows` 今天是 `ProcessTablePane` 的私有计算属性，右值是 `vm.tableSort.ordered(vm.visibleRows)`。VM 上还没有这个名字。锁稿要的读取是 `vm.sortedRows`：同一条公式，不是完整 `rows`，也不是新存储。实现把它做成 VM 上的非发布计算属性，pane 里的 `List` 与 `visibleCount` 改为读它，避免两份公式。`@Published` 因此不会变成 24。

显式 Top 的 `onChange` 只调用专用入口 `revealTopApp(request:proxy:)`。`revealProcessListTarget` 不改，仍只给 `.onChange(of: vm.processListScrollTarget)` 和 `.onAppear`。不把旧 helper 改成按 `request.pid` 滚动，否则日常选中的目标会被换掉。

```swift
.onChange(of: vm.topAppLocateReveal) { _, request in
    guard let request else { return }
    revealTopApp(request: request, proxy: proxy)
}

private func revealTopApp(request: TopAppLocation.Reveal, proxy: ScrollViewProxy) {
    guard vm.sortedRows.contains(where: { $0.pid == request.pid }) else { return }
    DispatchQueue.main.async {
        proxy.scrollTo(request.pid, anchor: .center)
    }
}
```

同步门和 `main.async` 闭包里的 `scrollTo` 都只用 `request.pid`。不读 `processListScrollTarget`，也不读 `selectedPid` 来代替目标。不落到同组另一行，不落到完整 `rows`。43 不在这次 `sortedRows` 里就是 no-op；当前选中即使是 9，也不滚 9。

和旧 helper 共用的只有两件：`DispatchQueue.main.async` 这一跳，以及 `anchor: .center`。不共用它的目标选择。不引入 UIKit，不在 VM 里拿 `ScrollViewProxy`。

同一次动作里，发布发生在 filter、OFF、`selectPidIfPresent` 之后。视图接到事件时，同步门看的是当时的 `sortedRows`。正常夹具里，写完后的名称查询与 OFF 会让 43 进入这份投影，门通过，async 之后 `scrollTo` 的是 43。这是这条合成计划的顺序，不是「async 回来时数据永远还在」的 Mac 保证。更早或更晚的样本、过滤若让 `request.pid` 不在当时的 `sortedRows`，门直接返回：不 `scrollTo`，不改 filter / 上涨 / 退出，不换一行重定位，不把请求留下次再试。门通过之后，闭包不再查选中或旧滚动目标。间隙里行若又消失，仍只对原来的 `request.pid` 调用 `scrollTo`；SwiftUI 对过期 id 的真实处理未在 Mac 上验证，本文不把它写成成功。

同 pid：现有 scroll-target `onChange` 不跑。generation 变化使专用 `onChange` 再进一次 `revealTopApp`。同一目标的第二次请求（generation 再加一）仍各自走这个入口，不因为 pid 相同而省掉。

pid 有变化：`processListScrollTarget` 的现有 `onChange` 仍调用 `revealProcessListTarget`；专用入口另按 `request.pid` 走自己的门和 `scrollTo`。不人工把这两次合成一次，也不写成视觉上恰好滚一次。那种合并没有在 Mac 上验证。不删现有钩子，不为它再多发一条 Top 命令。

`List` 当时不在层次里（过滤空态）时，这份新 `onChange` 还不在树上。状态变回 `.ready` 后，现有 `onAppear` 仍用当时的 `processListScrollTarget` 走旧 helper。那是旧的普通选中揭示，不把 Top 请求收成一份持久 pending。本文不断言 SwiftUI 会在出现时补发当时已经存在的 Top `onChange`。

不在 `filter` 或 `risingOnlyFilter` 上加 `onChange`。名称框是 `AppFilterField(text: $vm.filter)`，上涨开关是 `Toggle(..., isOn: $vm.risingOnlyFilter)`。挂在这两枚值上会让普通输入和开关也滚动。

## 选中、详情与退出

这些都是现有函数的行为。本期不改 `ProcessQuitSession`、`ProcessQuitOutcome`，也不改 `selectedPid` 的 `didSet`。

上涨写成 false、而选中 pid 的数值不变时：`didSet` 若发现值没变就返回，不调用 `applyRisingOnlySelection`；若从 true 变成 false，`applyRisingOnlySelection` 看到 OFF，`selectedPid(...)` 返回当前 pid，与现选相同则返回。选中没有副作用。随后同 pid 的 `selectPidIfPresent` 再次命中同值 `didSet`，不把 `detail` 清掉，也不调用 `sampler.setSelectedPid`。

选中 pid 的数值有变化时：发生一次现有 `didSet`。`followListSelection` 把合法的新列表 pid 写成侧栏主体。活的 B 成为主体。这个函数不接收 store，所以原来那个不可用 pid 的记录还在 store 里；本期不增加撤销或改写记录的调用。`detail` 在这次 `didSet` 里先被置 nil，再由已有的 `Task { await sampler.setSelectedPid }` 去取。定位方法本身不保证 B 的详情在这一拍显示出来，也不保证缺席卡继续以 A 为画面主体。那两种说法都不是 `followListSelection` 的现文。

名称把行藏起来时，今天的 `MemoryGrowthRisingFilter.selectedPid` 仍忽略查询，选中可以继续合法。本期不改这句。点卡之后若上涨已被写成 false，后来那次成功样本上的 `applyRisingOnlySelection` 看到 OFF，不会再因为「没徽标」清掉这个 pid。样本路径仍然不写 `filter`。

## 明确不做

- 不把定位实现成 `clearMemoryPageFilters`，也不让清空去选中 pid 或发揭示
- 不在普通列表点选、键盘、名称输入、页切换时关掉上涨。N=5 与 `MemoryGrowthTopSeries.pidLimit` 不动
- 不改 `ProcessNameFilter`、`MemoryGrowthRisingFilter.apply` / `selectedPid`、`ProcessTableSort`
- 不在纯函数里重算 `TopConsumer`，不在同组里另挑 pid，不处理卡片未给出的平局
- 不为 nil 卡片加手势，不在 CPU / 网络 / 磁盘总览加这张卡的调用
- 不改 `processListScrollTarget` 的定义，不用它的非 nil 代表可见。不改 `revealProcessListTarget` 的目标。Top 请求不退回它，也不在没有可见行时改滚当前选中
- 不把揭示做成选中历史、pin，或第二份 `selectedPid`
- 不改 quit 观察器、store、失败文案、冻结投影
- 不改 Sampler、采样节奏、菜单栏、资源详情
- 不把后续样本写成会反复套用这次组名

## 实施时的文件

实现 PR 才动这些文件。本设计 PR 不动。

| 文件 | 改动 |
| --- | --- |
| `Pulse/Models/TopAppLocation.swift` | 新的纯函数 |
| `Package.swift` | `sources` 加入该文件 |
| `project.pbxproj` | 与现有模型相同，增加文件引用与 App target 的 Sources |
| `Pulse/ViewModels/MemoryDashboardVM.swift` | 一处可选发布属性、`locateMemoryTopApp`，以及非发布的 `sortedRows` 计算属性（公式与今天 pane 上的那条相同） |
| `Pulse/Views/OverviewSection.swift` | 唯一调用点。绑定一次 `leading`，闭包传 name 与 pid |
| `Pulse/Views/ProcessTablePane.swift` | Top 的 `onChange` 只调用 `revealTopApp(request:proxy:)`。旧 `revealProcessListTarget` 仍只服务 scroll-target `onChange` 与 `onAppear` |
| `Tests/SamplingCoreTests/MemoryPageFilterClearWiringSourceTests.swift` | 十五期清空。同一 VM `@Published` 总数 22→23，点名 `topAppLocateReveal`。清空两条语句不改 |
| `Tests/SamplingCoreTests/MemoryDashboardVMSortWiringSourceTests.swift` 的 `testPhase19DiskHeadersAreLiteralColumnsAndThisIsNotGUI` | 十九期磁盘表头。同一总数 22→23。分列表头、比较器与 forbidden 不改 |
| `Tests/SamplingCoreTests/MemoryDetailSidebarWiringSourceTests.swift` 的 `testFrozenGuardPidSwitchAndChartPlaceholderStayUntouched` | 十七期冻结侧栏。同一总数 22→23。`memoryGrowthSlot`、详情清空与采样曲线不改 |
| `Tests/SamplingCoreTests/ProcessQuitSessionWiringSourceTests.swift` 的 `testVMHoldsOneQuitStoreAndDerivesPhaseFromTheSidebar` | 十六期退出。同一总数 22→23。单一 quit store 与 `didSet` 仍为 2 不改 |
| `Tests/SamplingCoreTests/ResourceDetailPageSourceTests.swift` 的 `testNewModelsStayOutOfTheSamplerQuitStoreAndVMPublishedSurface` | 十八期资源详情。同一总数 22→23。投影不进入 sampler、quit store 或那些方法 |
| `docs/TECH.md` | 文末勘误。只补源码事实，不扩行为 |
| 新测试 | reducer 与源码接线分开，见下节 |

`TopAppCard` 的手势结构可以不改。`CPUOverviewSection`、`NetworkOverviewSection`、`DiskOverviewSection` 不调用新方法。

## 测试矩阵（设计；本 PR 不写、不跑）

实现 PR 的红必须是真的失败。本环境没有执行 `swift test`。不要把本节写成已经绿了。

**红：** 生产还没有 `TopAppLocation` 时，测试直接调用 `TopAppLocation.plan`。失败应是编译错误。接线测试在源码还没有 `locateMemoryTopApp` 时断言失败。禁止用 `XCTFail`、测试里复制一份假计划类型、或改松旧断言来伪装红。

**绿：** 补上纯函数、VM 方法、唯一调用点和揭示 `onChange`，使这些测试通过，再跑全量 `swift test`。实现 PR 留下真实日志。本设计 PR 没有这些数字。

Reducer 测试调用纯函数和现成 `ordered`，不编译 `MemoryDashboardVM`，不进入其 MainActor。接线测试只读源文件文本，风格与 `MemoryPageFilterClearWiringSourceTests` 相同。两类测试各自成测试方法。读过源码不算数学通过，跑过纯函数也不算点过 Mac。

1. Safari + ON：`.replace("Chrome")`，`risingOnly == false`，accepted 43，一条揭示。`ordered` 含 43。`currentRisingOnly: false` 的同名快照不改变这份计划。raw 已是 `"Chrome"` 的保持分支单独一个方法。
2. `""` 与一份仅空白 raw，上涨 OFF：`.keep` 且 raw 原文仍在断言里，`risingOnly == false`，一条揭示。不出现组名写入。
3. 空白查询 + ON、目标无徽标：仍 `.keep`，计划为 OFF，一条揭示。写后的 `ordered(..., risingOnly: false)` 含该 pid。
4. filter Safari、上涨已 OFF、传入已在场的 43：仍 `.replace("Chrome")`、OFF、一条新 generation。不返回 nil。
5. pid 不在 `rows`：nil。同组其它 pid 还在也不产出计划。
6. pid 在场但 `name` 已变：nil。不改用同组另一行。
7. 查询 Chrome、上涨 false、现有内存默认排序：两行 Chrome 都在，42 在 43 前是现有 pid 升序 tie-break；`Chrome Helper` 在；Safari 不在。`plan` 不携带 sort。

机制断言，不用来代替 1–7：

- `page != .memory` 为 nil
- 连续两次非 nil 计划的 generation 相差 1；nil 不消耗上一条 generation
- 纯函数源码不含 `TopConsumer`、`leading`、`selectedPid`
- VM 方法源码先 `guard let plan`，其后 `risingOnlyFilter = false`、`selectPidIfPresent`、`topAppLocateReveal =` 各一处且按这个顺序；`filter =` 只在 replace 分支；无 `selectedPid =`、无 `await`、无 `sample()`
- `OverviewSection` 只有一处 `TopConsumer.leading`、一处 `locateMemoryTopApp`，把绑定值的 `name` 和闭包 pid 传入；没有 `selectedPid =`
- `ProcessTablePane` 里只有 Top 的 `onChange(of: vm.topAppLocateReveal)` 调用 `revealTopApp`。该函数同时含 `vm.sortedRows.contains(where: { $0.pid == request.pid })` 与 `scrollTo(request.pid, anchor: .center)`，并且 `scrollTo` 在 `DispatchQueue.main.async` 闭包里。三处缺一即红。空白或换行可以不同，身份门和 `request.pid` 这两个匹配都要在。函数体不用 `processListScrollTarget` 或 `selectedPid` 当滚动目标
- `revealProcessListTarget` 仍含对 `processListScrollTarget` 的读取、`DispatchQueue.main.async` 与 `scrollTo`。旧的 `onChange(of: vm.processListScrollTarget)` 与 `onAppear` 仍调用它，不改为调用 `revealTopApp`
- 反向夹具只约束专用入口：`sortedRows` 不含请求 pid 时这条函数在 `scrollTo` 前返回。源码接线不是点击、不是真的 `ScrollView`、也不是视口已经滚到
- CPU / 网络 / 磁盘总览源码不含 `locateMemoryTopApp`
- `clearMemoryPageFilters` 语句仍是那两句。`@Published` 为 23，新属性没有 `didSet`，全文件 `didSet` 仍为 2

既有清空、排序、上涨、退出测试里，除这一 VM `@Published` 总数外的期望不放宽。原先写「十五期那条计数是唯一数值更新」漏列了同一字面总数还钉在另外四个既有测试里。22→23 是这一处属性的单值映射，不是五次行为变更。见文末「二十期实现期全量回归勘误」。

## 风险

| 风险 | 应对 |
| --- | --- |
| 空白查询也被写成 Chrome | 规则 1：trim 后为空则 `.keep` |
| 为了「精确」把用户的 `"Chrome"` 或空白 raw trim 后再写回 | `.keep` 不赋值。只有非空且不是 `==` 才 `.replace(name)` |
| 同 pid 已选中就跳过 OFF 或揭示 | 计划不读 `selectedPid`。VM 三步都在 nil 返回之后，无同 pid 条件 |
| 先写 filter，门失败再补救 | nil 在任何写入之前返回 |
| `await` 之后再读 `rows` 重算代表 | 方法无 `await`。代表 pid 是参数，函数不调用 `leading` |
| 用 `scrollTarget != nil` 当作已经滚到，或 Top 入口再调用旧 helper | 同 pid 时 scroll target 不变。`revealTopApp` 只看 `sortedRows` 是否含 `request.pid`，`scrollTo` 只用该 pid |
| 在 filter 上 `onChange`，输入每个字都滚动 | 只观察 `topAppLocateReveal` |
| 新 pid 时现有钩子加新命令被写成「已证实只滚一次」 | 源码只锁一条专用命令。视觉合并不写进验收 |
| 点卡当拍被写成一定会清掉无徽标选中 | 今天的直接赋值不调用 `applyRisingOnlySelection`。清发生在后来那次调用且上涨仍 ON 时 |
| 改 `followListSelection` 去冻结旧主体或当场填详情 | 不改该函数。活 B 成为主体；详情仍走现有 sampler 任务；旧记录留在 store |
| 把 `@Published` 再加到 24，或给揭示加 `didSet` | 只增加这一处可选属性，无 `didSet` |
| 源码测试被说成 Mac 已点过 | 下节 |

## 验收

- [ ] 唯一入口是内存 `OverviewSection` 里现有 `TopAppCard`。闭包把同一次 `leading` 的组名和 pid 交给 `locateMemoryTopApp`。没有 `vm.selectedPid = pid`。nil 卡片仍无动作。CPU / 网络 / 磁盘总览不调用
- [ ] 门在任何 filter 写入之前：内存页、`acceptedPid` 非 nil、该行 raw `name` 与传入名 Swift `==`。失败则 filter、上涨、选中、侧栏主体、揭示都保持进入时的值。不替换同组 pid，不重算 Top
- [ ] trim 后为空的当前 filter 保持该 raw，不写组名。trim 后非空且 raw 已与组名 `==` 时保持该 raw。其余非空才 `filter =` 组名。不新增 `!name.isEmpty`
- [ ] 每条通过门的动作都接着 `risingOnlyFilter = false`、`selectPidIfPresent(acceptedPid)`、一条揭示。同 pid 也不省这两步。普通点选、键盘、名称框、页切换、两处清空都不发揭示
- [ ] 例子 1：Safari + ON、无徽标 → 查询 Chrome、OFF、accepted 43；`ordered` 含 43；两行 Chrome 都匹配；`Chrome Helper` 可以因现有子串留下；排序与页不改
- [ ] 例子 2、3：空白 OFF 与空白 ON 都保持空白 raw；ON 那条仍先 OFF 再选中再揭示
- [ ] 例子 4：已选 43、Safari、上涨 OFF → 查询变为 Chrome、选中仍 43、投影含 43、专用揭示恰好一条。不把非 nil 的 `scrollTarget` 当成已经可见
- [ ] 例子 5、6：消失或改名是 nil，含不发揭示
- [ ] 揭示属性是唯一新增 `@Published`（22 调整为 23），无 `didSet`，无选中历史。`sortedRows` 仍是今天那条 `visibleRows` + `tableSort` 公式，不另发布。Top 的 `onChange` 只进 `revealTopApp(request:proxy:)`：同步门是 `vm.sortedRows.contains(where: { $0.pid == request.pid })`，`main.async` 里只 `scrollTo(request.pid, anchor: .center)`。43 不在这份投影里则不滚动，也不改滚选中 9。旧 `revealProcessListTarget` 仍只服务 `processListScrollTarget` 的 `onChange` 与 `onAppear`。不宣称 SwiftUI 合成、真实居中，或 async 间隙里行集不变
- [ ] 不改 quit store / session。选中数值变化时仍是现成 `followListSelection`：活的新 pid 成为主体；不保证详情当拍出现；旧的不可用记录留在 store。同 pid 的 OFF 不给选中带来副作用
- [ ] 名称过滤谓词、上涨谓词、清空方法的两条语句、N=5、Sampler 都不改。后续样本不持续改写这次 filter
- [ ] 实现 PR 有真实的编译失败红，以及 Linux 上 reducer 与源码接线的日志。这些日志不是 Mac 点卡，也不是 Xcode 已编译

## Linux 已测与未验

本 PR 不跑测试。实现 PR 在 Linux 上能执行的是 SamplingCore 里的 `TopAppLocation.plan`、`ProcessSelection.acceptedPid`、`ProcessNameFilter`、`MemoryGrowthRisingFilter.ordered`。VM 与 `ProcessTablePane` 不在这个目标里，调用顺序和 `onChange` 用源码阅读断言。那份阅读不证明 MainActor 上跑过 VM。

`TopConsumer.leading` 在被排除的 `Views/` 里。代表 pid 43 是阅读 `>=` 与夹具行序得到的输入，不是 Linux 去编译视图类型。

未验，不挡本设计合并，实现 PR 在 Linux 上也不能把它们勾成已过：

- Mac 上点这张卡、SwiftUI `List` 重建、高亮、真实滚到居中、过期 id 的实际处理
- 新 pid 时旧 helper 与 `revealTopApp` 两次 `scrollTo` 调度是否被合成成一次视觉滚动
- 源码接线不等于点击、真的滚动或视口里已经看见该行
- Xcode 编译 App，以及 `project.pbxproj` 下的实际运行
- 本设计 PR 没有 Mac 日志，也不做手势埋点

实现等本设计合并 + Grok merge gate 后再写 Swift。本 PR 不写 Swift、不写测试、不合并。

## 二十期实现期全量回归勘误

上文「十五期那条计数是唯一数值更新」是开写时的源码事实漏列，不是第二处产品范围。`MemoryDashboardVM.swift` 上 `@Published` 的字面总数，在基线里同时被下面五份既有测试守护。二十期只新增 `topAppLocateReveal` 这一处发布属性，所以五处都是同一个 22→23，不是五次行为扩张，也不改各自原来的域断言。

| 文件与方法 | 原来守护的域 | 本次数值 |
| --- | --- | --- |
| `MemoryPageFilterClearWiringSourceTests`（十五期清空；方法体仍只断言那两条清空语句） | 清空接线。`didSet` 仍为 2，清空语句不改 | 22→23 |
| `MemoryDashboardVMSortWiringSourceTests.testPhase19DiskHeadersAreLiteralColumnsAndThisIsNotGUI` | 十九期磁盘读/写分列。表头、比较器、磁盘字段不得变成发布属性 | 22→23 |
| `MemoryDetailSidebarWiringSourceTests.testFrozenGuardPidSwitchAndChartPlaceholderStayUntouched` | 十七期冻结侧栏。`memoryGrowthSlot` 门、选中时 `detail = nil`、采样曲线不改 | 22→23 |
| `ProcessQuitSessionWiringSourceTests.testVMHoldsOneQuitStoreAndDerivesPhaseFromTheSidebar` | 十六期退出。quit store 仍是一份，`didSet` 仍为 2 | 22→23 |
| `ResourceDetailPageSourceTests.testNewModelsStayOutOfTheSamplerQuitStoreAndVMPublishedSurface` | 十八期资源详情。投影不进入 sampler、quit store，也不进入 `selectPage` / `applySample` / `applyRisingOnlySelection` | 22→23 |

`@MainActor` 仍为 1。这个 1 是 `@MainActor` 属性字面出现次数，不是把注释里的 `MainActor` 字样算进同一条约束，也不是新加一个属性。注释里已有 “on the MainActor”，那不是 `@MainActor`。`didSet` 仍是两处。磁盘表头、退出 store、冻结采样、资源详情和采样免疫都维持原断言。
