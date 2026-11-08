# Pulse 九期技术设计（首包：内存列表上涨徽标密度 Top N=5）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 9 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。
>
> 已被取代：徽标悬停不再复用「近期内存持续上涨」，二十二期起与「仅上涨」开关共用 Top5 口径说明。
>
> 已被取代：十四期起，切到其它页时 Top5 仍按最后一次内存页排序计算。

> 一期至八期正文不改写。六期写明「角标仅选中行 `.rising`」、八期冒烟第 2 条仍按「仅选中行」回归——**本文只覆盖那条密度延期**：把已有的内存列表「上涨」徽标从「仅选中」扩成「当前排序 Top N=5 ∩ `.rising`」。不新开增长算法、不扫全表、不改 Sampler 周期。GPU Tab、无界全表 series / ring、点击徽标跳详情、恐吓文案 / 「泄漏」、Helper / XPC、新 Tab、Electron、自动杀、新 entitlements 仍不做。

**已锁定**：九期 = **B（密度）**。仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。徽标**只复用** `MemoryGrowthSignal.evaluate`，**禁止**第二套斜率 / 泄漏算法、禁止 rss 两点差 hack。列表徽标出现条件改为：该行 pid ∈ **当前内存页排序 Top N=5** 且 `evaluate == .rising`。文案 / 样式复用六期：本体「上涨」；hover / accessibility「近期内存持续上涨」；次要文字色；无红闪。不是滚动视口「看得见的行」，不是无界全表 ring。详情侧栏「内存趋势」三态（三期）一字不改。选中 pid 若不在 Top 5：列表徽标不亮，详情照常。N=5 **硬封顶**。允许 **有界** Sampler 增量：为当前 Top 5 个 pid 维护短 series（同一 `sample()` tick / 同一周期，**不是**新采样周期）；pid 跌出 Top 5 则立刻 drop / clear。零新 entitlement / Helper / XPC。只改内存 Tab 列表。

来源：用户 + 产品锁定的九期 Must（八期收尾已合 #28）；对照现实现（`MemoryGrowthList.badge` 仍是 `页 == .memory && rowPid == selectedPid && evaluate(detailSeries) == .rising`；`ProcessTablePane` 只把 `vm.memoryGrowthListBadge` 传给选中行；Sampler 只为选中 pid 写 `selectedMemorySeries`，`seriesLimit = 90`；`ProcessTableSort` 内存页默认内存降序）。

## 范围（相对一二三四五六七八期）

| 项 | 一二三四五六七八期 | 九期首包 |
| --- | --- | --- |
| 定位 | 六期：列表徽标仅选中行 `.rising`；八期按该条冒烟 | **密度（B）**：同一枚徽标，出现条件改为 Top N=5 ∩ `.rising` |
| 增长算法 | 三期 `MemoryGrowthSignal.evaluate`；六 / 八期禁止第二套 | **仍只调用这一份**。无 rss 两点差、无新阈值 |
| Sampler series | 三期起只选中 pid `selectedMemorySeries`；六 / 八期锁零 Sampler / 禁全表 ring | **允许有界增量**：当前 Top N=5 各一条短 series。同一 tick / 同一周期。N=5 硬封顶。**不是**新采样周期，**不是**无界全表 ring |
| 列表徽标可见性 | 六期 / 八期：仅选中行 + `.rising` | **做（本刀）**：pid ∈ 当前排序 Top 5 且 `.rising`。选中但不在 Top 5 → 列表不亮 |
| 详情「内存趋势」 | 三期三态（上涨 / 不足可见 / none 不占位） | **不改**。选中 pid 在不在 Top 5 都不影响详情 |
| 文案 / 样式 | 六期：「上涨」+「近期内存持续上涨」；次要色；无红闪 | **原样复用**。不新作文案、不改色 |
| 滚动视口可见行 | — | **不做**。不是「屏幕上看得见的行都评」 |
| 点击徽标跳详情 | 六期角标不可点 | **仍不可点**。点行选中仍走现成列表选中，不因徽标跳转 |
| CPU / 网络 / 磁盘列表行 | 六期不画 | **仍不画** |
| GPU Tab | 灰置 | **仍灰置** |
| 采样周期 | 前台 ~1.5s，后台 ~2–3s | **不改**。Top 5 series 吃同一 `sample()` |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 / 恐吓文案 | 不做 / 禁止 | **仍禁止**。永不写「泄漏」 |

一二三四五六七八期验收与公证路径不因本文重开。八期冒烟第 2 条「仅选中行」由本文覆盖；详情三态、菜单栏 B、网络 / 磁盘文案不重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

