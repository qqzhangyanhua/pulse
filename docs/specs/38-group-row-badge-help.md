# 内存页组行上涨徽标说明追加受评 PID（未实现）

> 已被取代：组行上已有的上涨徽标 help 已经接上受评 PID。当前文字以 [TECH.md](../TECH.md) 为准。下面的正文是落地前的约定，不再改。

> 落地前的技术约定。它不是实现授权，也不是 `main` 上已经改变的帮助文字。当前列表徽标和「仅上涨」开关仍以 [TECH.md](../TECH.md) 为准：两边读的都是 `MemoryGrowthListCopy.help` 这一整句，里面没有 PID。
>
> 产品验收已锁定。本文只约定：内存页按 App 的组行上，原本已经出现的「上涨」徽标，在原 help 后面追加一句受评 PID。对照提交 `f91d1203f8d83c00e80077be4388b2fc8a183249`。开写前核对过该提交仍是 `origin/main`，父提交 `fcd97bdabf2afe1b379dff0132c42a21a50f0013`。没有更晚提交。文件号 `38` 只用来接在 `37` 之后，不是期次立项。
>
> 落地后改写 TECH.md 的现状句。本文到那时停改。本机冒烟清单的勾选这次不动。本文档 PR 没有跑 Mac 悬停，也没有跑 VoiceOver。静态测试不能代替这两项。

## 今天的徽标说明

`MemoryGrowthListCopy.help` 是这一整句：

`完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期内存占用序列判断趋势。`

`title` 仍是「上涨」。`MemoryGrowthList.badge(page:rowPid:seriesByPid:)` 只在页面是 `.memory`、`seriesByPid` 里有这个 `rowPid`、并且 `MemoryGrowthSignal.evaluate` 为 `.rising` 时返回徽标。返回的 `help` 就是上面这句静态文字。不足、平坦、pid 不在这张图里、以及其它页，都是空，列表不画徽标。

`MemoryDashboardVM.memoryGrowthListBadge(for:)` 把传入的 pid 原样交给 `badge`。`ProcessTablePane` 对 `sortedRows` 的每一行调用 `memoryGrowthListBadge(for: row.pid)`。按 App 合并之后，这一行的 `row.pid` 是 `AppGroupProjection.combine` 的代表。`combine` 把 `groupedMemberCount` 写成 `members.count`，一个成员也是 `1`，不是空。未合并的 `ProcessRow` 这个字段默认是空；`apply(grouped: false)` 原样返回这些行。

徽标有两处读者，读的是同一个字段。`MemoryGrowthRisingBadge` 用 `.help(badge.help)`，并 `.accessibilityHidden(true)`。父行 `ProcessLine` 是 `.accessibilityElement(children: .ignore)`，只在 `if let growthBadge` 时 `parts.append(growthBadge.help)`。没有徽标就不追加。短标签是 `Text(badge.title)`，不进这句 help。

「仅上涨」开关在 `MemoryDashboardView` 上单独 `.help(MemoryGrowthListCopy.help)`。它不读 `badge.help`。

Top5 序列、80 点、8 MiB、60% 间隔、名称过滤、「仅上涨」保留、窗口过滤、合并、排序、采样、选中、侧栏「这条趋势属于 PID …」和曲线都不在这句 help 的赋值里。侧栏那句和列表这句不是同一处文字。

## 锁定的行为

只改组行上那枚已经存在的徽标的 `help` 字符串。

同时满足才追加：

1. `MemoryGrowthList.badge` 按今天的规则已经返回徽标。没有徽标就不造说明，也不因此新画一枚徽标。
2. 这一行是内存页按 App 合并后的组行。判断是 `groupedMemberCount != nil`。`1` 也算组行。
3. 追加的 PID 是这次 `badge` 实际拿去查 `seriesByPid` 的那个 `rowPid`。列表调用处这个数就是 `row.pid`。不读 `selectedPid`。

追加的句子是：`此上涨判断针对 PID 123，不代表同名组合计趋势。` 其中 `123` 是上面的 `rowPid`。把它直接接在 `MemoryGrowthListCopy.help` 现有结尾的后面，不再插分隔符。短标签仍是「上涨」。

`MemoryGrowthListCopy.help` 的静态字面量不改。开关继续 `.help(MemoryGrowthListCopy.help)`，所以工具栏帮助仍是没有 PID 的那一整句。

非组行的 `groupedMemberCount` 为空。即使内存页上这行已有徽标，`help` 仍是静态那一整句。合并关闭时走的就是这些行。其它页的 `badge` 今天就是空；CPU 页虽然也会合并出 `groupedMemberCount`，列表徽标仍不出现，不追加这句。

