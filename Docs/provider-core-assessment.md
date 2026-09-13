# Agent Wallet 数据层判断（2026-09-12，本机代码）

## 结论

保留 `CodexBar/` 和 `Pulse/`，当前唯一交付工程是 `AgentWallet/`。
Pulse 提供悬浮栏与设置界面；数据层逐步通过适配器复用 CodexBarCore。
本次修复不等于已经完成核心迁移，也不需要另外运行 CodexBar 桌面应用。

## 已确认的故障与修复

- 图标：`LobeIconStore` 只查找 `.svg`。之前增加/裁剪的 `qoder.png`
  根本没有被加载，旧 `qoder.svg` 仍是圆形占位图。现在替换实际 SVG，
  路径取自官网引用的官方 wordmark，只保留符号和透明背景。
- 路径：运行进程位于 `AgentWallet/build.noindex/Agent Wallet.app/Contents/MacOS/Pulse`。
  `Pulse` 是此工程的可执行文件名，并不表示正在运行旁边的 `Pulse/` 源码。
- 密码：原 Qoder fetch 每次访问 Safe Storage；进程内缓存退出即丢失。
  bundle.sh 使用 ad-hoc 签名，designated requirement 绑定二进制哈希，
  重新构建后历史钥匙串授权可能不再适用。本机没有有效 codesigning identity。
- 本次修复：Qoder 的启动、刷新只进行禁止交互的钥匙串查询；只有设置中的
  “连接 Qoder CN”允许交互。导入的是当前账号 token，不持久保存 Safe Storage
  总密钥。token 使用已有 LocalSecrets 文件存储，绑定源登录文件指纹，
  有效复用上限七天，401/403 删除副本；源文件缺失/变更不复用旧账号。
  加密边界和局限见 `providers/qoder-cn.md`。

## CodexBar 能复用什么

| 能力 | 本地依据 | 建议 |
| --- | --- | --- |
| 无交互钥匙串与授权协调 | `CodexBarCore/KeychainNoUIQuery.swift`、`KeychainAccessGate.swift` | 第一优先，后台读取与主动授权分离；本次 Qoder 已采用同类双重 UI 禁止策略 |
| 服务注册、来源选择、失败回退 | `CodexBarCore/Providers/ProviderDescriptor.swift`、`ProviderFetchPlan.swift` | 作为统一数据接口的基础，逐步替换 UsageStore 中越来越长的分支 |
| 额度和消费解析 | `Providers/Codex/`、`DeepSeek/`、`OpenAI/` | 分别验证后接入；Codex 订阅额度与 OpenAI API 费用不能混为一个余额 |
| 浏览器登录导入 | SweetCookieKit、各服务 CookieImporter | 按账号/站点限定来源，明确权限状态与失效恢复 |
| Qoder CN | `Providers/Qoder/QoderUsageFetcher.swift` | 已支持中国网站，但与当前桌面端的接口/返回结构不同，不能直接替换已验证路线 |
| ComfyUI | 本地 Providers 未发现实现 | 仍需单独验证 Comfy 账号积分接口，换成 CodexBarCore 不会自动补齐 |

本地 CodexBar 的 `ProviderIcon-qoder.svg` 也还是旧圆形图标。因此图标错误
和未完成的 ComfyUI 接入不能归因于“没用 CodexBar 核心”。

## 整合边界与顺序

1. 保留一个可运行产品和一套账号、设置、缓存。不要同时启动两个抓取后台，
   也不要默认让 CLI 子进程为每次刷新重新导入全部凭据。
2. 定义 Agent Wallet 的统一数据接口，包含来源、读取时间、账号身份、
   余额/额度类型、过期状态、恢复动作。将 CodexBar `UsageSnapshot` 适配为
   现有 `ProviderUsage`，由 `WalletSnapshot` 驱动界面。
3. 固定 CodexBar 版本，优先迁移 Codex / DeepSeek，再验证 Qoder 中国网站路线。
   每个服务至少验证首次授权、重复刷新、退出重开、登录失效和切换账号。
4. ComfyUI 单独实现；Stripe 充值账单的金额不能替代剩余积分。
5. 再收敛旧抓取代码。现有本机可工作的读取路线保留到替代路线验证通过。

CodexBarCore 虽然已导出 library，但还依赖 QuickJS、Crypto、Logging、
SweetCookieKit，并带自己的 FetchContext 和 SettingsSnapshot。
因此“添加 package 依赖”不是完整整合。应先做一个服务的适配并验证，
不把整套菜单栏 UI、自动更新、快捷键和配置系统一起塞进来。

## 交付身份仍需后续统一

当前沿用 Pulse 的 bundle ID、数据目录和上游 Sparkle 更新源。
本次没有直接更名这些标识，以免用户设置与登录启动项丢失；正式发布前
需要带迁移逻辑的独立身份与更新渠道，并采用稳定签名。
稳定签名能减少每次构建后的重复信任确认，但不应代替后台禁止弹窗的策略。

## 本次验收

- 两项无真实钥匙串访问的回归测试通过：新 Session 实例跨重启复用、
  磁盘密文与 0600 权限、七天过期、换账号、注销和服务端拒绝后的失效。
- 双架构 Release 构建成功，本地化 403 个键通过校验。
- 包内实际 SVG 与源码 SHA-256 一致；打开真实设置窗口，标题与侧栏均
  显示 Qoder 官方线框图形。
- 完整退出后确认旧进程不存在，再从指定 .app 路径启动。Qoder 在
  22:34:02 收到新的用量接口读数，剩余 0 cr；过程中没有输入密码。