- `SwiftUI Views`（`ProcessLine`，仅内存页）←观察→ 同一 `MemoryDashboardVM`
- 详情侧栏继续走现成 `memoryGrowthSlot` / `MemoryGrowthSidebar`——**本刀不改详情三态**
- 列表徽标仍是对同一 `MemoryGrowthSignal.evaluate` 的投影，不是第二条判定
- Sampler 同一 `sample()` tick、同一周期（前台 ~1.5s / 后台 ~2–3s）、同一 `seriesLimit`（现 90）
- 选中 pid 的 `selectedMemorySeries` **继续按三期维护**（详情曲线 + 三态）
- **有界增量**：再为「当前内存页排序 Top N=5」维护最多 5 条短 series。pid 跌出 Top 5 立刻 drop / clear。N=5 硬封顶
- 选中 pid ∈ Top 5 时，详情与列表可共用同一段 series，禁止为同一 pid 采两遍
- 选中 pid ∉ Top 5 时：详情 series 照写，列表徽标不亮

约束：

- 不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询、不改采样周期。
- 不改 `Pulse.entitlements`、不改公证脚本、不改菜单栏 A / B。
- 自身占用仍优先：有界 5 条 series，禁止无界全表 ring。
- `ProcessLine` 跨 Tab 复用——接线必须按页门控，禁止「所有 Tab 顺手亮徽标」。
- 增长信号仍不进 `ProcessRow` 采样字段。不要给每行存 `isRising`。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `MemoryGrowthSignal.swift`、`MemoryGrowthList`、`MemoryDashboardVM.memoryGrowthListBadge`、`ProcessTablePane`、`MemorySampler`。本刀必须按「已有 / 没有」落笔，**禁止**为了多行亮灯再发明一套增长数学，也**禁止**把六期的「零 Sampler」误读成九期红线——六期只服务选中行，密度刀需要有界 series。

| 现字段 / 调用 | 文件 | 九期怎么用 |
| --- | --- | --- |
| `MemoryGrowthSignal.evaluate` | `Models/MemoryGrowthSignal.swift` | **原样调用**。`minSamples` / `deltaThreshold` / `riseFloor` 不改 |
| `MemoryGrowthListCopy` / `MemoryGrowthRisingBadge` | 同上 + `ProcessTablePane` | 文案「上涨」/「近期内存持续上涨」、次要色胶囊 **原样**。无红闪、不可点 |
| `MemoryGrowthList.badge` | 同上 | **改谓词**：`页 == .memory && pid ∈ top5 && evaluate(该 pid series) == .rising`。不再要求 `rowPid == selectedPid` |
| `ProcessDetail.memorySeries` / `selectedMemorySeries` | Sampler 选中 pid ring | **详情唯一输入**。三期清 ring / 切进程规则不改 |
| Top N=5 series | **现无** | **本刀有界增量**。当前排序前 5 个 pid 各一条；跌出即清 |
| `ProcessTableSort` | `CPUPage.swift` | 内存页当前表头排序（默认内存降序）决定 Top 5 集合 |
| `ProcessRow` | `MemoryModels` | **仍无**增长字段。不要加 `isRising` |
| 六 / 八期「仅选中行」 | `ProcessTablePane` `selectedPid == row.pid ? badge : nil` | **拆掉这道门**。改成按行查 Top5∩rising |

**缺口**：Sampler 今天只有选中 pid 的 series，未选中行评不出 `.rising`。这是六期故意留下的范围，不是算法缺口。九期要密度，就必须给当前 Top 5 攒短 series——**有界、可丢、N=5 硬封顶**。不要借缺口做成全表 ring，也不要用相邻两帧 `memoryBytes` 冒充上涨。

因此本刀：

1. **有界 Sampler 增量**（不是新周期）：维护 Top N=5 短 series；跌出即 `removeAll` / drop；传入超过 5 个 pid 也只留 5 个。
2. 选中 pid 详情 series **继续独立按三期走**（可与 Top 5 共用同一缓冲，不可双 tick）。
3. 模型侧纯函数 / VM 派生：`pid ∈ Top5 && evaluate == .rising` → 六期角标文案，否则 `nil`。不足 / none / 不在 Top 5 / 非内存页都是 `nil`，角标位不写「—」。
4. **不要**给 `ProcessRow` 加 `isRising` 采样字段。
5. 选中但不在 Top 5：列表无徽标；详情三态仍工作。这是本刀范围，不是漏做。