代表换成另一个 pid 之后，下一行的 `row.pid` 就是新代表，徽标改查这个 pid 的序列。句子里的 PID 跟着这个新的 `row.pid`。`selectedPid` 可以仍是组里的另一个人，句子不写他。原来的代表不再上涨、新代表有徽标时，句子只出现在新行上。新代表没有徽标时，这一行不追加说明。

悬停和整行读屏继续共用这一份 `badge.help`。组行命中时，这一份已经是「原句 + PID 句」。不在 `accessibilityLabel` 里再拼一次 PID 句，不为这句新增无障碍元素，不去掉徽标的 `.accessibilityHidden(true)`，不改父行的 `children: .ignore`。这样整行只朗读一次完整说明，徽标本身不单独朗读。

## 明确不做

- 不改 `MemoryGrowthListCopy.help` 和 `title`，不改「仅上涨」开关的 help。
- 不改 Top5 的选取、80 / 8 MiB / 60% 的判断、过滤、合并、排序和采样。
- 不改选中、侧栏趋势句、曲线。不做同名组的合计曲线。
- 不给没有徽标的行、非组行和其它页追加 PID 句。
- 不新增独立的读屏元素，不让徽标和父行各读一遍。

## 测试

先用已经存在的函数取出今天的完整 help，再断言它等于「原句加 PID 句」。缺一个新符号导致的编译失败，不能当成这句话已经复现。改 `MemoryGrowthListCopy.help` 的字面量会让开关一起变，也不能用来通过。

在当前 `main` 上能编译、并且应当失败的断言：用 `MemoryGrowthListBadgeTests` 里已有的上涨序列造法，`count` 为 `MemoryGrowthSignal.minSamples`、步长 `1_048_576`，`evaluate` 已是 `.rising`。`AppGroupProjection.combine` 出一组，`groupedMemberCount` 非空，代表 pid 取 `combine` 的 pid。`MemoryGrowthList.badge(page: .memory, rowPid: 代表, seriesByPid: [代表: 序列])` 的 `help` 就是今天的完整 help，等于 `MemoryGrowthListCopy.help`。预期字符串是这个静态 help 直接接上 `此上涨判断针对 PID 代表，不代表同名组合计趋势。`。`XCTAssertEqual(今天的 help, 预期字符串)` 失败，因为两句不相等。失败原因是字符串不同，不是找不到类型。

现有 `testLockedCopyIsShortBadgeAndCalmHelp`、`testRisingTopFiveMemoryRowShowsTheBadge` 和 `testUnselectedTopFiveRisingRowStillShowsTheBadge` 仍要求三参数 `badge` 的 help 等于静态原句。这些期望保持。它们锁的是非组行和开关共用的那一句。

组行要变绿时，另做一个纯函数，入参是已经返回的徽标 help、`groupedMemberCount` 和这个 `rowPid`。函数先原样返回传入的 help，让「它等于原句加 PID 句」仍然失败。然后再只在 `groupedMemberCount != nil` 时追加。视图把结果放进这一行仅有的那份 `MemoryGrowthListBadge.help`。悬停和父行继续只读这个字段。

同一条相等断言覆盖：

- N 为 1：`combine` 一个成员，`groupedMemberCount` 是 `1`。最终 help 是原句加该 pid 的 PID 句。
- 多个成员：`groupedMemberCount` 大于 1。PID 是代表，不是较轻的那个成员。
- 代表切换：同一组先以 pid 9 为代表，句子含「PID 9」；内存读数让代表变成 pid 4 之后，句子含「PID 4」。旁边的 `selectedPid` 保持另一个数，句子里不出现它。
- 没有徽标：序列不足、平坦，或 pid 不在 `seriesByPid` 里。`badge` 仍是空。不生成带 PID 的 help。
- 合并关闭：行的 `groupedMemberCount` 为空，已有徽标的 help 仍等于静态原句。
- 其它页：`badge` 在 `.cpu` 等页面仍是空。CPU 上即使 `groupedMemberCount` 非空，也不出现 PID 句。
- 开关：`MemoryGrowthListCopy.help` 仍是没有 PID 的原句。`MemoryDashboardView` 仍是 `.help(MemoryGrowthListCopy.help)`。

接线只读源码：`parts.append(growthBadge.help)` 仍只有一处，`.help(badge.help)` 仍在徽标上，`.accessibilityHidden(true)` 仍在，父行仍是 `children: .ignore`。`ProcessTablePane` 不出现这句 PID 文案的字面量。`accessibilityLabel` 不在 `growthBadge.help` 之外再拼同一句。`memoryGrowthListBadge(for:)` 仍把 `row.pid` 交给查找，不改成 `selectedPid`。

这些测试不是 Mac 悬停验收，也不是 VoiceOver 是否只朗读一次的验收。
