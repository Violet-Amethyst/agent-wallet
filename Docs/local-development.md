# Agent Wallet 本地开发与 GitHub 同步

更新日期：2026-10-25。

## 项目位置

Mac 开发目录：`~/Developer/NativeApps/Agent-Wallet`。

此目录包含 `Package.swift`、`Sources/`、`Tests/`、`Docs/` 和完整 Git 历史。
2026-10-25 从 `~/Developer/Personal/agent-wallet/AgentWallet` 迁入。
`NativeApps` 用来归类原生应用源码；可运行的 `.app` 与源码目录是不同的用途。
历史研究记录中的旧目录表示当时的位置。

## 远端与分支

- `origin`：https://github.com/Violet-Amethyst/agent-wallet.git ，自己的产品仓库，日常提交发到这里。
- `upstream`：https://github.com/qunqin24/Pulse.git ，上游参考。合入前遵守 [产品身份约定](agent-wallet-identity.md)。
- GitHub 默认分支为 `agent-wallet`。本机 `main` 跟踪 `origin/main`，当前开发成果从 `main` 提交 PR 到 `agent-wallet`。

目录移动不改变 Git 的远端连接。以后在新目录打开项目即可继续提交。
此次同步上传现有开发提交和文档，通过 PR 展示与默认分支的差异；PR 合并另行决定。

## 日常提交

```sh
cd ~/Developer/NativeApps/Agent-Wallet
git status --short --branch
git fetch origin
# 先核对上游差异；有未提交修改时不切分支、不自动 stash。
git diff
# 按改动运行验证，见下方与 testing.md。
git add <本次改动的文件>
git commit -m "说明这次修改"
git push origin main
```

若 `main` 到 `agent-wallet` 已有打开的 PR，后续 push 会更新该 PR；若已经合并或关闭，先重新比较分支，再为新改动建立 PR。若远端领先导致 push 被拒绝，先处理分支差异，不强制推送。

仅放置文件不会自动提交；每次按修改范围检查、验证、提交并推送。凭据、本机设置、`.build/`、`build.noindex/` 不应进入提交。

## 验证

Swift 修改须通过无警告构建和相关测试；界面文字修改还需本地化检查：

```sh
swift build -Xswiftc -warnings-as-errors
swift test
./Scripts/check-localization.sh
```

首次迁移后若 Swift 缓存引用旧的绝对路径，可以给 `swift build` / `swift test` 指定新的 `--scratch-path` 重建缓存。构建要求见 [build-from-source.md](build-from-source.md)，测试范围见 [testing.md](testing.md)。
