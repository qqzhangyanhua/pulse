# Pulse 六期技术设计（首包：内存列表上涨轻角标）

> **归档，仅供追溯，不作为决策或实现依据。** 这是第 6 期落地前的设计稿，后续期数可能已改动其中的范围、口径、文案和文件位置，下方「已被取代」只列出已知的部分。现行规则以代码、[TECH.md](../TECH.md)、[PRD.md](../PRD.md) 和 [ADR](../adr/) 为准。
>
> 已被取代：「角标只在选中行出现、不给可见进程攒序列」：九期起改为内存页排序前 5 的进程判为上涨就显示，未选中的行也会显示，采样器为这 5 个进程各维护一条序列。
>
> 已被取代：角标悬停说明已改为「完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期内存占用序列判断趋势。」

> 一期至五期正文不改写。三期写明「不做列表角标」、四期 / 五期写明「列表增长角标仍不做（延期）」——**本文只覆盖那条延期**：把已有的 `MemoryGrowthSignal` 上涨态投到内存页进程列表行上，做成轻角标。不新开增长算法、不扫全表、不扩 Sampler ring。GPU Tab、菜单栏弹出条 B、磁盘 / 卷额外项、自动杀、恐吓文案、Helper / XPC、Electron 仍不做。

**已锁定**：仍单进程、单 `MemorySampler` Actor、单 `MemoryDashboardVM`。角标复用三期详情侧栏已经在算的 `MemoryGrowthSignal`（`[ChartSample] →` 三态），**禁止**第二套斜率 / 泄漏算法。角标**只在该行进程已经是 `.rising` 时出现**；样本不足、无信号、持平都不画角标，也不在角标位写「—」。本刀只改**内存 Tab** 列表行。不新开 entitlements、不拆 Helper / XPC、不自动杀。文案冷静，对齐详情「内存趋势」上涨态；永不写「泄漏」。

来源：用户 + 产品锁定的六期 Must；对照现实现（`MemoryGrowthSignal.evaluate` + `MemoryGrowthSidebar.slot` 只服务内存页详情；Sampler 只为选中 pid 维护 `selectedMemorySeries`，切进程清空；`ProcessRow` 无增长字段；`ProcessLine` 跨 Tab 复用、现无角标）。

## 范围（相对一二三四五期）

| 项 | 一二三四五期 | 六期首包 |
| --- | --- | --- |
| 增长斜率 / 判泄漏 | 三期已锁：只软信号，不是泄漏判定 | **仍不做泄漏判定**。算法、阈值、输入序列一字不改 |
| 信号入口 | 只详情侧栏；列表角标延期 | **做**：内存页列表行轻角标，投影已有 `.rising` |
| 数据源 | 选中 pid 的 `memorySeries` | **只复用这条**。不扩成全表时序、不新开采样通道 |
| 列表角标 | 三期禁止；四 / 五期延期 | **做（本刀）**：仅内存列表；仅 `.rising` |
| CPU / 网络 / 磁盘列表行 | 同构 `ProcessLine`，无增长角标 | **仍不画**。产品未要求全 Tab；默认内存-only 保范围最小 |
| GPU Tab | 灰置 | **仍灰置** |
| 菜单栏 | 交互 A：栏上仅压力色点 | **不变**。不做弹出条 B；不因增长改色点 |
| 文案 | 详情：上涨 / 不足 / 静默；禁泄漏 | 角标只用冷静上涨短词；不足 / 无信号**不占位**（与详情不足态不同） |
| Helper / XPC / 登录项 | 无 | **仍无** |
| TCC 全盘 / 新 entitlements | 不申请 / 空 dict | **仍不申请** |
| Electron / App Store 沙盒 | 不做 | **仍不做** |
| 自动杀 / 常驻通知 | 不做 | **仍不做** |
| 压力第三档恐吓红 | 不做 | **仍不做** |

一二三四五期验收、菜单栏交互 A、CPU / 网络 / 磁盘 Tab、详情侧栏三态、公证路径不因本文重开。实现等本设计合并 + Grok merge gate 后再写 Swift。

## 架构

仍单 Target、macOS 14+、非沙盒 Hardened Runtime。菜单栏与各资源页继续共享**同一个** `MemoryDashboardVM` / `MemorySampler`。

- `SwiftUI Views`（`ProcessLine`，仅内存页）←观察→ 同一 `MemoryDashboardVM`
- 详情侧栏继续走现成 `memoryGrowthSlot` / `MemoryGrowthSidebar`——**本刀不改详情三态**
- 列表角标是对同一 `MemoryGrowthSignal` 的**另一处投影**，不是第二条判定
- Sampler 同一 `sample()` tick：选中 pid 继续写入 `selectedMemorySeries`（现 `seriesLimit = 90`）
- **增长信号仍不进 Sampler**。不给全表 `ProcessRow.memoryBytes` 攒多进程 ring

