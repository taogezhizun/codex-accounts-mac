# Codex Accounts for macOS

一个用 SwiftUI 编写的原生 Mac 菜单栏工具，用于保存自己的多个 ChatGPT 登录账号，并通过正常退出、切换认证、重新打开的方式切换 Codex 桌面 App 账号。

**当前状态：0.3.0 开发预览，待签名发布。** 已通过核心自动化测试、真实 Codex 程序的无登录隔离协议测试与演示界面检查。真实账号之间的浏览器登录、额度读取、桌面切换与恢复仍需要用户本机验收。不能将“认证文件已替换”当作“桌面 App 已登录成功”。

![原创图标及尺寸预览](docs/images/icon-preview.png)

开发与维护：[taogezhizun](https://github.com/taogezhizun) · [项目主页与反馈](https://github.com/taogezhizun/codex-accounts-mac)

## 功能

- 原生双栏窗口与可搜索的菜单栏快速切换面板，支持备注、深浅色和默认隐藏邮箱。
- 从当前认证、选定 JSON 或 OpenAI 浏览器／设备码登录添加账号。
- 凭据与恢复备份保存在本机 Keychain；账号元数据保存在 Application Support。
- 启动时及每 5 分钟自动刷新额度，可暂停或手动刷新；失败保留缓存并退避重试。
- 切换前备份，正常退出桌面 App，原子替换认证后重开；支持恢复与人工核对状态。

## 支持范围

macOS 14+、Swift 5.9+ / Xcode 15+。优先在 Apple Silicon 上验证；Intel 可构建，但尚未进行实机验收。

需要安装官方 Codex 桌面 App。工具通过应用标识 `com.openai.codex` 发现 App，支持应用文件名称变化；使用 App 内置的 Codex 可执行程序，不随包再分发 OpenAI 程序。

第一版支持 ChatGPT 登录凭据，以及 `CODEX_HOME/auth.json` 文件认证（默认目录 `~/.codex`）。**暂不支持** API Key、`keyring` / `auto` / `ephemeral` 认证、共享 app-server 守护进程或受管理的认证策略。检测到这些不兼容情况时会停止切换。设置中的认证目录必须与桌面 App 实际使用的一致。

本工具不会自动判断所有正在运行的任务。点击切换后，需要先确认任务已暂停；如果 App 拒绝退出或其已识别的 Codex 子进程仍在运行，则停止切换，不强制结束桌面进程。其他客户端共用同一认证目录时也可能受到影响。

## 构建与启动

在仓库根目录运行：

```sh
./scripts/build-app.sh
open "dist/Codex Accounts.app"
```

将生成的 `.app` 拖入“应用程序”即可自用。脚本使用本地 ad-hoc 签名，无需付费 Apple Developer 账号。它不是 Developer ID 签名或 Apple 公证；其他机器下载未公证产物时可能出现 Gatekeeper 提示。优先从源码在本机构建。

首次保存凭据时，系统可能要求允许钥匙串访问。自行重新构建后，因签名身份变化，可能再次询问。不要关闭系统安全保护。

## 应用内更新

0.3.0 起，点击菜单栏应用菜单或“设置 → 应用更新 → 检查更新…”。发现新版后确认安装，Sparkle 会替换正在使用的工具并重新打开。只重开本工具，账号、备注、钥匙串和 Codex 桌面 App 保持原位。

**0.2.x 需要最后手动升级一次**：退出旧工具，把新版本拖到“应用程序”，替换同名 App，之后从同一位置启动。不要从下载压缩包或只读磁盘映像里长期运行。更新采用 HTTPS、Ed25519 签名和提取前校验，签名私钥不在仓库中；它不等于 Apple 公证，macOS 钥匙串仍可能在升级后重新请求访问。

## 首次使用

1. 在设置中确认桌面 App 和认证目录。
2. 点击“保存当前账号”，保留目前的登录。
3. 点击“浏览器添加账号”，在 OpenAI 官方页面登录另一个自己的账号；添加不会切换当前桌面账号。
4. 暂停桌面中的任务后，选择新账号并点击“切换至此账号…”，核对来源与目标后确认“切换并重开”。
5. 在重新打开的桌面 App 中核对账号，再点击工具中的“已核对，账号正确”；失败时使用“恢复上次认证”。

自动刷新默认开启：启动后刷新已保存账号，正常间隔 5 分钟，唤醒后补刷到期账号；同一时间只刷新一个账号。失败按 10、20、40、60 分钟退避，恢复成功后回到 5 分钟。登录、切换、待核对和应用更新期间暂停自动刷新。设置中可以关闭，⌘R 仍可立即刷新。

额度查询使用隔离辅助进程和 externally managed token 模式，不在第二个进程中刷新保存的 refresh token。当前桌面认证与已保存身份一致时，额度查询可使用桌面最新 access token；其他账号的 access token 过期后仍需重新登录或重新保存。工具不会发送预热消息、消费额度重置券或进行自动轮换。

## 日常操作

菜单栏点击目标账号即可就地确认切换；当前认证置顶，点击它可打开桌面 App。账号列表支持滚动和搜索，不限于前五个账号。额度旁的时钟表示缓存需要刷新。摘要取 Codex 各周期中最低的剩余比例；没有 Codex 数据时显示未读取，不借用其他额度组。

额度详情优先显示接口的易读名称，Codex 排在前面。未知组默认折叠到“其他额度”，原始编号可点击 ⓘ 查看。不同组不能合并或视为可互相替代。旧缓存可直接使用；刷新后可获得接口提供的新名称。

| 快捷键 | 操作 |
| --- | --- |
| ⌘N | 浏览器添加账号 |
| ⌘R | 刷新选中账号额度 |
| ⌘↩ | 查看选中账号的切换确认 |
| ⇧⌘P | 隐藏或显示邮箱 |
| ⌘E | 编辑选中账号的备注 |

隐藏邮箱不等于可安全公开截图：备注仍然可见。公开素材始终使用演示模式。

## 开发与验证

```sh
swift test
python3 scripts/privacy-check.py
```

可选的真实 CLI 无登录隔离测试：

```sh
CODEX_ACCOUNTS_TEST_CLI="$(command -v codex)" swift test --filter RPCSmokeTests
```

该测试使用空的临时认证目录，只执行握手、`account/read` 与 `config/read`，不使用真实账号。

截图和 UI 检查使用演示模式：

```sh
open "dist/Codex Accounts.app" --args --demo
```

可在 `--demo` 后增加 `--demo-dark`、`--demo-empty` 或 `--demo-pending`、`--demo-quotas` 检查对应状态。请先退出已经运行的工具，再启动演示模式。演示模式不初始化账号库、Keychain 或 RPC；所有邮箱都是 `example.com` 示例，所有账号操作禁用。**不要用真实账号窗口截图提交到仓库。**

详见 [安全与数据说明](SECURITY.md)、[验收清单](docs/VALIDATION.md)、[设计说明](docs/DESIGN.md) 和 [UI 设计与参考](docs/UI-DESIGN.md)。

## 致谢与许可

本项目的多账号管理理念受到 [cjg1995/codex-account-switcher](https://github.com/cjg1995/codex-account-switcher) 启发。感谢原作者。本项目面向 macOS 独立开发，与 OpenAI 及原项目作者无隶属或背书关系。

该项目的公开实现曾用于评估可移植性；本仓库根据功能需求与官方协议重新实现，没有复制或逐行翻译其源代码，也没有使用其图标、截图或文档。上游在 2026-09-10 核查时未声明许可证，因此这里的 MIT 许可仅覆盖本仓库的原创内容，不授予上游代码的使用权。

本项目采用 [MIT License](LICENSE)。接口依据：[OpenAI Authentication](https://learn.chatgpt.com/docs/auth)、[Codex App Server](https://learn.chatgpt.com/docs/app-server)；UI 使用 Apple SwiftUI / AppKit；应用更新使用 [Sparkle 2.9.6](https://sparkle-project.org)，保留其[完整许可证](docs/licenses/Sparkle.txt)。自动刷新节奏与缓存反馈参考 [OpenUsage](https://github.com/robinebers/openusage/blob/main/docs/refreshing.md)，未复制其实现或素材。

维护者签名和发布步骤见 [更新与发布](docs/UPDATES.md)。
