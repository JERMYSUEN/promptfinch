<p align="center"><img src="../assets/logo.svg" alt="PromptFinch logo" width="220" height="54"></p>

[English](../../README.md) · **简体中文（zh-CN）** · [繁體中文（zh-TW）](README.zh-TW.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Українська](README.uk.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [हिन्दी](README.hi.md) · [বাংলা](README.bn.md) · [Bahasa Indonesia](README.id.md) · [Tiếng Việt](README.vi.md) · [ไทย](README.th.md) · [தமிழ்](README.ta.md) · [తెలుగు](README.te.md) · [मराठी](README.mr.md) · [العربية](README.ar.md) · [اردو](README.ur.md) · [فارسی](README.fa.md) · [Kiswahili](README.sw.md) · [ਪੰਜਾਬੀ](README.pa.md) · [Filipino](README.fil.md)

# PromptFinch

**选择。优化。粘贴。**

PromptFinch 是适用于写作、编程、研究、摘要与规划的 Prompt 编辑与优化工具。将以你惯用语言写下的粗略需求，整理成让目标模型更容易执行的指令。优化器会要求模型理清目标、输入与限制，按需安排步骤、处理关键信息缺口，并从原始需求推导检查方式。已经清楚的需求应保持精简；新增结构应有助于任务，不应擅自添加新要求。

**macOS App** 可作为手动工作台或文本选择助手：在兼容应用中选中文本、点击右键，在辅助操作菜单选择 **转为英文 Prompt**，再于附近面板查看结果。仅点击右键不会将文本发送给模型。另有使用相同后端的**浏览器工作台与 HTTP API**。

Windows／Linux 桌面预览版新增相同工作台，以及 Windows UI Automation／Linux X11 的实验性右键附加菜单。Wayland 可使用手动输入及剪贴板导入，没有全局右键菜单。详见[桌面版支持指南（英文）](../desktop.md)。

PromptFinch 会编辑指令，不会执行指令描述的任务。它以保留需求、指定的答案语言与固定字符串为设计目标。真正优化需要自行配置模型 API；没有密钥时，可用明确标注的 mock 模式试用操作流程，但不会翻译或优化文本。

## 演示动图

![在 Codex 桌面输入框使用 PromptFinch，使用合成示例文本](../media/demo-selection.gif)

15 秒 Codex 桌面操作示意：选中粗略的 CSV 错误修复需求、点击右键，在 PromptFinch 辅助操作菜单选择转换，查看补上项目检查、聚焦修复与需求验证步骤的英文 Prompt，再复制粘贴回 Codex。辅助菜单由 PromptFinch 提供，并非 Codex 内置功能。界面、示例内容与优化结果均为合成，未使用个人输入；此动图并非屏幕录制或实时模型请求。

## 文档语言

最上方链接可切换 README 页面。英文是原始版本；简体中文（zh-CN）与繁体中文（zh-TW）包含完整参考内容。其他 26 个版本提供翻译介绍，并链接至英文配置指引。这些链接切换文档，不会更改 App 语言。

macOS App 的**设置 → 界面语言**可选繁体中文（默认）、英文、日文与韩文。浏览器界面仍为繁体中文。新生成的优化说明与假设会使用原生界面语言；浏览器另有说明语言选项。切换语言不会重写现有结果。

macOS App 生成英文 Prompt 指令。浏览器默认生成英文指令，也提供繁体中文选项。API 使用 `promptLanguage: "en"` 获取英文指令；省略时保留 `zh-Hant` 默认值。最终答案语言是原始 Prompt 中的另一项需求。工具接受 Unicode 输入，但文档翻译不代表每种语言的模型质量均已验证。

[文档索引](../README.md) · [故障排查](../troubleshooting.md) · [完整 API 参考](../api.md)

## 功能

- 接受原始 Prompt、任务类型，以及可选的下游目标模型名称。
- 要求模型在保留任务意图、限制与固定字符串的前提下，改善需求清晰度与执行指引，而非只转换语言。
- 生成可复制的 Prompt，并将优化说明与假设分开呈现；复制及贴回只会使用 Prompt 字段。
- macOS App 提供手动输入、文本选择操作、结果面板、模型配置、四种界面语言及可选的贴回功能。
- 处理空白输入、长度限制、加载、取消与易懂的错误信息。
- 可在明确标注的 mock 模式下无需密钥检查流程，或由 Node.js 后端调用已配置的 OpenAI 兼容模型。

任务类型包括通用、写作、分析、编程、摘要与营销；研究与规划可选分析或通用。可选**目标模型**只作为编辑 Prompt 的提示，不会切换后端生成模型；后端模型由 `LLM_MODEL` 配置。

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

获取源码后，选择浏览器演示或 macOS App：

```sh
git clone https://github.com/JERMYSUEN/promptfinch.git
cd promptfinch
```

[v1.3.0 桌面预览版](https://github.com/JERMYSUEN/promptfinch/releases/tag/v1.3.0) 提供内含运行时的 Windows x64 与 Linux x64 安装包；支持范围、配置及验证说明见[发行指南（英文）](../releases/v1.3.0.md)。

[v1.1.0 发行版](https://github.com/JERMYSUEN/promptfinch/releases/tag/v1.1.0) 提供 `PromptFinch-1.1.0-macos-arm64.zip`、`PromptFinch-source-v1.1.0.zip` 及 `SHA256SUMS`。App 下载适用于 Apple Silicon，采用 ad-hoc 签名、未经过公证；需另外安装 Node.js 22+。解压后将 App 移至应用程序文件夹。设置及验证范围见[发行说明](../releases/v1.1.0.md)，也可从此源码工作目录自行构建。[变更记录](../../CHANGELOG.md)区分之前的快照；目前没有自动更新或 Intel／Universal Binary 下载。

### 浏览器演示（不需 API 密钥）

```sh
# Create a local configuration only if one does not already exist.
cp -n .env.example .env
npm start
```

打开 [http://127.0.0.1:3000](http://127.0.0.1:3000)。若 `.env` 已存在，请先检查内容，并配置 `OPTIMIZER_MODE=mock` 进行本地演示，不要覆盖原文件。运行服务不需要 `npm install`。

**Mock 输出不会翻译，也不会进行语义优化。**它是用来检查输入、加载、结果显示和复制流程的模板，不会调用模型或将 Prompt 传送给供应商。

浏览器的 Prompt 语言菜单控制指令语言。原始需求中明确指定的答案语言仍会保留。

### 构建并安装 macOS App

```sh
xcode-select --install  # Skip if Command Line Tools are already installed.
npm run setup:signing:mac
npm run build:mac
npm run install:mac
```

构建结果为 `build/PromptFinch.app`。安装程序会将 App 放入用户的 `~/Applications` 并打开。无需另外启动浏览器服务器：App 会在 `http://127.0.0.1:3210` 启动自己的后端。

安装程序也会处理旧 App 名称的迁移；详见[更名说明](../branding.md)。

`setup:signing:mac` 是每台电脑各自执行一次的本地签名身份配置。私密签名密钥会存放在登录钥匙串；macOS 可能要求确认访问。这有助于在本地重建时保持辅助功能权限身份稳定。这不是 Developer ID 签名或公证，且不得发布签名密钥。若现有签名配置无效，构建会停止，不会暗中取代身份。

若未选择模型配置，App 会使用 mock 模式。在 App 的「设置」中建立或选择模型配置文件、填入供应商配置并重新加载配置，也可在此选择界面语言。若 App 找不到 Node，请在「设置」中选择其可执行文件。

也可在安装时指定现有配置：

```sh
npm run install:mac -- --config .env
```

更多 macOS 配置请参阅目前以繁体中文编写的 [macOS 指南](../macos.md)。

## Windows 与 Linux 桌面预览版

桌面版内含运行时，直接在主进程使用共用优化器，不启动本地 HTTP 服务器；macOS 仍使用现有 Swift App。从源码启动需要 Node.js 22.12+：

```sh
npm ci
node scripts/build-desktop-helpers.cjs
npm run desktop
```

Windows x64 上可构建安装程序及 ZIP；Linux x64 上可构建 AppImage 及 tar.gz。运行 `npm run build:desktop`，结果位于 `desktop-dist/<version>/`。已打包的桌面版不需另装 Node。Linux 构建依赖与启动方式见[桌面版指南（英文）](../desktop.md)。

在兼容软件中选取文字后右键，再点击附加菜单的“转为英文 Prompt”才会生成。捕获文字十秒后失效，不自动粘贴回原处或提交。Windows 支持取决于来源软件的 UI Automation。原生标准文本控件已通过验证；Windows 上的 Chromium／Electron 选区，包括 Codex 与 Claude，仍未验证，无法捕获时请复制后导入剪贴板；Linux X11 读取选区缓冲区，无法证明点击位于高亮范围。Wayland 没有此全局监听功能。

取字不可用时，可自行复制后点击“读取剪贴板”。`Ctrl+Alt+P` 导入选取文字，`Ctrl+Alt+Shift+P` 导入剪贴板；快捷键不会生成。设置中会显示右键监听与快捷键状态。界面提供繁体中文、英文、日文与韩文；创建模型配置模板、填入自己的密钥，再选取文件加载。新安装默认为演示模式；偏好设置只记录语言及配置文件路径。

## 模型配置

实时生成使用 **OpenAI 兼容的 Chat Completions** 端点。后端会在 `LLM_BASE_URL` 后附加 `/chat/completions`。用户需自行提供模型供应商账户并承担相关费用。

PromptFinch 不包含或下载语言模型。`LLM_MODEL` 选择通过 API 编辑 Prompt 的模型；可选的目标模型字段只描述你打算粘贴结果的模型。供应商模型名称与账户权限必须符合该供应商当前的 API 配置。

新配置可参考 [.env.deepseek.example](../../.env.deepseek.example)：

```dotenv
OPTIMIZER_MODE=live
LLM_API_KEY=YOUR_MODEL_API_KEY
LLM_BASE_URL=https://api.deepseek.com
LLM_MODEL=deepseek-flash
LLM_JSON_MODE=true
LLM_THINKING_MODE=disabled
LLM_QUALITY_REVIEW=false
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
| `LLM_QUALITY_REVIEW` | `false` | 可选的同供应商、同模型独立复核；须明确设为 `true` 才启用，未设置或 `false` 仅执行编辑。 |
| `LLM_TIMEOUT_MS` | `45000` | 编辑、复核、修订与格式重试共用的上游总时间预算；整数范围 10 至 180000 毫秒。 |
| `HOST` | `127.0.0.1` | 独立服务器的监听地址。 |
| `PORT` | `3000` | 独立服务器端口。 |
| `ALLOWED_HOSTS` | 空白 | 反向代理的可选主机白名单，以逗号分隔，例如 `prompts.example.com,prompts.example.com:8443`。不接受通配符或完整 URL。 |

Mac App 无论所选配置文件中的值为何，都会将 `HOST` 与 `PORT` 设为 `127.0.0.1:3210`，并清空 `ALLOWED_HOSTS`。独立浏览器服务器可使用另一个端口。服务器默认只接受本机名称与非通配监听主机在实际端口上的请求；监听 `0.0.0.0` 或 `::` 不会放行任意 Host。远程域名与代理端口必须明确列入白名单，不自动信任转发主机标头。

实时配置或供应商调用失败时会报告错误，不会默默改用 mock 结果。`/api/config` 的 `ready` 表示配置已填妥，不代表已成功连上上游模型。

实时模式默认只执行编辑，一般调用供应商一次，需要格式重试时最多两次。模型复核为可选功能，`LLM_QUALITY_REVIEW` 未设置或为 `false` 时不启用；明确设为 `true` 后，才使用配置的同一模型，在另一个请求上下文中比对候选 Prompt 与原始要求。启用复核后，成功流程通常调用两次；候选内容被否决时，最多修订一次后再复核。编辑、复核、修订与格式重试合计最多四次调用，并共用同一超时预算。已启用的复核失败会报告错误，不会交付被否决的内容或改用 mock。这会增加付费 token 用量与等待时间；当前证据尚不足以支持默认启用。Mock 仍不调用模型。模型批准不代表正确性或下游效果已获保证，重要要求仍须自行比对。

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
- 韩语谚文、俄语西里尔字母、由右至左文本、组合附加符号、连接符、表情符号及混合文本皆可输入，不会对文本进行规范化或按字母系统过滤。浏览器输入栏会自动调整文本方向。文档涵盖的语言与四种 macOS 界面语言是不同的范围。
- 两种指令语言都会保留原文另外要求的下游答案语言。模型必须保留明确要求、条件与否定的适用范围、固定字符串、变量、代码与 URL。两种模式都会以有限规则修复引号或代码中仅因 NFC 规范化而被更改、且可明确判定的固定字符串。若字符串被省略、翻译或改为语义相近但拼法不同，后端无法重建；重要字符串请自行检查。
- [多语验证记录](../multilingual-verification.md)记录了传输检查，以及使用 `deepseek-flash` 进行的 18 种语言、24 个实时模型合成案例，包含韩语／俄语的简短、中等和较长案例。其中也记录了一项不够精确的日文优化说明，以及尚未测试的语言与宿主 App。这些样本不保证新输入或其他模型的翻译质量。
- [跨语言对照验证](../multilingual-parity-verification.md) 对 29 个 locale（28 种语言，中文分繁简）使用同一组需求，另测答案语言推断、混合语言、长引文与条件范围，分别记录自动检查、模型输出复核与剩余限制。

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

成功时返回 `prompt`、`improvements`、`assumptions`、`mode`、`generationModel` 与 `promptLanguage`。原文与结果对照会保留生成当时的原文，逐行标示文字改动；这不等于语义正确性验证。重用结果时只复制 `prompt`；优化说明与假设是独立的审阅备注。`notesLanguage` 支持 `zh-TW`（API 默认）、`en`、`ja`、`ko`，与 Prompt 指令及原文指定的答案语言分开。

英文与繁体中文模式现在都直接返回完整、可使用的 `prompt`；繁体中文结果不再加上原始需求包装。曾解析该包装的客户端，应改为另外保留提交的原文，并完整使用返回 Prompt。`improvements` 可有 0–4 项，需求已清楚时可以没有额外编辑，工作台会另行显示提示。成功的实时响应另有 `modelReview: {status: "approved" | "disabled", revisionCount: 0 | 1}`，只表示实际经过的复核流程，不是质量认证。API 版本仍为 2，客户端应接受新增响应字段与空白说明数组。

API 会验证输入与模型响应结构、限制同时进行的优化请求，并报告配置、供应商、格式错误和超时错误。取消操作会关闭上游请求；供应商端的处理和计费仍由供应商控制。

[完整 API 参考](../api.md)提供响应示例、配置就绪状态、限制、状态码与取消行为。`LLM_TIMEOUT_MS` 是编辑、复核、修订与格式重试共用的上游总时间预算；下一次调用不会重新计时。

## macOS 操作流程

1. 打开 App 手动工作台，输入或贴上需求，选择任务与可选目标模型，再生成英文 Prompt。
2. 检视 Prompt 与分开显示的备注。可复制 Prompt，或清空工作区以移除输入与结果。
3. 使用文本选择操作时，依提示在系统设置中启用「辅助功能」。在兼容的输入框中选择文本并按右键，再于辅助菜单选 **转为英文 Prompt**（按钮文字会随 App 语言切换）；结果会显示在附近。宿主 App 原有的上下文菜单仍可使用。按取消、点击其他位置、键盘输入、切换 App 或等待 12 秒，都会关闭操作提示而不生成结果。只有在明确选择该操作后，助手才会再次检查选择内容。也可使用选择按钮。部分 Electron App 可能显示启用提示：等待约两秒、重新选择文本后再试。
4. 其他入口包括默认的 Option-Command-P 快捷键、支持的 macOS 服务，以及明确的剪贴板操作。宿主 App 必须提供可用的文本选择功能，因此不保证所有 App 都兼容。
5. 可选自动贴回需要可信的非空选择范围，并在发送粘贴操作前重新核对来源 App、焦点字段与选中文本。无法确认位置时，结果会复制供手动使用；只有文本信息的选择仍可转换，再自行粘贴。状态只报告已发送粘贴操作，请检查来源文本，因为来源软件可能忽略模拟按键。剪贴板恢复结果会在回调完成后显示。备份不完整、暂存或立即恢复失败时，会停止贴回且不自动复制，保留结果供自行复制。面板也提供复制及手动贴回。贴回不会发送聊天消息，并可在设置中停用。Mock 结果不会贴回。

首次建立原生偏好设置时，选择按钮、右键菜单与自动贴回默认开启。若要在替换可编辑原文前先查看结果，请在设置关闭自动贴回；已识别的终端来源不受此偏好影响，仍只复制结果。

关闭工作区窗口后，选择助手仍会在菜单栏运作；结束 App 则会停止由它启动的后端。辅助菜单是独立且不会抢走焦点的操作面板，不会插入宿主 App 原有的上下文菜单。详见[右键操作验证](../context-menu-verification.md)。

### 仅更新原生后端

更改可信任的后端或浏览器代码后，可只更新已安装 App 的外部后端，不必重建已签名的原生可执行文件：

```sh
npm run update:mac-backend
```

更新程序会先暂存并以 mock HTTP 检查候选版本，正常关闭 App、检查端口，再切换后端版本并重新启动 App。若启动失败会尝试恢复。它不会更改所选模型配置，也不会终止无关的端口监听进程。安装重新构建的 App 会保留现有外部后端，不会自动选用较新的内附后端文件。要采用已安装版本附带的规则，请打开**设置 → 使用此 App 隨附後端**（繁体中文界面；英文为 **Use this app’s bundled backend**）。这是明确的本地操作，会暂存、验证并启动该 App 随附的后端；失败时会尝试恢复原先版本。模型配置、Node 路径与偏好会保留，不下载 GitHub 文件，也不调用模型。切换前请先保存未完成的工作区文本。

现有安装若同时更新原生与后端代码，请先更新可信任的源码工作目录，再运行：

```sh
git pull --ff-only
npm run build:mac
npm run install:mac
npm run update:mac-backend
```

若只更改后端，更新源码后运行 `update:mac-backend` 即可。请保留此电脑已配置的稳定签名身份；新电脑须先完成快速开始中的一次性签名配置。更新程序是手动本地命令，不是自动下载服务。

## Terminal 与 CLI 文本选择

在 macOS Terminal 中使用 Claude Code 或 Codex CLI 时，选中画面上的文本、点击右键，再从辅助菜单选择“转为英文 Prompt”。终端须提供可读取的选中文本；仅点击右键不会生成或发送内容。

已识别的终端来源采用**仅复制结果**的流程，即使其他输入框已启用自动粘贴也一样。检查结果后，手动粘贴到指定的 CLI 输入区，再自行发送。终端画面的高亮文本不等于可编辑的输入范围，因此不会直接替换高亮内容或向终端发送粘贴操作。

[Terminal 指南](../terminal.md) 提供配置、替代入口与验证范围。用户已确认 Apple Terminal 的辅助菜单与英文生成可用；Claude Code／Codex CLI 的单独配置，以及剪贴板、手动粘贴与取消等剩余操作仍需手动验收。

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
- 输入、结果与说明在内存中处理，不使用数据库或 Prompt 历史记录。原生偏好设置（包括任务类型与目标模型提示）及配置路径会存储在本地。原生诊断记录状态元数据与长度，不记录 Prompt 内容；分享日志前仍须检查 App／进程元数据。
- 实时模式会将请求与编辑指示传送至已配置的模型供应商；启用模型复核时，也会传送原始要求与候选内容。这些调用都受同一供应商的数据保留政策约束。Mock 不会调用模型。
- 浏览器界面不使用 Cookie、浏览器存储、分析工具或远程字体；重新加载会清空工作区。原生工作区可透过清除操作或结束内存会话清空。
- 启用文本选择操作后，App 会监听鼠标事件并读取可访问的文本选择内容。若安全的可编辑字段提供非空选择范围但没有选择文本属性，助手可能暂时读取字段值。超过 65,536 个 UTF-16 code unit 的值会被拒绝；只会返回选择范围，也不会记录字段内容。
- 复制、贴回及备用复制会使用系统剪贴板。恢复操作会先确认用户没有复制新内容。清空工作区不会删除已复制到系统剪贴板的文本。

这是供个人本地使用的工具，没有账户验证或多用户隔离。独立服务器支持部署配置，但公开部署需要自行配置 HTTPS 与访问控制。远程部署及 Docker 运行尚未验证。

## 验证结果与限制

[当前的 Prompt 质量验证记录](../prompt-quality-verification.md)说明本次编辑与复核逻辑、受控检查及尚未完成的实时模型评估。以下先前记录保留各自的历史范围，不代表当前版本或所有语义案例均已通过。

[优化效果验证记录](../optimization-value-verification.md)定义了 8 个合成案例，检查翻译之外的任务指引，以及清楚需求是否保持精简。最初检查遇到供应商超时与服务错误；后来的[改善验证记录](../improvement-verification.md)记录已取得的实时样本、机械检查与单独复核的语义问题。示意结果不代表已证明模型或下游任务表现改善。

[先前的可靠性验证](../reliability-verification.md)于 2026-10-09 通过 JavaScript 语法检查、55 项 Node 测试、190 项原生检查、10 项 Chrome 流程测试，以及 macOS 构建／签名检查。2026-10-11 的 Terminal 变更通过语法检查、55 项 Node 测试、233 项原生检查、README／文档链接检查，以及 macOS 构建／签名检查，并完成新版安装；这次原生变更未重跑浏览器流程测试。自动化测试使用 mock 或受控供应商，不代表真实模型的输出质量。

用户先前确认辅助菜单出现时不会自动生成，且明确点击一次即可获取英文结果。此版本在 Codex／Claude 中使用实体鼠标操作，以及完整的复制／贴回／取消行为仍需验收。[文本选择验证](../context-menu-verification.md)与[多语样本审阅](../multilingual-verification.md)各自记录不同的验证范围。

目前限制包括宿主 App 的文本选择支持、没有 OCR、不能自定义全局快捷键、未内含 Node、没有自动更新，以及没有现成且经过公证的安装程序或 Universal Binary 发布版。Intel／最低 macOS 版本硬件、实体移动设备、Docker 与远程部署仍未验证。实际语义质量仍需人工复核；检查与剩余限制见[当前的 Prompt 质量验证](../prompt-quality-verification.md)。

## 开发

```sh
npm ci
npm run check
npm run check:docs
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

在具备 Node.js 22+ 与 Xcode Command Line Tools 的 macOS 上运行 `npm run package:mac`，可生成公开用 Apple Silicon App ZIP 与源码 ZIP。它只复制明确列出的公开文件，以 ad-hoc 签名构建，不读取真实 `.env` 或个人签名配置。发行 manifest 记录相对输入路径与 SHA-256；`SHA256SUMS` 列出下载文件校验码。这项打包不会公证 App 或发布到 GitHub。只需源码包时可运行 `npm run package:source`。

`npm run dev` 会以 Node watch 模式运行独立服务器。`npm run check:docs` 会检查 README 导览、翻译结构与变更记录顺序，不会认证翻译准确度或模型质量。API 测试使用本地假模型服务；原生测试使用合成目标与具名测试剪贴板。[GitHub 工作流程](../../.github/workflows/check.yml)会运行 JavaScript／文档检查、Node 测试与 macOS 原生检查、公开封装与解压后验证，不会发布发行文件。浏览器测试目前在本地运行；特定提交的结果请查看 [GitHub Actions](https://github.com/JERMYSUEN/promptfinch/actions)。

## 贡献与授权

开发规范请参阅 [CONTRIBUTING.md](../../CONTRIBUTING.md)。欢迎修正翻译，以及使用可分享合成输入的可复现的问题报告。请勿在贡献中放入 API 密钥、本地环境文件、私人 Prompt、剪贴板内容或个人签名数据。

PromptFinch 使用 [MIT License](../../LICENSE)。模型供应商账户及任何模型费用由各用户自行负责。
