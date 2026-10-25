# Agent Wallet 产品身份与上游跟进

日期：2026-10-22。基线是本地 `main` `3221bfb`。Pulse **1.12.2** 在 `085dff7`。1.12.3 的计价和进程修复已 cherry-pick：`bfd74ce`（上游 `547b57c`）、`3221bfb`（上游 `a53a5ca`）。`VERSION` 仍是 **1.12.2**。未接 `acd02a3`（版本号与更新说明）和 `8410d08`（三份 appcast）。上游 `main` 当时在 `8410d08`。

本文是以后跟 Pulse、对照 CodexBar 时的现行约定。行为以代码为准；本文和代码冲突时，先改本文。`Docs/ROADMAP_AND_LEARNING_PATH.md`、`Docs/research/`、`Docs/reference/ARCHIVE_REPORT.md` 是当时的记录，数字、默认值和文件名以本文为准。

## 这个产品是什么

Agent Wallet 是长在 Pulse 源码上的 macOS 算力钱包。刷新、缓存、通知、Token spend、七十六个服务商里的大部分读取通道，仍然是 Pulse。我们自己决定的是：一个读数在坞上算配额还是余额、圆环按剩余还是按最紧的限额来画、配额和余额怎么并排，以及几条 Pulse 当时没有的账户读取。

可执行文件、菜单和设置域仍沿用 Pulse 的名字。坞底的退出按钮写的是 “Quit Agent Wallet”。若和官方 Pulse 使用同一个 bundle id，两边会共享同一套设置。换标还没有做。

## 和 Pulse、CodexBar 的关系

| | Pulse | CodexBar | Agent Wallet |
|---|---|---|---|
| 仓库 | `upstream` → `https://github.com/qunqin24/Pulse.git` | 不接入 remote，只作阅读 | `origin` → `https://github.com/Violet-Amethyst/agent-wallet.git` |
| 许可 | Apache-2.0，我们保留 | MIT。需要它的接口时，在 Pulse 形状里重写，并在注释里写明出处 | 同一份 Apache-2.0 |
| 在产品里的位置 | 上游。历史从它来，读取和修复默认跟它 | 参考。`Docs/reference/codexbar/` 与 `Docs/research/` 是笔记，不是依赖 | 唯一要改、要构建的树：`AgentWallet/` |
| 界面 | 屏幕边缘单列圆环坞 | 菜单栏高密度列表，另有 Widget 和 Linux 桌面 | Pulse 的边缘坞，加上配额/余额分列和底部动作键 |

CodexBar 不进 `Package.swift`，也不作为子模块编译。工作区里若还留着只读的 `Pulse/` 或 `CodexBar/` 副本，不在那些目录里改产品。

## 合并时必须保住的行为

这些是产品身份。上游的同名文件可以接它的修复，但不能把下面的语义盖回 Pulse 的单列、已用优先。

### 1. 剩余优先的钱包读数

`Sources/Pulse/Wallet/WalletSnapshot.swift` 把 Pulse 的 `ProviderUsage` 变成坞上的一种读法。Pulse 把最紧的限额放在粗外环，文案常是已用。我们把短周期放在较粗的内环，长周期放在较细的外环，坞上的短标题是剩余。

几何常量在 `DockLayout`：`outerRingLineWidth` 2pt（长周期），`innerRingLineWidth` 2.8pt，`innerRingDiameter` 26pt。弧的颜色仍按用掉的比例变紧急；画出来的弧长是剩余。

`WalletAdapter.snapshot` 里这几条是我们的映射，合上游时逐条看：

