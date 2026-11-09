# 内存页可见同名组的行高亮（未实现）

> 落地前的技术约定。它不是实现授权，也不是 `main` 上已经显示的界面。当前界面仍以 [TECH.md](../TECH.md) 里写明的 pid 比较为准。
>
> 产品验收已锁定。题目是：内存页当前选中进程所在可见同名组的行高亮，不是稳定组选择，也不是整组操作。对照提交 `b29b82c9541931626a9a5e4e82385bdb71f41e09`。开写前核对过该提交仍是 `origin/main`，父提交 `3c26ee015a2735e78cce9d2d992d4d4fbb11b68e`。文件号 `34` 只用来接在 `33` 之后，不是期次立项。
>
> 落地后改写 TECH.md 的现状句。本文到那时停改。本机冒烟清单的勾选这次不动。本文档 PR 没有跑 Mac 高亮、List 是否保住选择，或 VoiceOver。这三项不能勾成已验收。

## 和读屏、原生选择的关系

`b29b82c` 上没有必须先改绑定才能写这份约定的阻断。高亮、文字颜色和原生选择是三条通道，不能改一处比较就说它们变成了同一种选中。

`ProcessTablePane` 里：

- `listRowBackground` 在 `selectedPid == row.pid` 时铺 `PulsePalette.selection`，否则清空。这是自绘底色。
- `ProcessLine` 的 `selected` 用同一次比较。为真时，整行文字、网络列和磁盘、能耗单元格改成白色或白色半透明。为假时用原来的主色或次色。
- `accessibilityLabel` 不读 `selected`。标签是名称、CPU、内存，以及当前页才有的网络、磁盘、能耗、唤醒，有徽标时再加徽标说明，最后是线程数。没有「已选中」，没有 pid，也没有成员数。徽标视图自身是 `accessibilityHidden(true)`。
- 这一行没有 `accessibilityAddTraits`，也没有把 `selected` 写成辅助功能的选中特征。
- `List(vm.sortedRows, selection: $vm.selectedPid)` 另有系统选择。行 `id` 是 `row.pid`。`.tint(PulsePalette.selection)` 只影响这条系统选择的颜色。

因此 `ProcessLine.selected` 今天只改墨色，不改读屏句子。把它改成真，不会把代表 pid 写进 `accessibilityLabel`，也不会替系统宣告这行已被选为操作对象。落地时底色和这个墨色必须用同一次判断，避免蓝底上仍是未选中的文字颜色。这次判断不加上 `isSelected`，不改标签文字，不把代表 pid 写进 `selection`。

原生 `List` 选择仍绑定 `selectedPid`。代表变化后这个值和合并行 id 不相等。系统是否仍把某一行报成已选中，源码不能证明。VoiceOver 未验。不允许为了让系统选择看起来连续，去伪造选中特征或改绑定。

## 锁定的行为

只改内存页、且「按 App」生效时，哪一条合并行铺底色和白色文字。不新增选择，不表示整组或代表成了操作对象。

### 复用已有查找

`MemoryMagnitudeVisibleGroup.row` 已在 `b29b82c` 落地。输入仍是这一帧的 `page`、与 `sortedRows` 同一次的 `grouping`、`selectedPid`、`visibleRows`。它先确认选中 pid 在未合并的可见行里，再用该行本帧的 `name` 做 `AppGroupProjection.combine`。返回空表示没有可高亮的组合计。

建议在 `Pulse/Models/` 增加一个无存储的布尔函数，名称实现时再定。它不写 `selectedPid`，不调用 `setSelectedPid`，不采样。

- 查找有值，且该值的 `pid` 等于这条列表行的 `pid`：涂这一行。
- 查找为空：退回 `selectedPid == row.pid`。非内存页、合并关闭、没有选中、选中 pid 不在可见集合，都走这一条。

不缓存上一帧的行或名字。`combine` 返回的 pid 只用来找现有合并行，不得写回 `selectedPid`。

CPU 页即使 `grouping` 为真，查找也返回空，所以仍是 pid 比较。磁盘页、网络页、本机页同样。

### 被动变化

代表换成另一个同名 pid、可见成员进出，或选中进程本帧改了名：只要原 pid 仍在这一帧 `visibleRows` 里，高亮落在包含它的这一帧合并行。N 为 1 时合并行 pid 就是它自己，现有比较已经涂中，新判断也涂中。

原 pid 被滤掉或不在 `rows` 里：不借其它同名行，也不留下上一帧的底色。既有清选中不改。名称过滤仍不参与清选中；「仅上涨」和「仅窗口 App」仍按各自的既有函数清。pid 不在 `rows` 时仍由 `legalListSelection` 清掉。这些都不是新规则。

### 高亮不是操作对象

