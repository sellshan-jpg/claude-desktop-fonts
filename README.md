# Clfont

[![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2026%2B-lightgrey)](#系统要求)
[![Release](https://img.shields.io/github/v/release/sellshan-jpg/clfont)](https://github.com/sellshan-jpg/clfont/releases/latest)

**简体中文** | [English](README.en.md)

Clfont 是一款 macOS 工具，用于替换 Claude 桌面版界面中的字体。可选择只替换中文、
只替换英文，或两者同时替换；未被选中的部分与界面图标均保持原有渲染效果。

> **声明**
>
> 本项目为第三方工具，与 Anthropic 无任何隶属或合作关系。源码公开以供查证，
> 采用非商业许可（见[许可证](#许可证)）。使用时会修改本机安装的 Claude.app，
> 并变更其代码签名，请在使用前完整阅读[代码签名的影响](#代码签名的影响)一节。

## 目录

- [工作原理](#工作原理)
- [安全性](#安全性)
- [系统要求](#系统要求)
- [安装](#安装)
- [使用方法](#使用方法)
- [代码签名的影响](#代码签名的影响)
- [已知限制](#已知限制)
- [问题反馈](#问题反馈)
- [从源码构建](#从源码构建)
- [命令行接口](#命令行接口)
- [项目结构](#项目结构)
- [许可证](#许可证)

## 工作原理

Claude 桌面版的界面内容由远程 `claude.ai` 提供，其字体来自两个 Web 字体族：
`anthropic-sans` 与 `anthropic-serif`。

Clfont 在 `app.asar` 的 renderer preload 中追加一段脚本，向页面注入如下形式的
样式规则：先声明一个自有字体族，只覆盖需要替换的码位；再把它前插到 Claude 的
字体变量中。

```css
@font-face {
  font-family: ClaudeCJKSerif;          /* 自有族名，不与页面既有族同名 */
  src: local("STSongti-SC-Regular");
  unicode-range: U+4E00-9FFF, ...;      /* 仅覆盖 CJK 码位 */
}
:root {
  --font-anthropic-serif: "ClaudeCJKSerif", "anthropic-serif", ui-serif, ... !important;
}
```

字体栈按字符逐个求值：某字符不在前一个族的 `unicode-range` 内时，交由栈中下一个
族渲染。因此被覆盖的码位使用指定字体，其余码位仍由 Claude 原本的 Web 字体处理。
替换范围即由 `unicode-range` 决定：

| 替换范围 | 覆盖的码位 |
| --- | --- |
| 中文 | `U+2E80-2EFF`、`U+3000-303F`、`U+3400-4DBF`、`U+4E00-9FFF`、`U+F900-FAFF`、`U+FF00-FFEF` |
| 英文 | `U+0020-007E`（基本拉丁），正文另含 `U+00C0-00FF`、`U+0100-017F`（带重音的拉丁字母） |
| 中英文 | 以上全部 |

英文范围**刻意不含拉丁文补充区中的符号段与私用区**。Claude 界面中的图标由字体
字形实现，实测显示其码位落在这些区段；将其排除可确保替换英文时图标不受影响。
带重音的拉丁字母只对正文字体放开，承载图标的界面字体不放开。

**不能给 `anthropic-sans` / `anthropic-serif` 追加同名 `@font-face`。** 这两个族由
页面用 `url()` 加载。向其追加声明会使 Chromium 重建该族，已加载的 Web 字体被置回
未加载状态且不再取回，结果是全部西文衬线沿后备链掉到 `Georgia`。实测：追加前该族
状态为 `loaded`、数字串宽 259.63px；追加后为 `unloaded`、宽 251.97px（即 Georgia），
15 秒后及显式调用 `document.fonts.load()` 之后均不恢复。因此替换一律经由变量前插，
自有族名与页面既有族名不重叠。

粗体所用的字面按实测笔画粗细选取。部分字体自带的 Bold 与其正体差别过小——宋体为
1.16 倍墨量、楷体为 1.23 倍，而多数字体在 1.34 倍以上——此时改用同族更重的一档。

该方案的关键特性是**不修改任何 `font-family` 声明**。Claude 界面中的图标由字体
字形实现，若通过覆盖 `font-family` 的方式替换字体，图标将无法正常显示。

修改 `app.asar` 后，需同步更新 `Info.plist` 中的 `ElectronAsarIntegrity` 哈希值
并重新签名，否则应用无法启动。

## 安全性

Clfont 的全部操作均在本机完成，具体范围如下：

- **修改前先检测环境。** 缺少必要组件时直接给出提示并终止，不会留下改到一半的
  应用。
- **注入内容仅有样式规则。** 写入页面的只有 CSS：`@font-face` 声明，以及字体族与
  底色两类自定义属性的取值。作用范围限于指定码位的字形渲染与界面底色。不改动任何
  网络请求，不伪造客户端身份，不绕过任何限制、配额或计费。
- **不接触账号与会话数据。** 不读取、不上传账号信息与聊天记录。唯一的对外请求是
  检查更新时读取本项目的 GitHub Releases 接口（`api.github.com`），该请求不携带
  任何本机信息，可在「关于」窗口中关闭自动检查。
- **可完整撤销。** 安装前创建完整应用备份。任一环节失败或中途取消都会将文件恢复
  至修改前的内容并重新验证签名；如需连同 Anthropic 的原始签名一并恢复，使用
  「还原」——在备份与当前版本匹配时可完全还原。

以上内容均可在源码中查证：注入的 CSS 由 `clfont` 中的 `build_css` 生成，写入方式
见同文件的 `build_preload_injection`。

需要说明的是，本工具通过修改应用包实现上述功能，该行为可能不符合 Claude 的使用
条款。项目作者不对使用本工具产生的任何后果作出担保，是否使用请自行判断。

## 系统要求

| 项目 | 要求 |
| --- | --- |
| 处理器 | Apple Silicon |
| 操作系统 | macOS 26 及以上 |
| 依赖组件 | 无 |

自 6.0 起不再需要任何额外组件。命令行工具已由 Python 重写为 Swift 并直接编入
应用包，只调用 `codesign`、`ditto`、`du`、`ps` —— 四者均为系统自带的可执行文件。
此前必需的 Xcode 命令行工具不再需要：它提供的 `python3` 实为一个 118KB 的转发
壳，未安装时无法运行。

## 安装

1. 从 [Releases](https://github.com/sellshan-jpg/clfont/releases) 下载
   `Clfont.app`，移动至「应用程序」文件夹。
2. 本应用采用 ad-hoc 签名，未经 Apple 公证，首次打开时 Gatekeeper 会予以拦截。
   请执行以下命令移除隔离属性：

   ```bash
   xattr -dr com.apple.quarantine /Applications/Clfont.app
   ```

   亦可通过右键点击应用图标，选择「打开」，并在确认对话框中再次选择「打开」。

应用界面提供简体中文与英文，默认跟随系统语言，也可在「关于」窗口中手动切换。

首次执行修改时，macOS 会请求「App 管理」权限（修改其他应用的应用包所需）。
请选择「允许」；若误选了「不允许」，程序会在界面中说明并提供前往
「系统设置 → 隐私与安全性 → App 管理」的入口，打开开关后重新执行即可。

Clfont 启动时会在后台向 GitHub 查询一次是否有新版本，每日至多一次，仅读取
Releases 接口，不发送任何本机信息。有新版本时在界面中给出提示，查询失败不作提示。
该功能可在「关于」窗口中关闭。

## 使用方法

1. **选择目标**：通常为 `/Applications/Claude.app`。
2. **选择替换范围与字体**：「中文」只替换中文字形，界面图标不受影响，为推荐选项；
   「英文」与「中英文」会一并改变界面英文的观感。选定范围后选择对应字体。
3. **字号**：中文与英文可分别在 80% 至 150% 之间调节，用于弥补宋体等字体默认
   显示偏小的问题。该设置通过 `@font-face` 的 `size-adjust` 实现，只缩放被替换
   的字符本身，不改动任何 `font-size` 值，因此界面图标、行距与整体布局均不受
   影响。
4. **兼容模式**：保持「标准」即可；若个别区域未生效，再切换至「扩展」，该模式会
   将同样的覆盖规则扩展到更多常见字体族。
5. **执行安装**：点击「应用」，整个过程约需 1 至 2 分钟。

安装流程依次为：退出目标应用 → 创建完整备份 → 重新打包 `app.asar` → 更新完整性
哈希 → 重新签名 → 启动验证。任一环节失败或用户中途取消，都会将文件恢复至修改前
的内容，并重新签名与验证，Claude 仍可正常启动。

需要注意的是，**自动回滚只恢复文件内容**：收尾的重新签名同样采用 ad-hoc 签名，
应用的代码签名不会回到 Anthropic 的原始签名。若需连同原始签名一并恢复，请使用
「还原」，见[恢复原始签名](#恢复原始签名)。

如需撤销修改，点击「还原」。如遇异常，可点击「自检」，程序将检查应用完整性、
未完成事务、字体可用性、磁盘空间、哈希与签名状态，结果记录于日志中。

## 代码签名的影响

**这是使用本工具前最需要了解的事项。**

Claude 官方版本由 Anthropic 签名（`TeamIdentifier=Q6L2SF6YDW`），启用了 hardened
runtime，并声明了一组 entitlements。由于修改 `app.asar` 后必须重新签名，而本工具
无法获得 Anthropic 的签名证书，只能采用 ad-hoc 签名。由此产生以下影响：

- **`keychain-access-groups` 权限丢失。** 该权限包含 WebAuthn 通行密钥及
  Microsoft workplace join 相关的钥匙串访问组。该条目与开发者身份绑定，ad-hoc
  签名下无法保留。使用通行密钥或 Microsoft / Entra SSO 登录 Claude 的用户可能
  无法完成身份验证。
- **hardened runtime 被关闭。** 应用的安全防护等级随之降低。
- **TCC 权限记录失效。** 系统按代码签名身份记录隐私权限，签名变更后，麦克风、
  通知等权限需要重新授权。
- **钥匙串重新授权。** 重新签名后首次启动时，系统会要求重新授权
  「Claude Safe Storage」。该弹窗可能连续出现多次（实测最多 4 次），每次输入登录
  密码并选择「始终允许」即可，属预期行为。

其余 entitlements 会被完整保留。修改只涉及 `Contents/Resources/app.asar` 与
`Contents/Info.plist`，二者均由顶层签名封存，Claude 内部各组件（Helper、
Framework）的签名并未被破坏，因此重新签名只作用于顶层 bundle；顶层则在首次修改
前记录原版 entitlements，并在此后每次签名时一并写回。`com.apple.security.virtualization`
（Cowork 与本地虚拟机所需）等条目由此得以保留。

> **5.2 之前的版本**在重新签名时使用了 `codesign --deep`，会连同 Claude 内部各
> 组件一起重签，其 entitlements 被全部清除，Cowork 与虚拟机功能因此不可用。若你
> 使用过这些版本，升级后程序会检测到该情况并在界面中提示，执行一次「应用」即会
> 先从完整备份还原、再进行修改，权限随之恢复；若没有可用备份，需从
> <https://claude.ai/download> 重新下载安装 Claude。

### 恢复原始签名

Clfont 在首次修改前会创建完整应用备份，保存于
`~/.local/share/clfont/Claude-backup-<版本号>.app`，该备份为未经修改的原始版本。

恢复原始签名只有「还原」这一条路径。安装过程中的自动回滚不走备份，它只把文件改
回修改前的内容再重新签名，签名仍为 ad-hoc。因此若安装失败后需要让 Claude 回到
完全未经改动的状态，请再执行一次「还原」。

执行「还原」时，若能匹配到当前版本对应的备份，程序将直接从备份恢复整个应用包，
**Anthropic 的原始签名、hardened runtime 及全部 entitlements 会一并恢复**。还原
完成后会输出 `TeamIdentifier` 以供确认。

若备份与当前版本不匹配（例如 Claude 已自动更新至新版本），还原操作仅能恢复文件
内容并重新执行 ad-hoc 签名，原始签名无法复原。此种情况下，建议从
<https://claude.ai/download> 重新下载并安装 Claude。执行 `clfont doctor` 可查看
当前所处的状态。

### 备份占用与清理

每个目标最多保留 2 份整包备份，超出的会在下次安装时自动清理。备份通过 `ditto`
创建，在同一 APFS 卷上为写时复制克隆，创建时几乎不占额外空间；但 Claude 更新后，
旧版本备份持有的数据块不再与现有文件共享，会转为实际占用。

在应用内展开状态卡的「详情」可查看当前目标的备份占用，并清理已无法用于还原的
旧版本备份（与当前版本一致的那份会被保留，因为只有它能恢复原始签名）。命令行
使用 `clfont backups`；若曾对多个 Claude 使用过本工具，`clfont backups --all`
可列出并清理其他目标遗留的备份。

## 已知限制

- **Claude 自动更新会覆盖已应用的修改。** 程序检测到这一情况时，会在主界面给出
  提示并附带「重新应用」按钮，点击即可恢复，字体设置无需重新选择。
- **实现依赖 Claude 当前的构建细节。** 字体族名称 `anthropic-sans` 与
  `anthropic-serif`、字体变量 `--font-anthropic-serif` / `--font-anthropic-sans`、
  代码字体钩子 `--font-mono-override` 与底色变量 `--cds-surface-*` 均来自远程
  `claude.ai`；打包路径 `.vite/build/mainView.js`、`ElectronAsarIntegrity` 机制及
  Electron fuse 配置来自当前桌面版构建。上述任一项发生变化，都可能导致修改失效，
  需等待 Clfont 更新。
- **无法覆盖 CSS 通用字体关键字。** `system-ui`、`-apple-system`、`sans-serif`
  等为 CSS 关键字，`@font-face` 不接受将其作为字体族名称，因此使用此类字体栈的
  区域，中文仍由系统默认字体渲染。Claude 自身的字体栈经由 `--font-anthropic-sans`
  等变量给出，实际测试中未出现此情况。

## 问题反馈

如遇 Claude 本身运行异常，请先通过「还原」将其恢复至原始状态，再判断问题是否
与本工具相关。向 Anthropic 提交问题报告前，请确认目标应用未处于被修改的状态。

与 Clfont 相关的问题，欢迎提交至
[Issues](https://github.com/sellshan-jpg/clfont/issues)。

## 测试

```bash
python3 tests/test_clfont.py            # 全部
python3 tests/test_clfont.py test_asar  # 按名字筛选
UPDATE_GOLDEN=1 python3 tests/test_clfont.py   # 有意改动行为后更新黄金文件
```

```bash
CLFONT_BIN=build/clfont-swift python3 tests/test_clfont.py   # 改测 Swift 实现
```

约 75 秒，无第三方依赖。测试分两层：纯函数层直接调用 `clfont` 里的函数；端到端
层对 `tests/fixture.py` 造的假 Claude.app 跑真命令，覆盖安装、还原、幂等、冒烟
失败回滚、六个崩溃注入点的恢复，以及 GUI 所依赖的状态标记。

不使用真实的 Claude.app：一次整包备份要 800MB 与约一分钟，且测试一旦改坏它，
用户日常使用的应用就废了。假 app 只有 64KB，全流程秒级完成。

两个实现的一致性由三条测试保证：相同配置下注入的 CSS 逐字节相同；原样重打包
asar 与原文件逐字节相同；五个子命令的完整输出在归一化路径、哈希与时间戳后逐字
相同。最后一条尤为必要——GUI 依据输出中的字面量解析状态，措辞偏差不会导致报错，
只会让界面长期显示错误的状态。

## 从源码构建

```bash
./gui/build.sh                  # 输出至 build/Clfont.app（含编译 CLI）
./cli/build.sh                  # 只编译 CLI，输出至 build/clfont-swift
```

构建需要 Xcode 提供的 `swiftc` 与 `iconutil`。图形界面使用了 macOS 26 的 Liquid
Glass API，因此编译目标为 `arm64-apple-macos26.0`。

## 命令行接口

命令行工具可独立使用：

```bash
clfont install --mode auto                 # 应用修改
clfont install --scope both --scale 120 --scale-latin 90   # 指定范围与字号
clfont status                              # 查看当前状态
clfont doctor                              # 环境自检
clfont uninstall                           # 还原
clfont backups                             # 列出整包备份与占用
clfont backups --prune                     # 清理已无法用于还原的旧备份
clfont backups --all                       # 连同其他目标的备份一起列出
clfont --app /path/to/Claude.app install   # 指定其他 Claude 安装位置
```

## 项目结构

| 路径 | 说明 |
| --- | --- |
| `cli/` | 命令行工具，Swift 实现，编入应用包；全部文件操作在此完成 |
| `clfont` | 同一工具的 Python 实现。**不参与运行**，作为回归测试的对照基准保留 |
| `tests/` | 回归测试。同一套断言在两个实现上运行，输出须逐字一致 |
| `gui/ClfontApp.swift` | SwiftUI 图形界面，仅调用命令行工具，不直接操作目标应用 |
| `gui/render-icon.swift` | 应用图标绘制程序，由构建脚本调用 |
| `gui/build.sh` | 构建脚本：编译、生成图标、组装 bundle、签名 |

## 许可证

Copyright © 2026 赵万 (Jovan)。本项目采用
[PolyForm Noncommercial License 1.0.0](LICENSE)，为源码公开（source-available）
而非开源许可，要点如下：

- **个人与非商业用途免费**，包括个人研究、学习与自用。
- **禁止任何商业用途**，包括但不限于收费分发、内置于付费产品、或用于营利性组织
  的业务活动。
- 允许查看、修改与再分发，但**必须保留本许可证与版权声明**，且再分发同样受
  非商业限制约束。

以许可证原文为准。若需商业授权，请通过
[Issues](https://github.com/sellshan-jpg/clfont/issues) 联系。
