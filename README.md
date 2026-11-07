# TapSulor iOS

TapSulor（TapTap 开发者数据助手）的 **iOS 版源代码**。移植自安卓版 v1.0.5（包名 `com.taptapgain`）。

> ## ⚠️ 重要：这里没有 IPA，不能直接安装
>
> **本仓库只提供源代码工程，不是可安装的安装包，也没有提供任何 IPA 文件。**
>
> - iOS 应用**必须**在 **macOS + Xcode** 环境下编译，再用你自己的 Apple ID / 开发者 Team 签名，才能装到 iPhone 上。
> - **无法在 Windows、Linux 或 Android 手机上直接打包**。Xcode 只有 macOS 版本，这是苹果的硬限制，没有绕过办法。
> - 想装到自己的 iPhone 上：Mac + Xcode + 免费 Apple ID 就够（但证书 7 天过期，需重新连接 Mac 重装）。
> - 想长期使用或分发给别人安装：需要 **付费 Apple Developer 账号（$99/年）**，用 TestFlight 或企业签名分发，否则 IPA 无法直接给别人装。
>
> **不会打包是正常的。** 你可以把整个工程交给 AI 协助：告诉 AI「这是 Xcode 工程，我要在 Mac 上编译成 IPA」，它会一步步带你操作（见下方「用 AI 协助打包」）。

---

## 📱 与其它版本的关系

