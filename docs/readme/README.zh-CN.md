[English](../../README.md) · **简体中文（zh-CN）** · [繁體中文（zh-TW）](README.zh-TW.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Українська](README.uk.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [हिन्दी](README.hi.md) · [বাংলা](README.bn.md) · [Bahasa Indonesia](README.id.md) · [Tiếng Việt](README.vi.md) · [ไทย](README.th.md) · [தமிழ்](README.ta.md) · [తెలుగు](README.te.md) · [मराठी](README.mr.md) · [العربية](README.ar.md) · [اردو](README.ur.md) · [فارسی](README.fa.md) · [Kiswahili](README.sw.md) · [ਪੰਜਾਬੀ](README.pa.md) · [Filipino](README.fil.md)

# PromptFinch

**选择。优化。粘贴。**

PromptFinch 是通用的 Prompt 编辑与优化工具，适用于写作、编程、研究、摘要与规划。将粗略需求整理成更清楚的指令，供你选择的模型使用。

macOS App 结合手动工作台与选择助手：在兼容应用中选中文本并点击右键，于辅助操作菜单选择 **Convert to an English Prompt**，再于附近面板查看结果。仅点击右键不会生成内容，也不会将内容发送给模型。另有使用相同后端的浏览器工作台与 HTTP API。

macOS App 与 API 的英文模式会将多语输入整理为英文 Prompt，并以保留明确需求、指定答案语言与固定字符串为设计目标。它只会编辑指令，不会执行原始任务。使用前请检查生成结果。

## 功能

- 接受原始 Prompt、任务类型，以及可选的下游目标模型名称。
- 生成可复制的 Prompt，并将优化说明与假设分开呈现；复制及贴回只会使用 Prompt 字段。
- macOS App 提供手动输入、文本选择操作、结果面板、模型配置及可选的贴回功能。
- 处理空白输入、长度限制、加载、取消与易懂的错误信息。
- 可在明确标注的 mock 模式下无需密钥检查流程，或由 Node.js 后端调用已配置的 OpenAI 兼容模型。

GitHub 仓库名称建议为 `promptfinch`。请参阅[更名与兼容性说明](../branding.md)。任务类型包括通用、写作、分析、编程、摘要与营销；研究与规划可选分析或通用。可选**目标模型**只作为编辑 Prompt 的提示，不会切换后端生成模型；后端模型由 `LLM_MODEL` 配置。

目前的应用界面及优化说明／假设主要使用繁体中文。本项目文档提供 29 种语言／文字版本，但不包含 App 界面的翻译，也不代表所有输入语言均已通过验证。

## 系统需求

| 用途 | 需求 |
| --- | --- |
| 浏览器工作台／HTTP API | Node.js 22 或更新版本；不需第三方运行时依赖。 |
| macOS 原生 App | macOS 13 或更新版本作为编译目标，并安装 Node.js 22+ 运行时。App 不包含 Node。 |
| 构建 macOS App | Apple Xcode Command Line Tools，包含 Swift 与 Apple 签名工具；不需要完整 Xcode。 |
| 开发与浏览器测试 | `npm ci` 安装开发依赖；Playwright 需要已安装的测试浏览器。 |

原生构建会依 Node 程序架构产生 `arm64` 或 `x86_64`，不是 Universal Binary。已记录的原生检查是在 Apple Silicon 上运行；尚未在实体 Intel 设备或最低 macOS 13 版本上验证。

以下指令请在项目根目录、macOS 或常见 Linux 环境提供的 POSIX shell 运行。

## 快速开始

### 浏览器演示（不需 API 密钥）

```sh
# Create a local configuration only if one does not already exist.
cp -n .env.example .env
npm start
```

打开 [http://127.0.0.1:3000](http://127.0.0.1:3000)。若 `.env` 已存在，请先检查内容，并配置 `OPTIMIZER_MODE=mock` 进行本地演示，不要覆盖原文件。运行服务不需要 `npm install`。

**Mock 输出不会翻译，也不会进行语义优化。**它是用来检查输入、加载、结果显示和复制流程的模板，不会调用模型或将 Prompt 传送给供应商。

浏览器默认使用英文指令。选择 **繁体中文 Prompt** 可使用原本的中文优化流程。这只控制指令语言；原始需求中明确指定的答案语言仍会保留。Mock 模式会清楚说明内容并未真正翻译。

### 构建并安装 macOS App

```sh
xcode-select --install  # Skip if Command Line Tools are already installed.
npm run setup:signing:mac
npm run build:mac
npm run install:mac
```

构建结果为 `build/PromptFinch.app`。安装程序会将 App 放入用户的 `~/Applications` 并打开。无需另外启动浏览器服务器：App 会在 `http://127.0.0.1:3210` 启动自己的后端。

安装程序会将现有的 `Prompt 選取助手.app` 迁移为 `PromptFinch.app`，并保留签名身份、配置路径与已存储的偏好设置；详见[更名说明](../branding.md)。

`setup:signing:mac` 是每台电脑各自执行一次的本地签名身份配置。私密签名密钥会存放在登录钥匙串；macOS 可能要求确认访问。这有助于在本地重建时保持辅助功能权限身份稳定。这不是 Developer ID 签名或公证，且不得发布签名密钥。若现有签名配置无效，构建会停止，不会暗中取代身份。

若未选择模型配置，App 会使用 mock 模式。在 App 的「设置」中建立或选择模型配置文件、填入供应商配置并重新加载配置。若 App 找不到 Node，请在 App 的「设置」中选择其可执行文件。

也可在安装时指定现有配置：

```sh
npm run install:mac -- --config .env
```

更多 macOS 配置请参阅目前以繁体中文编写的 [macOS 指南](../macos.md)。

## 模型配置

实时生成使用 **OpenAI 兼容的 Chat Completions** 端点。后端会在 `LLM_BASE_URL` 后附加 `/chat/completions`。用户需自行提供模型供应商账户并承担相关费用。

新配置可参考 [.env.deepseek.example](../../.env.deepseek.example)：

```dotenv
OPTIMIZER_MODE=live
LLM_API_KEY=YOUR_MODEL_API_KEY
LLM_BASE_URL=https://api.deepseek.com
LLM_MODEL=deepseek-flash
LLM_JSON_MODE=true
LLM_THINKING_MODE=disabled
LLM_TIMEOUT_MS=90000
HOST=127.0.0.1
PORT=3000
```

请在私人本地配置中以自己的密钥取代 `YOUR_MODEL_API_KEY`。修改现有 `.env`，不要覆盖它。浏览器服务器的配置更改后需重新启动；Mac App 则需重新加载所选配置。

其他兼容供应商可替换基本 URL、密钥与模型识别码。若供应商不接受 DeepSeek 思考参数，请将 `LLM_THINKING_MODE` 留空。若供应商不接受 JSON 模式，请配置 `LLM_JSON_MODE=false`；但它仍必须返回优化器要求的有效 JSON。原生 Claude 或 Gemini 端点需要适配器或兼容网关，不能直接填入 Chat Completions URL。

不需验证的本地兼容服务可以 `LLM_API_KEY=local-only` 作为非敏感信息占位值，并配置该服务实际的基本 URL 与已加载模型名称。这不会启动或随附本地模型。

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `OPTIMIZER_MODE` | `mock` | `mock` 使用模板；`live` 调用模型。 |
| `LLM_API_KEY` | 空白 | 仅供后端使用的 Bearer 认证；实时模式必填。 |
| `LLM_BASE_URL` | `https://api.openai.com/v1` | 兼容 API 基本 URL；不得含内嵌认证、查询或片段。 |
| `LLM_MODEL` | 空白 | 供应商模型标识符；实时模式必填。 |
| `LLM_JSON_MODE` | `true` | 传送 `response_format: {type: "json_object"}`。 |
| `LLM_THINKING_MODE` | 空白 | 留空时不传送；可用 `enabled` 或 `disabled`。 |
| `LLM_TIMEOUT_MS` | `45000` | 请求／响应超时；整数范围 10 至 180000 毫秒。 |
| `HOST` | `127.0.0.1` | 独立服务器的监听地址。 |
| `PORT` | `3000` | 独立服务器端口。 |

Mac App 无论所选配置文件中的值为何，都会将 `HOST` 与 `PORT` 设为 `127.0.0.1:3210`。独立浏览器服务器可使用另一个端口。

实时配置或供应商调用失败时会报告错误，不会默默改用 mock 结果。`/api/config` 的 `ready` 表示配置已填妥，不代表已成功连上上游模型。

## 示例：Prompt 语言与答案语言

原始需求：

> 编写一段简短邀请。保持 ACME-42 不变。请用西班牙语回答。

以下是示意的优化结果，并非实际记录的模型响应：

```text
Write a brief invitation in Spanish. Preserve the exact text "ACME-42" wherever it occurs.
```

指令本身为英语，但要求下游模型编写的邀请仍为西班牙语。优化器返回的是指令，而不是代为编写邀请。模型收到的指示包括保留明确需求与固定字符串、标示合理假设并避免改变任务意图；仍应检查遗漏或误译。

## 多语输入与涵盖范围

- 输入、JSON 传输及原生选择均支持 Unicode。12,000 字符上限以 UTF-16 code unit 计算，与 JavaScript 及 Swift 的 UTF-16 视图一致，不按可见字母或字素簇计数。超过上限会拒绝请求，不会截断。选择范围不能切开 surrogate pair。参阅 [JavaScript length](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/length) 与 [Swift UTF16View](https://developer.apple.com/documentation/swift/string/utf16view)。
- 韩语谚文、俄语西里尔字母、由右至左文本、组合附加符号、连接符、表情符号及混合文本皆可输入，不会对文本进行规范化或按字母系统过滤。浏览器输入栏会自动调整文本方向。界面与审阅备注仍为繁体中文；这不代表 App 界面已翻译成 28 种语言。
- 英文模式会分开处理指令语言与下游答案语言。模型必须保留明确答案语言要求、否定范围、固定字符串、变量、代码与 URL。若引号或代码中的固定字符串仅因 NFC 规范化而被更改，后端会以有限规则修复明确可判定的情况。若字符串被省略、翻译或改为语义相近但拼法不同，后端无法重建；重要字符串请自行检查。
- 涵盖目标包括英语、繁体／简体中文、西班牙语、法语、德语、葡萄牙语、义大利语、俄语、土耳其语、荷兰语、波兰语、乌克兰语、日语、韩语、印地语、孟加拉语、印尼语、越南语、泰语、泰米尔语、泰卢固语、马拉地语、阿拉伯语、乌尔都语、波斯语、斯瓦希里语、旁遮普语与菲律宾语。这不是通用的 GitHub 语言标准，也不代表模型有通用质量保证。
- 2026-10-09 的实时示例使用现有 `deepseek-flash` 配置：韩语和俄语各有简短、中等和较长案例；其他示例涵盖英语、两种中文、日语、西班牙语、法语、德语、葡萄牙语、义大利语、乌克兰语、阿拉伯语、波斯语、印地语、孟加拉语、泰语、越南语和印尼语。另有一个英文指令案例检查混合韩／俄字符串、NFD 重音、表情符号、变量与 URL；它不能取代韩语／俄语语义测试。
- 总计是 18 种语言的 24 个独立合成案例，并依发现的问题进行定向重测。最终 Prompt 示例符合审阅的核心限制；一项日文优化说明仍不够精确。其他目标语言、其他模型、复杂领域输入、原生 RTL 显示及所有宿主 App 工作流程都尚未认证。完整 Prompt 与审阅结果见[公开验证记录](../multilingual-verification.md)。

## HTTP API

独立服务器默认为 `http://127.0.0.1:3000`。原生 App 管理的后端使用 `http://127.0.0.1:3210`。

```sh
curl --fail --silent --show-error http://127.0.0.1:3000/api/config

curl --fail --silent --show-error http://127.0.0.1:3000/api/optimize \
  -H 'Content-Type: application/json' \
  --data '{"prompt":"Write a brief invitation. Keep ACME-42 unchanged. Answer in Spanish.","task":"writing","targetModel":"","promptLanguage":"en"}'
```

| 请求字段 | 行为 |
| --- | --- |
| `prompt` | 必填且不可空白；最多 12,000 个 UTF-16 code unit。 |
| `task` | `general`（默认）、`writing`、`analysis`、`coding`、`summary` 或 `marketing`。 |
| `targetModel` | 可选下游模型提示；单行，最多 80 个 UTF-16 code unit。 |
| `promptLanguage` | `en` 表示英文指令；未提供时默认 `zh-Hant`。 |

成功时返回 `prompt`、`improvements`、`assumptions`、`mode`、`generationModel` 与 `promptLanguage`。重用结果时只复制 `prompt`；优化说明与假设是独立的审阅备注。英文模式的备注仍使用繁体中文。

API 会验证输入与模型响应结构、限制同时进行的优化请求，并报告配置、供应商、格式错误和超时错误。取消操作会关闭上游请求；供应商端的处理和计费仍由供应商控制。

## macOS 操作流程

1. 打开 App 手动工作台，输入或贴上需求，选择任务与可选目标模型，再生成英文 Prompt。
2. 检视 Prompt 与分开显示的备注。可复制 Prompt，或清空工作区以移除输入与结果。
3. 使用文本选择操作时，依提示在系统设置中启用「辅助功能」。在兼容的输入框中选择文本并按右键，再于辅助菜单选 **Convert to an English Prompt**；结果会显示在附近。宿主 App 原有的上下文菜单仍可使用。按取消、点击其他位置、键盘输入、切换 App 或等待 12 秒，都会关闭操作提示而不生成结果。只有在明确选择该操作后，助手才会再次检查选择内容。也可使用选择按钮。部分 Electron App 可能显示启用提示：等待约两秒、重新选择文本后再试。
4. 其他入口包括默认的 Option-Command-P 快捷键、支持的 macOS 服务，以及明确的剪贴板操作。宿主 App 必须提供可用的文本选择功能，因此不保证所有 App 都兼容。
5. 可选自动贴回会检查来源 App、焦点字段、文本与选择范围后才取代已选文本。若无法再确认来源，则改为复制结果。面板也提供复制及手动贴回。贴回不会送出聊天信息，并可在配置中停用。Mock 结果不会贴回。

关闭工作区窗口后，选择助手仍会在菜单栏运作；结束 App 则会停止由它启动的后端。辅助菜单是独立且不会启用宿主 App 的操作面板，不会插入宿主 App 原有的上下文菜单。详见[右键操作验证](../context-menu-verification.md)。

### 仅更新原生后端

更改可信任的后端或浏览器代码后，可只更新已安装 App 的外部后端，不必重建已签名的原生可执行文件：

```sh
npm run update:mac-backend
```

更新程序会先暂存并以 mock HTTP 检查候选版本，正常关闭 App、检查端口，再切换后端版本并重新启动 App。若启动失败会尝试恢复。它不会更改所选模型配置，也不会终止无关的端口监听进程。Swift 或原生 UI 更改仍须运行 `build:mac` 与 `install:mac`。

## 架构

```text
Native macOS workspace / selection result panel
  -> SwiftUI + AppKit client
  -> app-managed Node.js backend on 127.0.0.1:3210

Optional browser workspace / HTTP API client
  -> standalone Node.js backend on 127.0.0.1:3000

Either backend
  -> labeled mock template, or configured model provider
  -> prompt + separate improvements / assumptions
```

主要原始码：

- [server.js](../../server.js)：HTTP API、静态文件、请求验证与错误处理。
- [lib/optimizer.js](../../lib/optimizer.js)：配置、mock／实时模型适配器、编辑指示与响应验证。
- [public/](../../public)：支持响应式版面的繁体中文浏览器工作台。
- [macos/Sources/](../../macos/Sources)：原生工作台、后端生命周期、选择、结果面板与贴回功能。
- [scripts/](../../scripts)：原生构建、本地签名、安装、后端更新与开发检查。

## 隐私与数据处理

- API 密钥由 Node.js 后端从本地配置读取，不会暴露在前端代码或封装进 App。目前密钥以纯文本环境文件保存；尚未整合 Keychain 密钥存储。
- 输入、结果与说明在内存中处理，不使用数据库或 Prompt 历史记录。原生偏好设置及配置路径会存储在本地。原生诊断记录状态元数据与长度，不记录 Prompt 内容。
- 实时模式会将请求与编辑指示传送至已配置的模型供应商，并受该供应商的数据保留政策约束。Mock 不会调用模型。
- 浏览器界面不使用 Cookie、浏览器存储、分析工具或远程字体；重新加载会清空工作区。原生工作区可透过清除操作或结束内存会话清空。
- 启用文本选择操作后，App 会监听鼠标事件并读取可访问的文本选择内容。若安全的可编辑字段提供非空选择范围但没有选择文本属性，助手可能暂时读取字段值。超过 65,536 个 UTF-16 code unit 的值会被拒绝；只会返回选择范围，也不会记录字段内容。
- 复制、贴回及备用复制会使用系统剪贴板。恢复操作会先确认用户没有复制新内容。清空工作区不会删除已复制到系统剪贴板的文本。

这是供个人本地使用的工具，没有账户验证或多用户隔离。独立服务器支持部署配置，但公开部署需要自行配置 HTTPS 与访问控制。远程部署及 Docker 运行尚未验证。

## 验证结果与限制

以下检查结合 2026-10-09 的多语更新与明确右键菜单修正。浏览器与实时模型证据属于多语更新，没有在此次仅涉及原生代码的修改中重跑。

| 已记录检查 | 范围 |
| --- | --- |
| JavaScript 语法与 Node HTTP 测试 | 语法通过；49 个后端测试通过，涵盖 Unicode 传输、UTF-8 分块边界、NFC 固定字符串修复与不截断长度验证。 |
| 原生核心／API／剪贴板检查 | 81 项通过：原有 66 项，加上明确菜单选择、取消／关闭、AppKit 按钮操作只执行一次，以及来源更改、逾期、忙碌或停用时的保护。 |
| 浏览器流程测试 | 10 项 Chrome 测试通过，包含英语／中文切换、混合 Unicode、RTL 方向、超长 emoji 插入不会静默截断、复制、错误、取消及 390／320px 窗口。 |
| 实时模型样例 | 18 种语言共 24 个案例，包含韩语／俄语简短、中等和较长案例。人工审阅的核心 Prompt 通过；一项日文优化说明仍不够精确。 |
| 原生工作区与 IDE（现有证据） | 曾手动观察生成及清除流程。用户确认 Codex 面板恢复正常，并在新版菜单修改前提到 Claude 也可使用；这不代表新版每项操作都已认证。 |
| 新版右键菜单（用户验收） | 用户确认原上下文菜单仍存在、辅助菜单出现时不会自动生成，并在明确点击后取得英语结果。 |

新版菜单已由用户确认可显示并以一次点击生成；各宿主 App 中完整的复制／贴回／取消测试仍有限。先前 Codex／Claude 的成功经验不代表新版所有操作均已认证。未测试的语言与其他宿主 App 仍未验证。浏览器窗口尺寸测试不等同实体 iOS 或 Android 测试。HTTP 成功及受控供应商 Unicode 往返测试都不代表翻译质量。

尚未提供或验证：OCR、可配置的全局快捷键、包含 Node、功能自动更新、Universal Binary、Developer ID 签名、公证、下载二进制文件的 Gatekeeper 行为、其他实体 macOS／CPU 组合及公开二进制发行版。项目包含 GitHub 检查工作流程，但尚未验证远程运行。README 不宣称提供预先构建下载文件或成功的 CI 徽章。

## 开发

```sh
npm ci
npm run check
npm test

# Browser checks: install the test browser once.
npx playwright install chromium
npm run test:ui

# Alternatively, use an installed Google Chrome.
PLAYWRIGHT_CHANNEL=chrome npm run test:ui

# macOS-only checks and native build.
npm run test:mac
npm run build:mac
```

`npm run dev` 会以 Node watch 模式运行独立服务器。API 测试使用本地假模型服务，不代表真实模型翻译质量。原生测试不能取代在各宿主 App 中以实体操作测试文本选择及右键流程。项目包含 [GitHub workflow](../../.github/workflows/check.yml)，涵盖 Node 检查与 macOS 原生检查／构建，但不代表已发布或已确认远程 CI 运行结果。

## 贡献与授权

开发规范请参阅 [CONTRIBUTING.md](../../CONTRIBUTING.md)。欢迎修正翻译，以及使用可分享合成输入的可复现的问题报告。请勿在贡献中放入 API 密钥、本地环境文件、私人 Prompt、剪贴板内容或个人签名数据。

PromptFinch 使用 [MIT License](../../LICENSE)。模型供应商账户及任何模型费用由各用户自行负责。