| 账户 | 坞上的读法 |
|---|---|
| 同时有短窗口和长窗口 | `dualQuota`：内环短（约 5 小时或不超过 12 小时的 `.other`），外环长（周、月，或更长的 `.other`）。标题只印短窗口的剩余。 |
| Codex，且已有配额窗口 | 只留一个环，用 `headlineWindow`。周限额和 5 小时不再拆成双环。 |
| Cursor 同时有 `cursorModels` 与 `otherModels` | 内环 Cursor Models，外环 Other Models。钉住某一侧时内外对调。 |
| Antigravity 同时报 Gemini 与 Claude and GPT，且账号未拆成两枚环 | 内环 Gemini，外环 Claude and GPT。优先用已耗尽的窗口，否则用周限额。 |
| Qoder | 余额轨。标题是个人额度加共享额度的整数积分（`qoder.credits` + `qoder.shared`）。 |
| OpenAI、xAI，且花费窗口的估计是用户自己的预算 | `money(.periodSpend)`，标题印剩余预算。 |
| 只有预付余额 | `money(.prepaid)`。满环按 100 个货币单位画，例如 ¥90.07 画成约 90% 的剩余弧。 |
| 只有一条配额 | `singleQuota`，标题是剩余百分比或 `300 cr` 这种积分。 |

DEBUG 夹具在 `WalletFixtures.swift`，只在调试构建里出现，不写入 `UsageCache`。

### 2. 单列与双列坞

设置项 `settings.usesDualTrackDock`，默认 **开**（双列）。外观和位置两页都有 “Rail columns”。

双列只在开关打开、而且配额账户和余额账户都至少有一个时生效（`DockLayout.isDualTrack`）。配额在一侧，余额在另一侧，余额沿坞的长边错开半个步长。侧边坞厚 120pt（`dualTrackWidth`），步距 56pt（`dualTrackItemSpacing`）。单列把配额排在前面、余额排在后面，两组之间有一条分隔（`singleColumnGroupDividerPosition`）。

窗口长度无论单列双列都要加上底部动作区 `actionAreaLength`。2026-10 合入 Pulse 1.9.0 时，上游的单列 `length` 盖掉了这段高度，设置和退出被裁出窗口，第二列的点击也被算到第一列。事后记在 `Docs/reference/ARCHIVE_REPORT.md`。

### 3. 底部动作键

坞末端有两枚直径 40pt 的键：设置、退出。点击不走 SwiftUI 的 `.onHover`。`FloatingPanelController` 的 `panel.onClick` 用 `DockLayout.actionPositions` 做圆域判断：第一枚打开设置，第二枚 `terminate`。槽位命中必须带上 `isMoney`，否则余额列的坐标会偏到配额列。

`AppDelegate.startMonitoring()` 把这两个闭包传进面板。菜单里的退出文案仍是 Pulse 的 “Quit Pulse”；坞上那一枚是 “Quit Agent Wallet”。

### 4. 我们加的账户读取

这些文件是在 Pulse 的 `Provider` / `ProviderUsage` 上新写的，不是从 CodexBar 拷进来的模块。

| 读取 | 文件 | 和上游已有能力的差别 |
|---|---|---|
| OpenAI API 账单 | `Providers/OpenAIUsageService.swift` | 用 Admin Key 读 `GET /v1/organization/costs`。Codex 仍是 ChatGPT / Codex 的限额窗口，两者不要并成一个服务商。 |
| xAI 开发者平台 | `Providers/XAIUsageService.swift`、`Auth/XAIWebLogin.swift` | Management API 的预付余额和用量，或 console 的 `sso` cookie。和 Grok CLI、Grok Bot 是三个产品。 |
| DeepSeek 网页登录 | `Auth/DeepSeekWebLogin.swift` | 从 Chrome 的 `platform.deepseek.com` local storage 读 `userToken`。Pulse 原有的 DeepSeek 余额分母设置还在。 |
| Qoder CN 桌面会话 | `Auth/QoderCNSession.swift`，说明在 `Docs/providers/qoder-cn.md` | 从 `com.qodercn.app.stable` 的 `auth.v1.dat` 取 token，加密后存 `qoder-cn-session.dat`，最多七天，不保存 Safe Storage 主密钥。Pulse 已有的 `qoder.com` / `qoder.com.cn` 网页 cookie（`QoderUsageService`）是另一条路，合上游时两条都留。 |
| Codex 展示过滤 | `Usage/CodexDisplay.swift` | 可从坞上拿掉 Spark / bengalfox 窗口，并固定周限额的排序。 |