| 版本 | 仓库 | 说明 |
|---|---|---|
| 📱 Android | [TapSulor-Android](https://github.com/liusu239113/TapSulor-Android) | Kotlin + GeckoView |
| 💻 Windows | [TapSulor-Desktop](https://github.com/liusu239113/TapSulor-Desktop) | Electron |
| 🍎 iOS | **本仓库** | Swift + WKWebView，**仅源码** |

---

## 🧭 思路

安卓版的界面是一套本地网页（`assets/index.html`、`js/main.js` 等），外层是 GeckoView，原生部分通过 `window.AndroidBridge` 提供账号、登录、网络等能力。iOS 版沿用这个结构：

- **网页层原样复用**：`TapSulor/Web/` 来自安卓版的 `assets/`，`index.html`、`js/main.js`、`js/detail.js`、样式、字体、音效均未修改。
- **原生桥用 Swift 重写**：`ios-bridge.js` 在 WKWebView 文档开始时提供与安卓同名、同参数的 `window.AndroidBridge`。安卓版自带的 `android-bridge.js` 照常把它包装成 `window.electronAPI`，页面代码无需改动。
- **原生逻辑对齐桌面版**：安卓版的 Kotlin 源码不在 APK 里，所以账号、登录、会话判断等规则参照桌面版 `app.asar`（v1.0.1 的 `main.js`）和 `assets/account-state.js` 实现。

## 📁 目录

```
TapSulor-iOS/
├── TapSulor.xcodeproj/            Xcode 工程
├── TapSulor/
│   ├── Info.plist
│   ├── Assets.xcassets/           应用图标（1024×1024）
│   ├── Web/                       网页资源（来自安卓版 assets，另加 ios-bridge.js）
│   └── Sources/
│       ├── App/                   入口、场景、AppCoordinator（调度中心）
│       ├── Core/                  纯逻辑：数据模型、账号仓库、TapTap 数据解析、Cookie 请求头
│       ├── Network/               URLSession 网络层、检查更新
│       ├── Bridge/                WKScriptMessageHandler、页面脚本
│       └── UI/                    主界面、登录与后台网页窗口、弹窗
├── Tests/
│   ├── bridge-contract-test.mjs   JS 桥接契约测试（Node）
│   ├── run-logic-checks.sh        纯逻辑测试（macOS 命令行）
│   └── logic-checks/main.swift
└── README.md
```

---

## 🔨 自己打包（Mac + Xcode）

**环境要求：** macOS + **Xcode 16 或更新**，运行目标 iOS 17+。

1. 在 Mac 上安装 Xcode（App Store 搜索 Xcode，约 10+ GB，装完要启动一次装组件）。
2. 下载本仓库源码（Code → Download ZIP，或 `git clone`）。
3. 双击 `TapSulor.xcodeproj` 打开工程。
4. 选中左侧的 **TapSulor** target → **Signing & Capabilities**：
   - 勾选 `Automatically manage signing`
   - **Team** 选你的 Apple ID（没有就点 `Add an Account`，用普通 Apple ID 登录即可，免费）
   - 若 `Bundle Identifier` 冲突，改成 `com.你的名字.tapsulor`
5. 想先在电脑上试跑：顶部选一台 **iPhone 模拟器**，按 `⌘R`。
6. 想导出 IPA：
   - 真机安装：顶部选你的 iPhone（需 USB 连接并信任电脑），`⌘R` 直接装上去。
   - 导出 IPA 文件：菜单 `Product → Archive`，等归档完成后在 Organizer 里点 `Distribute App`：
     - 免费账号：**Development** 方式可导出，但只能在你的设备上装，且 7 天过期
     - 付费账号：可选 **Ad Hoc**（指定设备）/ **App Store Connect**（TestFlight 分发）

### 常见报错

| 报错 | 处理 |
|---|---|
| `Signing for "TapSulor" requires a development team` | 第 4 步没选 Team |
| `No devices are available` | 打开 Xcode → Settings → Platforms，下载 iOS 模拟器 |
| `The request was denied by service delegate` / 白屏 | 在 Xcode 里看 Console 日志，把报错发给 AI |
| `Command PhaseScriptExecution failed` | 关掉 Xcode，执行 `xcode-select -p` 确认指向 Xcode，`sudo xcodebuild -license accept` |
| 少量 Swift 语法/SDK 差异报错 | 本工程开发环境只有命令行工具、没装 Xcode，**未经真正编译验证**，首次构建可能有少量报错，把报错贴给 AI 即可修 |

---

## 🤖 用 AI 协助打包

你不是必须懂 Xcode。准备好 Mac 后，把下面这段直接发给任意 AI（ChatGPT / Claude / 本助手都行）：

> 这是一个 iOS Xcode 工程（Swift + WKWebView），仓库地址是 `https://github.com/liusu239113/TapSulor-iOS`。我的电脑是 macOS __ 版本，Xcode 版本是 __。我想把它编译成 IPA 并装到我的 iPhone 上，请一步一步带我操作，每一步告诉我点哪里、输入什么命令。如果报错，我会把报错原文贴给你。

要点：
- **需要提供给 AI 的信息**：macOS 版本、Xcode 版本、报错原文（可截图或用 `xcodebuild` 命令行输出）。
- **可以直接让 AI 做的事**：解释报错、帮你改 `Info.plist` / Bundle ID、写 `xcodebuild archive` + `exportArchive` 命令行脚本、判断选 Development 还是 Ad Hoc。
- **AI 做不了的事**：它无法替你在你的 Mac 上点鼠标、也无法替你登录 Apple ID 完成签名授权，**这两步必须你自己操作**。

如果想让 AI 帮你写纯命令行打包脚本（不用打开 Xcode 图形界面），可以要求它生成类似：

```bash
xcodebuild -project TapSulor.xcodeproj -scheme TapSulor -configuration Release \
  -archivePath build/TapSulor.xcarchive archive \
  DEVELOPMENT_TEAM=你的TeamID CODE_SIGN_STYLE=Automatic
```

---

## ⚖️ 功能对照

| 安卓版 | iOS 版 |
|---|---|
| 多账号仓库、切换、删除（AccountManager） | `AccountStore`；每个账号使用独立的 `WKWebsiteDataStore`，切换账号时重建网页 |
| TapTap 开发者登录（LoginActivity） | `WebSheetViewController` 作为登录窗口；每次登录使用全新的数据存储，成功后写入账号 |
| 工作室切换 | `switchStudio` 记录选中的开发者 ID 并重建页面 |
| 收益 / DAU / 曝光数据 | 页面调用 `electronAPI.fetch`，原生用当前账号的 Cookie 发起 GET 请求，仅允许 taptap.cn、taptap.com |
| 游戏后台（BackendWebViewActivity） | 弹出 `https://maker.taptap.cn/` 首页（暂未按游戏跳转） |
| 检查更新（UpdateChecker） | 启动 3 秒后静默检查；设置里的「检查更新」会主动检查 |
| 前后台回调 | 回到前台触发 `__onAppResume`；前台期间每 5 分钟触发 `__onAppBackgroundTick` |
| 主题、字体、音效 | 由页面实现（localStorage）；音效由 WKWebView 播放 |

## 📌 已知差异

- **游戏后台地址**：安卓版的 `BackendWebViewActivity` 会接收 `EXTRA_APP_ID`（当前游戏 ID），但 DEX 里只能找到 `https://maker.taptap.cn/` 这一个地址，看不出如何按游戏跳转。iOS 版目前只打开 Maker 首页；如需直达游戏页，请提供地址格式，在 `AppCoordinator.openBackend` 里拼接。
- **屏幕录制**：安卓版的 `makerbridge` 内容脚本用于让 Maker 页面走 Electron 的录屏分支。WKWebView 不能录制屏幕，因此没有移植。
- **采集接口**：`getCapturedApis`、`replayApi` 在页面里没有被调用，iOS 版返回空结果。
- **探索页**：安卓版的 `ExplorerActivity` 在 iOS 上没有对应入口，`openExplorer` 为空实现。
- **更新检查**：读取 `ark.yanyususu.online/tapsulor/version.json`，只看 `ios_version`，下载地址依次取 `ios_url`、`app_store_url`、`testflight_url`、`download_page`。服务器上没有这些字段时不会提示更新。
- **后台运行**：iOS 不允许常驻后台，5 分钟轮询只在前台生效。
- **应用图标**：来自安卓版 1254 px 图标放大到 1024 px，建议换原版高清图。

## ✅ 验证情况

已完成的检查（命令行，不需要 Xcode）：

- `node Tests/bridge-contract-test.mjs`：桥接契约 9 项通过。
- `bash Tests/run-logic-checks.sh`：纯逻辑 58 项通过（账号规则、TapTap 数据解析、会话分类、Cookie 匹配、版本比较、accounts.json 读写）。
- 全部 Swift 源文件语法检查通过；针对 UIKit / WebKit 声明做了类型检查，0 个错误。
- `project.pbxproj`、`Info.plist` 格式校验通过，`Web/` 资源已正确挂入 Resources 构建阶段。

**未验证的部分**：开发环境只有命令行工具，没有安装 Xcode 和 iOS SDK，因此**没有真正编译过，也没在模拟器里跑过**。第一次在 Xcode 中构建可能出现少量 SDK 版本差异导致的报错，把报错发出来即可修正。

## 🔒 数据与安全

- 账号列表保存在 `Application Support/TapSulor/accounts.json`，不包含 Cookie。
- Cookie 保存在每个账号自己的 `WKWebsiteDataStore` 中，由系统管理。
- 删除账号会同时删除它对应的数据存储。
- 原生网络层只访问 `taptap.cn`、`taptap.com` 的 https 地址，页面无法把它当作任意网络代理使用。

## 📄 许可

沿用 Android 版协议，**GNU General Public License v3.0**。

---

<p align="center">
  开发者：<strong>流苏水寒</strong> · 联系 QQ：<a href="https://qm.qq.com/q/2391130219">2391130219</a>
</p>
