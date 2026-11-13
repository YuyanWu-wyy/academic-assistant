<p align="center"><img src="assets/icon.png" width="128" alt="学术助手：论文、铅笔与星光"></p>

<h1 align="center">学术助手 · Academic Assistant</h1>
<p align="center">选中一段，润色一句；打开一篇，用中文读懂。</p>
<p align="center">macOS 原生应用 · DeepSeek API · MIT</p>
<p align="center"><a href="README.en.md">English</a> · <a href="Resources/使用说明.txt">完整使用说明</a> · <a href="docs/PRIVACY.md">数据与隐私</a></p>

为在 Overleaf 写作、在浏览器中阅读英文论文的中文研究者设计。选中文字后按快捷键，就能预览英文润色、翻译或中文解释；导入 PDF 后，可生成中文导读、结合原文连续问答，并保存阅读笔记。

这是直接调用 DeepSeek API 的独立 Swift 应用，不依赖 Codex、ChatGPT 或 DeepSeek Harness。需要自己的 DeepSeek API Key，API 用量由 DeepSeek 计费。

## 可以做什么

| 场景 | 功能 |
| --- | --- |
| 学术写作 | 英文润色；先看预览，再手动复制回 Overleaf |
| 阅读英文段落 | 中文解释、英译中、中译学术英文 |
| 快速读论文 | main idea、问题与缺口、related works、挑战与贡献、方法、实验、结果和局限 |
| 精读 | 选中段落提问、连续追问、点击 `[p. N]` 回到 PDF 原文 |
| 整理 | 每篇论文独立保存导读、问答和笔记，导出 Markdown |
| 长论文/专著 | 保留完整 PDF，按页码范围解读章节，按需提供页面图像 |

润色与翻译采用随应用打包的学术写作规则，强调保留技术含义、数字、确定性与术语一致性。检测到 LaTeX 命令、公式或引用键改变时，会提示核对并暂停复制。

## 安装

需要 **macOS 14 或更高版本**、Apple Command Line Tools（或 Xcode）及可连接 DeepSeek 的网络。构建没有第三方包依赖。当前以源码构建方式提供；本地签名的构建产物尚未经过 Apple 公证。

首次安装编译工具：在终端执行 `xcode-select --install`，按系统提示完成安装。

建议将项目放在本机代码目录，避免 iCloud 或网盘同步给应用包添加文件属性。

```bash
mkdir -p ~/Developer
cd ~/Developer
git clone https://github.com/YuyanWu-wyy/academic-assistant.git
cd academic-assistant
./scripts/build.sh
```

编译完成后，将 `build/学术助手.app` 拖到自己的“应用程序”文件夹，再双击打开。脚本只构建，不覆盖已有安装。

1. 点击 **DeepSeek 设置**，输入自己的 [API Key](https://platform.deepseek.com/api_keys)，点击“保存并验证连接”。密钥保存在 macOS 钥匙串中。
2. 若需要全局选文，点击 **启用选文快捷键**，按提示在“系统设置 → 隐私与安全性 → 辅助功能”中允许学术助手。
3. 保持助手运行，在 Overleaf 或浏览器 PDF 中选中文字，按下面的快捷键。也可直接复制粘贴文字、手动导入 PDF，无需辅助功能权限。

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| `Control + Option + Command + P` | 读取选文并润色英文 |
| `Control + Option + Command + R` | 读取前台浏览器的论文链接 |
| `Control + Option + Command + D` | 把选中段落带入细读问答 |
| `Command + Return` | 处理写作文字 / 发送当前问题 |

关闭窗口后仍在菜单栏运行；退出应用后全局快捷键停止。右键“服务”入口取决于当前应用是否支持 macOS 文本服务。

## 阅读一篇论文

1. 在浏览器打开公开 PDF，按 `⌃⌥⌘R`；也可在“论文阅读”中粘贴链接或导入本地 PDF。
2. 点击“生成中文导读”，左侧保留原文，右侧展示结构化中文解读。
3. 想细读时，在浏览器选中一段后按 `⌃⌥⌘D`，或在助手左侧 PDF 选中段落后点击“用选中段落提问”。
4. 在“我的笔记”记下理解，点击“导出阅读笔记”保存导读、笔记和完整问答。

**Related works 仅梳理当前论文自身讨论和引用的研究路线。** 应用没有联网文献检索，也不会独立读取所有被引论文。

需要学校或网站登录的论文，请在已登录的浏览器下载后导入；应用不读取浏览器登录 Cookie，也不绕过访问限制。

## 模型与长文

默认模型为 `deepseek-flash`，可切换至 `deepseek-v4-pro`。当前应用仅对 Flash 启用页面图像；模型可用性和计费以 [DeepSeek 官方文档](https://api-docs.deepseek.com/quick_start/pricing/) 为准。

- 可导入最多 1,000 页、50 MB 的 PDF，提取文字上限 800 万字符。
- 单次解读最多 200 万字符；实际可处理长度还受模型上下文与服务端限制影响。
- “解读范围”留空为全文，也可填写 `20-35` 或 `5,12-18`，使用 PDF 物理页码。
- 超过 80 页的论文默认只发送文字；开启图表时每次最多提供 80 页图像。
- 每轮问题带入本轮范围的原文、已有导读和最近 16 轮问答。完整历史保存在本机，导出不受 16 轮限制。

## 数据与边界

API Key 只保存在本机钥匙串。导入的 PDF、提取文字、导读、问答和笔记保存在 `~/Library/Application Support/学术助手/Papers`。点击润色、导读或问答时，对应文字、对话和已启用的页面图像会发送至 DeepSeek；这不是离线模型。详见[数据说明](docs/PRIVACY.md)。

模型可能误读表格、公式、数值或引用。页码链接便于核对，不代表结论已验证。LaTeX 检查也不是编译验证。使用前请核对原文。

浏览器选文与地址识别依赖辅助功能支持。Chrome 上已做过人工验证；不同浏览器、PDF 阅读器和 Overleaf 编辑模式仍可能需要复制粘贴作为替代。

## 开发与自定义

```bash
./scripts/test.sh              # 离线测试，不读取 API Key，不调用真实 API
./scripts/build.sh --universal # 同时构建 Apple Silicon 与 Intel
```

测试会生成合成 PDF，检查 LaTeX 保护、请求格式、论文隔离、持久化、页码范围、长文导入和 Markdown 输出等。GitHub Actions 在 macOS 上运行测试并构建两个架构。构建成功不等于不同系统与硬件上都完成了人工验证。

写作规则在 `Resources/academic-writing-editor.txt`，阅读规则在 `Resources/paper-reading-rules.txt`。如本机存在 `~/.codex/skills/academic-writing-editor/SKILL.md` 或 `~/.codex/skills/summarize-research-paper/SKILL.md`，应用会优先读取对应规则；无需安装 Codex 即可使用内置版本。规则内容会随相应请求发送给模型，请勿在规则中放入密钥。

参见[项目结构](docs/DEVELOPMENT.md)、[贡献指南](CONTRIBUTING.md)和[更新记录](CHANGELOG.md)。

## 许可证

[MIT](LICENSE) · Copyright © 2026 Yuyan Wu。应用图标为 AI 生成。DeepSeek 服务不属于本项目；使用需遵循其平台条款。