约束：

- 不新开第二套 VM、不新开第二路 `proc_listpids` / Mach 轮询。
- 不改 `Pulse.entitlements`、不改公证脚本、不改菜单栏色点映射。
- 自身占用仍优先：角标是 O(1) 的可见性谓词（对已经算过的信号），不加倍采样。
- `ProcessLine` 已被 CPU / 网络 / 磁盘页复用——接线必须按页门控，禁止「所有 Tab 顺手亮角标」。

### 现模型里有什么（读仓库后的结论）

实现前已对照 `MemoryGrowthSignal.swift`、`MemoryDashboardVM.memoryGrowthSlot`、`ProcessRow`、`MemorySampler`。本刀必须按「已有 / 没有」落笔，**禁止**为了列表亮灯再发明一套增长数学。

| 现字段 / 调用 | 文件 | 六期怎么用 |
| --- | --- | --- |
| `MemoryGrowthSignal.evaluate` | `Models/MemoryGrowthSignal.swift` | **原样调用**。`minSamples` / `deltaThreshold` / `riseFloor` 不改 |
| `MemoryGrowthCopy` / `MemoryGrowthSidebar.slot` | 同上 | 详情继续：`.rising` / `.insufficient` 可见，`.none` 不占位。列表**不**复用不足态文案 |
| `ProcessDetail.memorySeries` | Sampler 选中 pid ring | 角标的**唯一**输入序列 |
| `ProcessRow` | `MemoryModels` | pid / cpu / rss / 线程 / 磁盘速率等。**无**增长字段 |
| Sampler `selectedMemorySeries` | 切 pid `removeAll` | **不扩**成全表 ring |

**缺口**：`ProcessRow` 上没有现成 `growthSignal` flag。这**不是**采样缺口——现有 series + `evaluate` 已能判定**选中行**是否 `.rising`。不要为了「每行都能亮」去给可见进程攒 ring：那会变成第二路时序、违反三期「只有点开的进程有曲线」，也把本刀从天级 UI 拖成采样改造。

因此本刀：

1. **零 Sampler 改动**（无新字段、不拉长 ring、不扫全表）。
2. 模型侧最多加一个纯函数 / VM 派生，例如 `MemoryGrowthListBadge`：`页 == .memory && 该行 pid == selectedPid && evaluate(detailSeries) == .rising` → 返回角标文案，否则 `nil`。
3. **不要**给 `ProcessRow` 加 `isRising` 存成采样字段——那会暗示每行都有独立判定。
4. 未选中行没有 series → 没有上涨信号 → 无角标。这是本刀范围，不是漏做。

### 建议模块 PR 顺序

信号已经在 `ProcessRow` 上？**没有。** 但也不需要先开采样 PR。

合并后工程顺序（一个 UI PR 即可，若暴露层只是几行纯函数）：

1. **小模型暴露 + 列表接线**：`MemoryGrowthListBadge`（或等价）纯函数 + `ProcessLine` 内存页角标 + `swift test`。覆盖：仅 `.rising` 可见；不足 / none / 未选中 / 非内存页都不出现；文案无「泄漏」。

三期算法单测已在。不必再拆「helper PR → UI PR」，除非暴露层长出新阈值（本刀禁止新阈值）。不要把本刀和 GPU / 菜单栏 B / 磁盘卷容量捆在一起。合并不擅自写代码。

## 可见性（产品 Must）

结论：角标是「该行**已经**处于上涨软信号」的列表投影，不是新扫描。

| 条件 | 角标 |
| --- | --- |
| 内存页 + 该行 pid == `selectedPid` + `evaluate(memorySeries) == .rising` | **画**轻角标 |
| `.insufficient`（窗口未满、刚点开、切进程后第一帧） | **不渲染**。不是角标上写「—」，也不是详情那句「样本不足，暂不判断」 |
| `.none`（窗口够但净增不够 / 正步比例低 / 持平） | **不渲染** |
| 未选中行（无 series） | **不渲染** |
| CPU / 网络 / 磁盘 / GPU 页 | **不渲染** |
| 无选中 / 进程已从列表消失 | 随侧栏一起卸掉，无残留 |

切进程：三期已锁「旧上涨不得带到下一进程第一帧」。列表角标同一条：新行在不足或 none 期间不得亮；只有新 pid 自己评出 `.rising` 才亮。

详情侧栏三态保持原样：不足仍然可见「样本不足，暂不判断」；列表不把不足态做成角标。两边读同一信号，展示策略不同——这是有意的，避免每行都闪「—」。

## UI 绑定

结论：只改内存页进程列表行。设计定视觉（色、尺寸、形状、是否 pill / 点）；TECH 锁定**出现条件与文案语气**。

### 位置

