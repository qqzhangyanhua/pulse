# 内存页按 App 复制当前可见组行（未实现）

> 已被取代：过滤框没有焦点时，内存页按 App 的复制已经写出当前可见组行。当前行为以 [TECH.md](../TECH.md) 为准。下面的正文是落地前的约定，不再改。

> 落地前的技术约定。它不是实现授权，也不是 `main` 上已经写出的剪贴板。当前复制仍以 [TECH.md](../TECH.md) 里的 `selectedRow` 路径为准。
>
> 产品验收已锁定范围「内存按 App 时复制当前可见组行」。产品接受组格式的第二列是成员数 N，不另留操作 pid。复制的是展示数据，不迁移选择，也不改退出对象。对照提交 `39275dd5d327991e740ba24d0a4760317b1b2317`。开写前核对过该提交仍是 `origin/main`，父提交 `61ddbe476a937cbbe8353af7cd6d8085e5afc273`。文件号 `35` 只用来接在 `34` 之后，不是期次立项。
>
> 产品锁定前核对过 `selectedRow`、`visibleRows`、`sortedRows`、`MemoryMagnitudeVisibleGroup`、`ProcessRowCopy` 和右键。⌘C 与菜单按钮的入口、以及文字焦点路由，是这份稿对照源码补上的，不能写成产品已经核过。入口和锁定范围一致，没有必须先改焦点系统的阻断。
>
> 落地后改写 TECH.md 的现状句。本文到那时停改。本机冒烟清单的勾选这次不动。本文档 PR 没有跑 Mac 剪贴板、文字焦点、List 是否保住原 pid，或 VoiceOver。若运行中选择被清掉，因而没有可复制的行，不能把端到端验收说成通过。

## 两个入口实际是一颗按钮

`PulseWindowCommands` 用 `CommandGroup(replacing: .pasteboard)` 放进一颗 `Button("复制")`。它不在「视图」菜单里。

- `nameFilterFocused != true` 时，这颗按钮带 `.keyboardShortcut("c", modifiers: .command)`。按 `⌘C` 和点这颗菜单按钮都调用 `copySelectedProcessRow`。
- `nameFilterFocused == true` 时，同一颗按钮不带快捷键。文字框自己接收 `⌘C`。按钮若仍被点到，`copySelectedProcessRow` 的第一句把动作交给 `NSText.copy`，然后返回。这条分支里没有 `ProcessRowCopy`，也不写 `NSPasteboard`。

没有第二颗菜单命令。右键是 `ProcessTablePane` 里另一颗 `Button("复制")`，直接对被点的 `row` 调用 `ProcessRowCopy.line`。本期不改右键。

落地只改 `copySelectedProcessRow` 在焦点判断之后选哪一行。两个入口因此用同一次解析。焦点为真的分支、快捷键是否挂上，都保持今天的写法。

## 锁定的行为

只在页面是 `.memory` 且「按 App」生效、并且原 `selectedPid` 还在这一帧 `visibleRows` 里时，复用 `MemoryMagnitudeVisibleGroup.row`。它用该可见行本帧的 `name` 做 `AppGroupProjection.combine`。复制文本用这个返回行调用现有的 `ProcessRowCopy.line(page:row:)`。

内存页这一行的字段是：名称、成员数或 pid、CPU、内存、线程。命中时第二列是 `groupedMemberCount`，其余列是该合并行自己的读数。缺数仍是「—」。这与对同一帧、同一合并行按右键得到的整行相同，不只是内存一列。

代表换成同名的另一个 pid，或选中进程本帧改了名：只要原 pid 仍在这一帧可见集合里，复制的就是这一帧的那个合并行。N 为 1 时查找有值，第二列是 `1`，不是空查找。原 pid 本来就是代表时，`selectedRow` 已经是这行，结果不变。

查找为空时，一律仍用现有 `selectedRow`：先 `sortedRows.first { $0.pid == selectedPid }`，没有再用 `rows.first`。原 pid 被藏起或不在列表里时，不借其它同名行，也不留下上一帧的合并行。没有 `selectedRow` 时，函数在写剪贴板之前返回。合并关闭，或页面不是内存，查找为空，走这条旧路径。本机页和 GPU 仍在写入前返回。

这次解析不写 `selectedPid`，不调用 `setSelectedPid`，不换详情曲线，不改退出目标。用户再点击合并行时，仍由现有 `List` 写入该行 pid。

`selectedRow` 的定义不改。它继续表示按 pid 找到的那一行，不改成永远返回合并行。

## 明确不做

- 不改右键。
- 不改 `ProcessRowCopy` 的列，不加单独的操作 pid 字段。
- 不改滚动，不改「占用最多的 App」的揭示。
- 不改 `List` 绑定，不改 `accessibilityLabel`，不加选中特征。
- 不改过滤和清选中。
- 不把文字焦点时的 `⌘C` 改成进程行。不借本项改焦点系统。
- 不做 CPU 页的组复制。
- 不做整个 App 的另一套汇总，不加组曲线。
- 不优化 #118 里每一行重复 `combine` 的高亮查找。

## 测试

先用已经存在的类型证明今天的复制和合并行不同。缺一个新类型导致的编译失败，不能当成这个差异已经复现。

在当前 `main` 上能编译、并且应当失败的断言：两个同名进程，选中较轻的 pid，内存页且合并为真。按今天的规则取出行，也就是合并后的 `sortedRows` 里没有这个 pid、再退回未合并行。`ProcessRowCopy.line(page: .memory, row:)` 的整行与 `MemoryMagnitudeVisibleGroup.row` 返回行的整行不相等。第二列一个是 pid、一个是成员数；CPU、内存、线程也各自不同。期望改成相等。这就是今天 `copySelectedProcessRow` 的回退结果。

新解析先写成今天这个回退，让上面的相等断言失败。然后再在内存页且合并生效、查找有值时改用返回行。不要先造一个不存在的类型来获得红灯。

解析至少覆盖：

- 两个入口只调用这一次解析。源码里快捷键挂在非焦点分支的同一颗按钮上，按钮动作是 `copySelectedProcessRow`。
- 命中时整行每个字段都等于该合并行的 `ProcessRowCopy.line`，包括 CPU 和线程，不只内存。
- 连续两次：第一次命中，第二次原 pid 不在可见集合。第二次等于当时的 `selectedRow` 行，不保留第一次的合计。
- N 为 1：查找有值，第二列是 `1`。
- 原 pid 就是代表：与今天命中 `selectedRow` 的合并行相同。
- 本帧改名：按新名字的合并行。
- 原 pid 不在可见集合，旁边另有同名行：用 `selectedRow` 的原进程行，不借用。
- 没有 `selectedRow`：不产生进程行。
- 页面不是内存，或合并关闭：查找为空，行与今天的 `selectedRow` 相同。

接线保持这些现有事实：焦点分支在 `NSPasteboard` 之前返回，并且不含 `ProcessRowCopy`；非焦点分支才有 `⌘C`；本机页和 GPU 在写入前返回；没有 `selectedRow` 的返回仍在写入之前；右键仍是 `ProcessRowCopy.line(page: vm.selectedPage, row: row)`；`selectedRow` 仍先 `sortedRows` 再 `rows`；`applySample` 不因此调用 `setSelectedPid` 或 `applyGroupedByAppSelection`。

`ProcessRowCopyWiringSourceTests` 今天锁着 `guard let row = dashboard.selectedRow else { return }` 和随后的 `row: row`。落地时可以改这一处断言的变量名，但不得放宽焦点分支、空选中返回和右键那三条。

这些测试不是 Mac 剪贴板验收，也不是文字焦点或 VoiceOver 验收。
