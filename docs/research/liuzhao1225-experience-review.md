# liuzhao1225/codex-account-switcher：体验与设计借鉴调研

核对日期：2026-09-11。核对对象为当时 main 的固定提交 `5f2a0352d33a26b479bbe614b9b80843f4c9cb16`。本节来自公开源码静态阅读，没有安装或运行上游 App，没有测试真实账号切换，也没有访问本机账号或钥匙串。以下“实现”仅代表该提交的控制流；README 的产品承诺不视为运行验收证据。

## 建议先看：适合我们的五项改进

对照基线：我们的 main `020054ccfbc06582431200652a99287da0251751`（App 0.3.2）。以下优先级是本次调研的产品判断，不是上游要求；尚未实现或发布。另实际浏览了[上游中文官网](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/)，观察的是官网展示的演示图与网页，未运行原生应用。

| 优先级 | 对方的做法与证据 | 我们当前的情况 | 建议采用的具体设计 |
| --- | --- | --- | --- |
| P0：账号列表扫读 | 头像、名称、重置时间、细额度条和百分比；当前行持续浅色高亮。[AccountRow](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/AccountRow.swift#L12-L55) | 菜单有头像、账号名和额度文字；当前账号有文字标记，但行底色只随悬停变化。[MenuPanel](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/Sources/CodexAccounts/MenuPanel.swift) | 菜单内增加细额度条、当前行浅底色，保留“当前”文字；明确 5 小时/7 天周期。非当前账号写“上次记录”及时间，避免缓存看起来实时。不要仅靠颜色区分当前账号。 |
| P0：可见的更新入口 | 发现新版本后，账号列表底部显示蓝点、版本号和更新按钮。[菜单更新行](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/MenuBarPopover.swift#L108-L125) | 已有 Sparkle 检查和原位更新，但菜单没有持久的新版本状态条。[AppUpdates](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/Sources/CodexAccounts/AppUpdates.swift)、[菜单](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/Sources/CodexAccounts/MenuPanel.swift) | 增加“新版本可用 · 查看更新”，沿用签名验证和用户确认安装；不用让用户为了找更新进入完整设置，也不要把提示变成强制安装。 |
| P1：常用设置更短 | 同一面板切换账号、管理、设置；设置分通用与更新，44 pt 最小行高、右侧控件对齐，包含菜单栏百分比和登录时启动。[页面路由](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/MenuBarPopover.swift#L10-L51)、[设置](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/SettingsView.swift#L18-L96) | 我们设置是一个长 Form，常用选项、认证目录和关于混排；菜单栏目前只有图标。[设置](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/Sources/CodexAccounts/Dialogs.swift#L90-L130)、[菜单栏标签](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/Sources/CodexAccounts/CodexAccountsApp.swift#L21-L26) | 做一个菜单内快捷设置入口，放自动刷新、显示剩余额度、启动选项；路径与兼容性放高级设置，作者和致谢放关于。保留完整管理窗口。菜单栏数字须注明使用哪个周期，失效时显示缓存状态。 |
| P1：首次使用与等待反馈 | 空库自动导入当前身份，浏览器登录后自动命名；添加位置直接变为取消按钮。[添加流程](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountController.swift#L53-L82)、[管理面板](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/ManageAccountsView.swift#L71-L89) | 我们已提供保存当前账号、浏览器添加、取消以及状态文字。[AppModel](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/Sources/CodexAccounts/AppModel.swift) | 首屏根据是否发现当前登录显示一个推荐入口：“保存当前账号”或“浏览器添加账号”。发现身份可以自动做，保存到钥匙串仍由用户点击；等待文案贴近添加入口，明确“请在浏览器完成登录”，可取消后重试。不用邮箱前缀自动生成公开可见备注。 |
| P2：介绍页与国际化 | 官网首屏为产品截图、短标题和清楚的下载按钮；中英文界面及系统语言选项。[官网](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/)、[语言设置](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/SettingsView.swift#L52-L64) | 已有真实组件的虚构账号截图、DMG 直链与中文 README；界面主要是中文。[README](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/README.md) | 先保留“下载 → 三步开始 → 常见问题”的短结构，统一截图与版本；有外部用户需求后再补英文和独立官网。继续使用我们的原创图标与视觉识别，不搬对方素材。 |

**第一批建议仅做两项 P0。** 可验收的结果：打开菜单就能区分当前账号与旧额度；有新版时能直接进入现有更新流程。当前账号刷新、钥匙串保存和恢复保护逻辑不需要为这两项改动而重写。

## 视觉与信息组织观察

官网演示图采用浅灰背景、低饱和蓝紫强调色、单色首字母头像、细进度条和稳定的对齐关系，信息密度适合菜单栏。源码对应 326 pt 固定面板、3 pt 额度条、当前行 10% 强调色背景。[面板](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/MenuBarPopover.swift#L51)、[条与底色](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/AccountRow.swift#L153-L186)。值得借鉴的是清楚的层级和一致的对齐，而不应机械地把我们 368 pt 的面板压到 326 pt。

其底部“管理账号 / 设置 / 退出”均有文字，减少纯图标猜测；管理和设置原地进入并能返回。[底部操作](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/MenuBarPopover.swift#L128-L163)。我们可把低频恢复入口收入更多操作，给常用操作留空间，同时保留搜索、滚动和大窗口。上游默认账号列表采用 VStack 而非 ScrollView，不作为多账号扩展性的参考。

上游只用背景高亮标当前账号、默认仅显示周额度，是它自己的取舍。[产品决策](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/docs/product-decisions.md)。我们不建议去掉文字标识，也不建议默认隐藏一个可能已经耗尽的 5 小时窗口。可保留完整额度详情，菜单只呈现一个明确标注周期的摘要，遇到另一周期接近耗尽时增加轻量提醒；不要合并不同额度池。

## 已有能力与不建议照搬的部分

我们已有菜单内切换确认、登录取消、额度失败保留缓存、自动刷新退避、DMG 和应用内更新。它们属于体验精修，不是能力空白。[我们的菜单](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/Sources/CodexAccounts/MenuPanel.swift)、[模型](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/Sources/CodexAccounts/AppModel.swift)、[更新](https://github.com/taogezhizun/codex-accounts-mac/blob/020054ccfbc06582431200652a99287da0251751/Sources/CodexAccounts/AppUpdates.swift)。

保留我们的当前账号刷新范围、钥匙串存储、恢复日志、缓存时间和人工核对 Desktop 账号。上游全账号并发刷新、文件凭据存储以及没有持久化恢复日志，是不同的产品边界，并非应照搬的优化。浏览器添加后自动派生邮箱前缀名称会影响我们默认隐藏身份的体验。Windows 支持和 Apple 公证也不是本轮建议；前者超出当前自用 Mac 范围，后者按上游文档声明存在，本次未验证发布包的公证票据。

## 源码证据与边界

## 结论

可借鉴的重点是：添加账号后自动命名、紧凑的确认流程、缓存额度在刷新失败时继续展示、按故障阶段给出可操作反馈。**上游的“身份验证”验证的是独立 Codex helper 读取的当前认证目录，不是重新打开后 Desktop 界面的账号。** 其不弹钥匙串授权的主要实现原因是凭据存为受文件权限保护的 `auth.json`，这与我们保存账号及恢复备份到钥匙串的方案不同，不能直接等同为更好的安全与使用体验。

## 1. 添加账号：浏览器完成后直接归档，不让用户手工起名或粘贴 token

- 首次启动时，若账号列表为空但当前认证文件存在，会读取当前身份，自动导入并设为 active；这降低首屏空白状态的操作量。证据：[启动导入流程](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountController.swift#L53-L82)。
- “添加账号”创建新的 UUID profile 目录，将其作为 helper 的 `CODEX_HOME`，调用 `account/login/start`、打开返回的浏览器 URL，等待最长 600 秒的登录完成通知，再调用 `account/read` 获取身份。添加操作不会主动写入当前 active home。证据：[新 profile 与取消处理](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountController.swift#L206-L248)、[浏览器登录协议](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/CodexClient.swift#L504-L552)。
- 默认名称来自邮箱 @ 前半部分；账号 ID 相同（或 ID 无法比较时邮箱相同）判重，失败或取消会清理未登记 profile。体验含义：减少一个命名步骤，但邮箱推导名不是隐私友好展示方案，不能原样替代我们隐藏邮箱的偏好。证据：[默认名称与身份匹配](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/Models.swift#L139-L160)、[判重和清理](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountStore.swift#L158-L176)。
- 添加期间操作行变为“取消添加账号”与小进度指示，取消会停止 helper；能清楚表达“等待你在浏览器操作”，比只显示无限 spinner 更可控。证据：[取消入口](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/ManageAccountsView.swift#L71-L89)、[取消登录会话](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/CodexClient.swift#L545-L552)。

## 2. 切换：值得借鉴阶段反馈，不能照搬“Desktop 已验证”的表述

实现顺序为：验证 profile/registry 前置条件 → 请求 Desktop 正常退出并等待 → 读取当前 active home 身份并保存离开账号凭据 → 原子写入目标凭据 → helper 验证目标身份 → 提交 activeAccountID → 重新打开 Desktop。证据：[完整切换流程](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/SwitchService.swift#L27-L109)。

关键证据边界：

- `readIdentity` 新开 `codex app-server --stdio`，用指定的 `CODEX_HOME` 执行 `account/read`，参数 `refreshToken: false`。匹配优先使用 accountID，缺少可比 ID 时退回大小写不敏感邮箱比较。它证明 helper 从该目录得到的身份与保存的目标一致；不证明网络 token 仍可用，也不证明重启后 Desktop 已采用这一身份。证据：[helper 运行环境](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/CodexClient.swift#L211-L220)、[身份读取 RPC](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/CodexClient.swift#L481-L490)、[匹配规则](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/Models.swift#L152-L159)。
- 目标验证发生在 `reopenDesktop` 之前；打开 Desktop 仅等待 `NSWorkspace.openApplication` 返回，没有后续 Desktop 内账号读取或 UI 检查。**不能据此删除我们“请核对 Desktop 账号”的最终确认，或宣称自动验证 Desktop 登录成功。** 证据：[验证、登记、重开的时序](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/SwitchService.swift#L81-L107)、[重新打开实现](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/DesktopController.swift#L65-L75)。
- 退出最多等 30 秒，失败即停止，错误告诉用户先完成或停止任务及处理退出对话框；不会升级成强制杀进程。确认页在操作前就说明这些后果，适合借鉴其“行动前告知 + 失败后下一步”。证据：[退出超时和错误提示](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/DesktopController.swift#L5-L62)、[中文切换确认文案](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/Localization.swift#L92-L99)。
- 目标身份验证或 registry 提交失败时，会尝试恢复刚保存的原凭据；恢复再失败，会把两个错误一起保留。但重开 Desktop 失败不回滚，界面改为“账号已切换，请手动打开”；这准确区分写入状态与启动状态，但其“所选账号已经生效”仍只得到 helper 身份证据支撑。证据：[限定范围的恢复](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/SwitchService.swift#L81-L137)、[重开失败专门反馈](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountController.swift#L173-L203)。
- 点击非当前账号先进入一个确认子页，确认后回列表并运行；错误在面板内显示可关闭 banner。可借鉴这种稳定的上下文，不必为常规错误再开系统弹窗。证据：[面板内错误与确认路由](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/MenuBarPopover.swift#L10-L47)、[切换确认页](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/MenuBarPopover.swift#L165-L199)。

## 3. 额度：缓存与失败降级值得借鉴，刷新范围不适合照搬

- 启动加载持久化 `usage-cache.json`，随后后台默认每 300 秒刷新；打开菜单面板也会触发刷新；已有刷新任务时不会重入。证据：[启动缓存与刷新调度](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountController.swift#L74-L125)、[打开面板刷新](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/MenuBarPopover.swift#L51-L58)。
- 刷新会并发遍历所有保存账号的 profile home，分别启动 helper 请求 `account/rateLimits/read`，**并非只刷新当前登录账号**。这与用户已明确选择的“仅刷新当前登录账号”不同；只借鉴显示及缓存策略，不改变刷新范围。证据：[所有账号并发刷新](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountController.swift#L129-L169)、[额度 RPC](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/CodexClient.swift#L493-L501)。
- 单账号刷新失败时：有旧值就保留进度条并标为 stale，旁边橙色小警告支持悬停解释；没有旧值才显示不可用。这是明确可用的体验模式：断网不会让整个列表突然清空。证据：[stale 与 unavailable 分流](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountController.swift#L151-L167)、[旧额度及局部错误呈现](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/AccountRow.swift#L59-L99)。
- 限额只选 `rateLimitsByLimitId["codex"]`（回退 `rateLimits`）的两个窗口；默认只显示周额度，设置开启后才显示精确 300 分钟的短周期。其周窗口识别容许 6–8 天且选择最长窗口；不会把任意短窗口标为 5 小时。可借鉴“先给一个易懂主指标，其他按需展开”，但需继续保留真实周期和多额度池的准确区分。证据：[额度池选择](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/CodexClient.swift#L587-L607)、[周期规范化](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/WeeklyUsageNormalizer.swift#L17-L41)、[默认显示设置](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/Models.swift#L46-L55)。
- 注意：磁盘缓存含 fetchedAt，但启动恢复缓存时直接转成 loaded，没有携带时间到 UsageViewState，也不按缓存年龄标旧。借鉴时应继续显示我们已有的更新时间，避免旧缓存看起来就是当前值。证据：[缓存时间与展示状态](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/Models.swift#L100-L136)、[缓存恢复实现](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountController.swift#L315-L319)。

## 4. 凭据存储：无钥匙串提示来自不同存储边界

- 保存的账号各有一份完整可复用的 `auth.json`，位于应用支持目录的 accounts/profile 下；默认 active home 为环境变量 CODEX_HOME 或用户 .codex。文件原子写入，临时文件模式 0600，目录设 0700。未使用 Keychain 包装凭据。证据：[存储位置](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountStore.swift#L30-L67)、[保存认证文件](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountStore.swift#L144-L170)、[原子写入及权限](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountStore.swift#L330-L383)。
- 这使常规读取无需钥匙串授权，但能够读取用户文件的同用户进程、备份或快照也可能复制凭据。不能把“不弹窗”当作更强的凭据保护。这里的建议仅是维持我们“启动/看额度不读钥匙串、主动账号操作才访问”的职责划分，不建议为了模仿上游而迁移用户凭据。上游 README 也明确把文件权限作为当前安全边界；本结论不包含对其发布二进制的安全审计。

## 5. 开源借鉴边界

固定提交 LICENSE 为 MIT，版权声明 `Copyright (c) 2026 liuzhao1225`；若采用其代码或实质性软件片段，应随分发保留该版权及 MIT 许可全文。仅借鉴交互思路并独立实现时，也可在项目致谢中说明参考的项目与具体思路，避免宣称对方背书。此次调研没有复制实现、图标或宣传图进入产品。证据：[上游 MIT 许可证](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/LICENSE#L1-L21)。

## 后续验证范围

这份调研没有验证上游 v0.1.12 二进制与 main 的一致性、安装签名/公证实际状态、真实多账号刷新行为、网络错误效果或 Desktop 重启后的界面身份。任何采用后的功能仍需我们自己的隔离测试及明确的本机验收；不能把上游 README 或静态控制流当成已完成的运行验证。