`UsageProvider` 里因此多了 `.openAI` 和 `.xai`，两者的 `billing` 是 `.api`。

### 5. 合完必须还在的测试

`swift test --filter 'RailGeometryTests|WalletSnapshotTests|WalletConnectionTests|QoderParsingTests|XAIUsageTests|OpenAIUsageServiceTests|CodexHeadlineTests'`

其中 `RailGeometryTests` 的 `DualTrackOlympicRailGeometryTests` 固定：双列左右错开、单列先配额后余额、两枚动作键落在坞的物理边界内。这组断言就是为了挡住下一次上游覆盖。

## 跟 Pulse 时直接接的部分

服务商解析、cookie、额度窗口字段、Token spend 的计价和缓存版本、通知规则、上游自己的本地化键、液态玻璃、Bot mark、多显示器跟随、自适应刷新。这些改动落在我们没有改写语义的文件上时，按上游合入。

2026-10-22 的 1.12.3 属于这一类，并且已经接上：`ModelPrices` 把 Antigravity 的 `gemini-3.8-flash-n`、`-control`、`-xpe` 按 `gemini-3.8-flash` 计价，`AgentCache` 从 11 升到 12，`BoundedProcess` 在输出上限处截断当前这块数据。同一天留下了版本号、更新说明和 appcast。

`VERSION` 和三份 `appcast*.xml` 是 Pulse 的发版公告。应用里的更新源仍是 `https://raw.githubusercontent.com/qunqin24/Pulse/main/`（`AppUpdate.FeedHost`）。把公告原样接进来，等于让这份钱包去下载 Pulse 的安装包。代码修复可以进；版本号和 appcast 按我们自己的发布再写。

## 对照 CodexBar 时怎么跟

CodexBar 更新了，先看它是否改到我们正在用的合同：Qoder 的额度接口、OpenAI organization costs、xAI Management API、DeepSeek 的网页 token。改到了，就读 `Docs/reference/codexbar/` 和对应的 service，在现有 Swift 文件里补差异。

这些不搬进产品：菜单栏磁贴、WidgetKit、Linux Qt 桌面、整份提供商目录、把 CodexBar 当成运行时或 Swift 包。成本曲线和小组件若以后要做，按 Pulse 的账本和坞来做，不合并它的界面。

## 一次上游合并的顺序

1. `git fetch upstream` 之后，用本文把 diff 分成「必须保住」和「直接接」。
2. 先看这些路径有没有被上游改到：`Sources/Pulse/Wallet/`、`Panel/UsageDockView.swift`、`Panel/UsageRingView.swift`、`Panel/UsageDetailCard.swift`、`Panel/FloatingPanelController.swift`、`Panel/FloatingUsagePanelContent.swift`、`Panel/FloatingUsagePanelView.swift`、`App/AppSettings.swift` 与 `AppSettings+Panel.swift` 里的 `usesDualTrackDock`、`Settings/AppearancePane.swift`、`Settings/PlacementPane.swift`，以及上一节列出的自有读取。
3. 冲突时留下：钱包映射、双列几何、`actionAreaLength`、`actionPositions`、命中测试里的 `isMoney`、`.openAI` / `.xai` / Qoder CN。上游对玻璃、刷新、多显示器、计价的修改留在旁边，不要为了消冲突整文件选用上游。
4. 跑上面的测试过滤。几何测试失败就还没合完。
5. 文档：改到了身份，就改本文。上游主题文档（`Docs/providers/`、`token-spend.md` 等）可以跟着上游走。`Docs/README.md` 里曾经列过、树里已经没有的 `wallet-ui-v0.md`、`wallet-ui-gap-analysis.md`、`wallet-provider-audit.md`、`api-capability-investigation.md`，不要当作现行规格找回来；现行规格是本文。`window-starter.md` 和 `update-mirror.md` 相对上游缺失，但窗口启动器和更新代码还在，缺的是文档，不是产品决定。