### Top N=5 定义（写死）

| 是 | 不是 |
| --- | --- |
| 内存页当前 `ProcessTableSort` 下、已采 `rows` 的前 5 个 pid（默认内存降序） | 滚动视口里看得见的行 |
| N=5 硬封顶；不足 5 条就按现有条数 | 无界全表 ring / 全表 series |
| 改表头排序或名次变化导致跌出前 5 → 立刻 drop / clear 该 pid series | 名称过滤表 `visibleRows`（过滤只影响画不画那一行，不改 Top 5 集合） |
| 仅内存 Tab 列表画徽标 | CPU / 网络 / 磁盘 / GPU 页、菜单栏 |
| 人在其它页时：不按 CPU / 磁盘排序扩 series | 把七期弹出条 Top3 或过滤表误当成 Top 5 |

离开内存页期间：Sampler **不要**跟 CPU / 磁盘表头走。续写用「最近一次内存页排序」的 Top 5，或回退到内存降序；切页本身不是清 series 的理由。回到内存页后按当时表头重新取前 5，跌出的照常 drop。

选中 pid 永远继续写详情 series，无论它在不在 Top 5。

## 建议工程顺序

1. **Sampler / 模型**：有界 Top 5 series + 纯函数「pid ∈ Top5 && `evaluate == .rising` → 六期角标文案，否则 `nil`」。`swift test` 钉：Top5 且 rising 亮；Top5 外不亮；不足 / none 不亮；排序 churn 跌出的旧 pid 立刻无徽标且 series 被清；只走 `evaluate`、无第二套算法；N 硬封顶 5（传入 6 个也只留 5）。
2. **列表 UI 接线**：`ProcessLine` / `MemoryGrowthListBadge` 从「仅选中」改为按行查 Top5∩rising。视觉、文案、次要色、不可点——与六期同一枚芯片。
3. **没有硬伤就不开 polish PR**。有硬伤：一个行为一个最小 fix，不要和 GPU / 全表 ring 捆在一起。

不要先开「新采样周期」PR 或「全表 ring」PR。合并不擅自写代码。

## 可见性（产品 Must）

结论：徽标是「当前排序前 5 里、已经评出上涨软信号」的列表投影。最多 5 枚。

| 条件 | 列表徽标 |
| --- | --- |
| 内存页 + pid ∈ 当前排序 Top 5 + `evaluate(该 pid series) == .rising` | **画**「上涨」（六期同款） |
| `.insufficient`（窗口未满、刚进入 Top 5、刚切排序） | **不渲染**。不是角标上写「—」 |
| `.none`（窗口够但净增不够 / 正步比例低 / 持平） | **不渲染** |
| pid ∉ Top 5（含选中但不在前 5） | **不渲染**。详情三态不受影响 |
| 名称过滤把该行藏起来 | 行不画则徽标不画；**不**因此把该 pid 移出 Top 5 series |
| CPU / 网络 / 磁盘 / GPU 页 | **不渲染** |
| 进程已从已采列表消失 / 跌出 Top 5 | series drop；无残留徽标 |

切排序 / 名次 churn：跌出 Top 5 的旧 pid 不得把上涨徽标带到新位置；新进入的 pid 在不足或 none 期间不得亮。对齐三期「旧上涨不得带到下一进程第一帧」的精神，作用对象从「选中 pid」换成「Top 5 集合」。

详情侧栏三态保持原样：不足仍然可见「样本不足，暂不判断」；列表不把不足态做成徽标。两边读同一 `evaluate`，展示策略不同——这是有意的。

## UI 绑定

结论：只改内存页进程列表行的**出现条件**。视觉锁在六期，本刀不重开设计。

### 位置

- 主入口：内存 Tab 的 `ProcessLine`，贴在进程名附近（轻徽标，**不是**新的可排序列，不参与默认排序加权）。
- 接线从「整表一个 `memoryGrowthListBadge` + 仅选中行传入」改为「按行 pid 查 Top5∩rising」。
- CPU / 网络 / 磁盘列表行：本刀**不画**。
- GPU Tab Out。菜单栏 A / B 不因上涨改色点或进弹出条。
- 点击徽标**不**跳详情、不改选中。点行选中仍走现成 `List` selection。

### 文案 / 样式（复用六期，不改义）

| 表面 | 锁定用词 | 说明 |
| --- | --- | --- |
| 徽标本体 | **上涨** | 与六期同一短词 |
| Hover / accessibility | **近期内存持续上涨** | 与六期同一句 |
| 颜色 | 次要文字色（`.secondary`） | 无红、无闪、无第三档恐吓红 |
| 详情（不改） | 「内存趋势」/「近几分钟持续上涨」 | 三期三态原样 |

