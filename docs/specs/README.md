# 设计稿归档

每一期落地前的需求或技术设计稿。这些文件写完后不再修改，**只作历史参考，不作为决策或实现依据**。

信息冲突时按这个顺序取信：

1. 代码（`main` 上的实现）
2. [ADR](../adr/)：口径和设计决定
3. [TECH.md](../TECH.md)：当前实现；[PRD.md](../PRD.md)：当前范围
4. 这里的归档稿

归档稿开头的「已被取代」列出已知过时的决定，但不保证列全。要引用归档稿里的规则，先到代码或 TECH.md 里确认它仍然有效。

| 文件 | 内容 |
| --- | --- |
| [00-prd.md](00-prd.md) | 一期需求文档 |
| [01-memory-mvp.md](01-memory-mvp.md) | 一期：内存单页 MVP（已被取代：内存口径） |
| [02-menubar-and-cpu.md](02-menubar-and-cpu.md) | 二期：菜单栏色点与 CPU Tab |
| [03-growth-signal.md](03-growth-signal.md) | 三期：选中进程增长软信号 |
| [04-network-tab.md](04-network-tab.md) | 四期：网络 Tab |
| [05-disk-tab.md](05-disk-tab.md) | 五期：磁盘 Tab |
| [06-list-growth-badge.md](06-list-growth-badge.md) | 六期：内存列表上涨角标 |
| [07-menubar-strip-b.md](07-menubar-strip-b.md) | 七期：菜单栏轻量条 B |
| [08-polish-smoke.md](08-polish-smoke.md) | 八期：polish 与本机冒烟 |
| [09-growth-badge-top5.md](09-growth-badge-top5.md) | 九期：上涨徽标 Top N=5 |
| [10-menubar-used-memory.md](10-menubar-used-memory.md) | 十期：菜单栏已用内存一行 |
| [11-menubar-top3-select.md](11-menubar-top3-select.md) | 十一期：菜单栏 Top3 点选打开主窗 |
| [12-rising-only-filter.md](12-rising-only-filter.md) | 十二期：「仅上涨」过滤 |
| [13-sampling-retry.md](13-sampling-retry.md) | 十三期：采样失败手动重试合流 |
| [14-menubar-top3-sort.md](14-menubar-top3-sort.md) | 十四期：菜单栏 Top3 跟随内存页排序 |
| [15-filter-empty-clear.md](15-filter-empty-clear.md) | 十五期：内存页过滤空态双清 |
| [16-quit-outcome-per-pid.md](16-quit-outcome-per-pid.md) | 十六期：退出结果按 pid 留存与原处重试 |
| [17-memory-detail-resident.md](17-memory-detail-resident.md) | 十七期：内存详情驻留口径（已被取代：改为内存占用） |
| [18-resource-detail-projection.md](18-resource-detail-projection.md) | 十八期：资源 Tab 详情按当前资源呈现 |
| [19-disk-read-write-sort.md](19-disk-read-write-sort.md) | 十九期：磁盘读取 / 写入分列排序 |
| [20-top-app-locate.md](20-top-app-locate.md) | 二十期：「占用最多的 App」定位 |
| [21-history-curve-missing.md](21-history-curve-missing.md) | 二十一期：历史曲线当前值缺失说明 |
| [22-growth-help-copy.md](22-growth-help-copy.md) | 二十二期：上涨帮助句（已被取代：措辞改为内存占用） |
| [31-save-current-snapshot.md](31-save-current-snapshot.md) | 保存当前快照：落地前技术设计。行为已落地，以 TECH.md 为准。文件号不是期次立项 |
| [32-memory-detail-attribution.md](32-memory-detail-attribution.md) | 内存详情数值与曲线归属说明：落地前技术约定。行为已落地，以 TECH.md 为准。文件号不是期次立项 |
| [33-memory-magnitude-visible-group.md](33-memory-magnitude-visible-group.md) | 内存详情大数在代表变化后仍匹配当前可见同名组：落地前技术约定。行为已落地，以 TECH.md 为准。文件号不是期次立项 |
| [34-memory-group-row-highlight.md](34-memory-group-row-highlight.md) | 内存页当前选中进程所在可见同名组的行高亮：落地前技术约定。行为已落地，以 TECH.md 为准。文件号不是期次立项 |

二十三期以后已经落地的工作没有单独的设计稿，需求和结论记录在对应的 issue 和 PR 里。下表收到二十八期；更后的期次以对应 PR 为准，不在这里补写。

`31-save-current-snapshot.md` 登记在上表只为了能找到它。首版的预览、前 5 进程和本机 HTML 文件已在稿内写死。实现落地后，当前行为以 TECH.md 为准；这份稿和其它归档一样不再改。

`32-memory-detail-attribution.md` 同样只为了能找到落地前的约定。行为已落地，当前界面以 TECH.md 为准；稿本身不再改。

`33-memory-magnitude-visible-group.md` 登记在上表只为了能找到它。行为已落地，当前界面以 TECH.md 为准；稿本身不再改。

`34-memory-group-row-highlight.md` 登记在上表只为了能找到它。行为已落地，当前界面以 TECH.md 为准；稿本身不再改。本机冒烟清单的勾选不因这份稿改变。

| 期数 | 内容 | PR |
| --- | --- | --- |
| 二十三期 | 拆分超限的详情侧栏与内存页 VM | #75 |
| 二十四期 | 退出后显示已用内存约减少多少 | #76 |
| 二十五期 | 键盘快捷键与主窗口尺寸记忆 | #77 |
| 二十六期 | 系统降频提示 | #74 |
| — | 菜单栏最忙一核、交换用量、仅窗口 App、按 App 合并、系统进程说明 | #78–#82 |
| 二十七期 | 本机页总览 | #83 |
| 二十八期 | 进程内存改用内存占用口径 | #88（#84–#87） |

新的设计稿按 `NN-主题.md` 加在归档表里，并登记一行。落地后把结论写进 TECH.md，设计稿本身不再改。