底色和白色文字只表示这一可见组包含原来的选中进程。大数、占比、口径和「当前可见的 N 个同名进程合计」仍按已落地的内存大数查找。侧栏标题里的 pid、曲线、最近值、峰值和上涨句仍是 `detail.row` 的原 pid。不得把代表 pid 写成已经选中的操作 pid。

计算过程不写 `selectedPid`，不调用 `applyGroupedByAppSelection()`，不调用 `setSelectedPid`，不重采曲线。被动的代表变化之后，退出目标仍是原 pid。普通退出仍无确认框。强制退出确认句仍是「立即退出“显示名”？」，名字仍来自完整 `rows` 里这个 pid。

用户再次点击已经高亮的合并行时，沿用现有 `List` 绑定，把该行当前的代表 pid 写入 `selectedPid`。那一次可以更换 pid 和曲线。本期不拦截这次点击。

## 明确不做

- 不改滚动。`processListScrollTarget` 仍是原 pid 在完整 `rows` 里是否还在。
- 不改 `⌘C`。它仍先按 pid 在 `sortedRows` 里找，找不到再用完整 `rows` 里的原进程。代表变化后复制的仍是原 pid 那一行。
- 不改右键「复制」。它复制的是被点的那一行。
- 不拦截点击，不重构 `List(selection:)`。
- 不改采样、过滤、排序、清选中、上涨徽标、分组键和 `combine`。
- 不加组历史或组曲线。
- 不做 CPU 页的组合计高亮。
- 不改退出目标和确认文案。
- 不改 `accessibilityLabel`，不加选中特征。

滚动、`⌘C` 和右键因此可以继续和高亮行不一致。本文不声称整行交互都已对齐。

## List 绑定的未知行为

代表变化后，`selection` 绑定的 pid 不是任何合并行的 id。应用源码没有在这条路径上把 `selectedPid` 写成 nil 或新代表。SwiftUI 会不会因为没有匹配 id 而把绑定写回 nil，纯函数和源码审查都不能证明。

若真实运行里选择被自动清掉，或被改成别的 pid，这项的端到端验收就不通过。先回报这个最小冲突，另审绑定修正。禁止在实现高亮时顺手改绑定。源码审查和合并这份文档可以先进行。Mac 上高亮是否可见、List 是否保住原 pid、VoiceOver 列，都还没验，不能勾成通过。

## 测试

先用当前实现证明今天的错误结果。缺一个新函数导致的编译失败，不能当成这个错误已经复现。

现状测试只调用已经存在的代码，在当前 `main` 上应当通过：

- 两个同名进程，选中较轻的 pid，内存页且合并为真。`MemoryMagnitudeVisibleGroup.row` 的 pid 是较重的那个。`selectedPid == 该 pid` 为假。这就是今天底色和 `ProcessLine.selected` 的比较。
- 同一次输入上，`ProcessSelection.scrollTarget` 仍是原 pid。`ProcessRowCopy.line` 用完整列表里的原进程时，第二列是这个 pid，不是成员数。
- N 为 1：内存页且合并为真，可见集合里只有选中 pid。`MemoryMagnitudeVisibleGroup.row` 有值，`groupedMemberCount` 为 1，返回的 pid 就是该 pid。`selectedPid == 该 pid` 为真，所以今天的底色比较已经涂中。这不是空查找。
- 合并关闭、页面不是内存、选中为空、选中 pid 不在可见集合：现有查找为空。空查找时的比较仍是 `selectedPid == row.pid`。

新行为测试调用上面的布尔函数。实现时先让函数体就是今天的 `selectedPid == row.pid`，让这条测试能编译，并用断言失败留下错误结果。然后再改成复用 `MemoryMagnitudeVisibleGroup`。不要把「函数还不存在」当作红灯的证据。

该函数至少断言：

- 代表已变且原 pid 仍可见：只有合并行的 pid 为真，原 pid 那一列不再单独为真。调用不产生新的 `selectedPid`。
- 本帧改名后，真值落在新名字的合并行。
- N 为 1：查找返回该 pid 自己的合并行，涂色为真。合并关闭、非内存页查找为空，比较仍是 `selectedPid == row.pid`。
- 原 pid 不在可见集合，旁边另有同名行：不为真。没有选中：不为真。
- 先命中再失配：第二次没有残留的真值。

接线测试读源码，不断言 Mac 画面：

- 底色和 `ProcessLine` 的 `selected` 使用这同一个函数。
- `List` 仍是 `selection: $vm.selectedPid`。
- `accessibilityLabel` 的函数体仍不出现 `selected`，源码里仍没有 `accessibilityAddTraits`。
- `copySelectedProcessRow` 仍读 `selectedRow`。右键仍对 `row` 调用 `ProcessRowCopy.line`。
- `processListScrollTarget` 仍把完整 `rows` 交给 `ProcessSelection.scrollTarget`。
- `applySample` 不因此调用 `setSelectedPid` 或 `applyGroupedByAppSelection`。

这些测试不是 Mac 高亮验收，也不是 VoiceOver 验收。