禁止出现：泄漏、泄露、leak、危险、告警、异常、中招、需要完全磁盘访问。验收对锁定字符串与实现字符串搜这些词。

### 明确不做（相对本刀）

- GPU Tab；新 Tab。
- 无界全表 series / ring；滚动视口「可见行」扫描。
- 点击徽标 → 跳详情 / 改选中。
- **新 Sampler 采样周期 / cadence**（前台 1.5s、后台 2–3s 不动）。
- Helper / XPC / 登录项；新 entitlements / TCC 全盘。
- 恐吓文案、「泄漏」、假权限墙。
- Electron / App Store 沙盒。
- 自动杀、常驻通知。
- 第二套斜率、rss 两点差、活动监视器式「内存泄漏」列。
- 给不足态画灰徽标或「—」。

## 风险

| 风险 | 应对 |
| --- | --- |
| 忍不住做成无界全表 ring | Top N=5 硬封顶；跌出即清；验收「列表最多 5 枚」 |
| 按滚动视口可见行或过滤表取 Top 5 | 定义表写死：当前 `ProcessTableSort` + 已采 `rows`；不吃 viewport / `visibleRows` |
| 第二套算法（列表用 rss 两点差） | 只允许 `MemoryGrowthSignal.evaluate`；单测钉「无第二套、阈值不改」 |
| 借密度刀改采样周期 | 范围表写死：同一 `sample()` tick / 同一 period |
| 选中但不在 Top 5 时详情也被关掉 | 详情仍走 `selectedMemorySeries`；验收钉「列表灭、详情三态仍在」 |
| 排序 churn 脏徽标 / 旧 series 残留 | 跌出立刻 drop；单测钉旧 pid 无徽标 |
| N 被改成 10 / 可见行数 | 硬编码 5；传入超 5 只留 5 |
| `ProcessLine` 跨 Tab 漏网 | 按页门控；CPU / 网络 / 磁盘验收「无徽标」 |
| 被读成「就是泄漏」 | 六期文案白名单；验收搜「泄漏」「leak」「危险」 |
| 点击徽标跳详情 | 芯片保持不可点；不做 button / tap gesture |
| Helper / 新 entitlement / GPU | 范围表写死不加 |

## 验收（九期首包）

产品 Must：

- [ ] 内存页进程列表：最多 5 枚「上涨」徽标；只出现在**当前排序 Top 5** 且 `MemoryGrowthSignal == .rising` 的行
- [ ] 文案 / 样式与六期相同：本体「上涨」；hover / accessibility「近期内存持续上涨」；次要文字色；无红闪
- [ ] 样本不足 / 无信号 / 持平 / 不在 Top 5（含选中但不在前 5）：**无徽标**，角标位也不写「—」
- [ ] 详情「内存趋势」三态不回退（上涨 / 不足可见 / none 不占位）；选中 pid 在不在 Top 5 都不影响详情
- [ ] 算法仍是三期 `MemoryGrowthSignal.evaluate`；无第二套增长数学、无 rss 两点差
- [ ] 无新 Sampler 周期；Top 5 series 与今日同一 tick / period；N=5 硬封顶；跌出即清
- [ ] CPU / 网络 / 磁盘列表行无此徽标；GPU 仍灰置
- [ ] 永不写「泄漏」/ leak / 「危险」；无自动杀；无假权限墙

明确不做（本包出现即不合格）：

- [ ] 无 GPU Tab、无新 Tab
- [ ] 无无界全表 series / ring；无滚动视口「可见行」扫描
- [ ] 无点击徽标跳详情
- [ ] 无新 Sampler cadence、无 Helper / XPC、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 无恐吓文案、无「泄漏」

共性：

- [ ] 一二三四五六七八期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏 A / B、详情增长软信号、退出链路）。列表徽标可见性以**本文**为准（覆盖六 / 八期「仅选中行」）
- [ ] 冷启动仍默认内存页
- [ ] UI / 单测：Top5∩rising 亮；Top5 外 / 不足 / none 缺席；排序 churn 丢旧 pid；N 封顶 5；拷贝无「泄漏」
- [ ] 不改公证脚本与 entitlements

## 工期

小：半天～1 天量级——按「有界 Sampler / 模型 + 单测 → 列表接线」拆，不是功能周。没有硬伤就不开第三条 polish PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。