- 主入口：内存 Tab 的 `ProcessLine`，贴在进程名附近（轻角标，**不是**新的可排序列，不参与默认排序加权）。
- `ProcessLine` 已按页显示网络列 / 磁盘列。六期再加一个 `showsMemoryGrowthBadge`（或把文案 `String?` 传进去），仅 `selectedPage == .memory` 为真。
- CPU / 网络 / 磁盘列表行：本刀**不画**。产品没有先锁「全 Tab 都亮」；默认内存-only，避免同构行被增长语义污染。
- GPU Tab Out。菜单栏仍交互 A，不做弹出条 B。

### 文案（冷静，已选题，设计可改词不改义）

对齐详情标题「内存趋势」+ 上涨 caption「近几分钟持续上涨」。列表位更短。

| 表面 | 锁定用词 | 说明 |
| --- | --- | --- |
| 角标本体 | **上涨** | 短、冷静、与详情上涨态同义 |
| Hover / accessibility | **近期内存持续上涨** | 比本体多「近期」「内存」，避免被读成 CPU / 磁盘在涨 |
| 详情（不改） | 「内存趋势」/「近几分钟持续上涨」 | 列表不复制整句，以免挤行 |

以上为锁定默认。设计仍可微调用词（不改含义），**不得**写成判定或恐吓。

禁止出现：泄漏、泄露、leak、危险、告警、异常、中招、需要完全磁盘访问。验收对锁定字符串与实现字符串搜这些词。

### 明确不做（相对本刀）

- 自动 `terminate` / 因上涨结束进程。
- 假「需要完全磁盘访问」墙。
- 菜单栏色点随增长变色、弹出条 B、常驻通知。
- 全表扫描、第二套斜率、把 `UsageHistory` 系统总用量误当成进程曲线。
- 活动监视器式「内存泄漏」列或排序加权。
- 给不足态画灰角标或「—」。

## 风险

| 风险 | 应对 |
| --- | --- |
| 忍不住给全表攒 ring / 改 Sampler | 上文缺口写死：不是采样缺口；未选中无角标是范围 |
| 第二套算法（列表用 rss 两点差） | 只允许 `MemoryGrowthSignal.evaluate`；单测钉「同一 series，详情 rising ⟺ 该行角标」 |
| 不足 / 持平画成「—」角标 | 可见性表：只有 `.rising` 渲染；不足与 none 都是 `nil` |
| 切进程脏角标 | 复用三期清 ring；派生随 `selectedPid` / `detail` 卸掉 |
| `ProcessLine` 跨 Tab 漏网 | 按页门控；CPU / 网络 / 磁盘验收「无角标」 |
| 被读成「就是泄漏」 | 文案白名单；验收搜「泄漏」「leak」「危险」 |
| 自动杀 / 新 entitlement | 范围表写死不加 |

## 验收（六期首包）

产品 Must：

- [ ] 内存页进程列表行：仅当该行进程已有 `MemoryGrowthSignal.rising` 时出现轻角标
- [ ] 样本不足 / 无信号 / 持平 / 未选中：**无角标**，角标位也不写「—」
- [ ] 算法仍是三期 `MemoryGrowthSignal.evaluate`（同一 `memorySeries`）；不新开 Sampler 字段、不第二套增长数学
- [ ] CPU / 网络 / 磁盘列表行无此角标；GPU 仍灰置
- [ ] 详情侧栏三态不回退（上涨 / 不足可见 / none 不占位）
- [ ] 角标本体锁定「上涨」；Hover / accessibility 锁定「近期内存持续上涨」（设计可改词不改义）
- [ ] 永不写「泄漏」/ leak / 「危险」；无自动杀；无假权限墙

明确不做（本包出现即不合格）：

- [ ] 无全表 ring / 无第二路采样
- [ ] 无菜单栏弹出条 B；栏上仍只是压力色点；点击仍回内存页
- [ ] 无 Helper / XPC、无 TCC 全盘、无新 entitlements、无沙盒改动
- [ ] 无 Electron、无 App Store 沙盒
- [ ] 无磁盘 / 卷额外项、无活动监视器泄漏列

共性：

- [ ] 一二三四五期验收不回退（内存页、CPU / 网络 / 磁盘 Tab、菜单栏色点、详情增长软信号、退出链路）
- [ ] 冷启动仍默认内存页
- [ ] UI / 单测：角标可见 ⟺ 上涨信号；其余缺席；拷贝无「泄漏」
- [ ] 不改公证脚本与 entitlements

## 工期

小：信号已在详情侧；`ProcessRow` 无现成 flag，但暴露只是纯函数。**一个工程 PR**（小模型暴露 + 列表行 + 单测）即可，天级，不是周级。不要先开采样 PR。本文只锁设计，不估日历人天。

实现等本设计合并、用户 / 主控确认、**Grok merge gate** 通过后再动 Swift、采样实现、entitlements 与脚本。
