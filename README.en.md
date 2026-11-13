<p align="center"><img src="assets/icon.png" width="128" alt="Academic Assistant icon"></p>

# Academic Assistant · 学术助手

A native macOS companion for academic writing and reading, with a Chinese interface. Polish selected English, translate between English and Chinese, or read a paper with structured Chinese summaries and passage-level Q&A.

[中文说明](README.md) · [MIT License](LICENSE)

## Features

- Global shortcuts for selected text in Overleaf and browser PDFs.
- Preview before copying; checks for changes to LaTeX commands, math and citation keys.
- PDF reading: main idea, problem, related work, challenges, contributions, methods, experiments, results and limitations.
- Clickable physical PDF page references, chapter ranges and optional page images.
- Per-paper summaries, conversations and notes; export the complete reading record to Markdown.
- A lightweight paper index: search titles, briefs and tags, and browse connections through shared topics without storing PDFs in the index.
- API keys stored in macOS Keychain. No third-party runtime dependencies.

Choose ChatGPT subscription access through the local official Codex CLI, or the DeepSeek API. Writing, reading and library Q&A share this selection. Subscription mode never reads the DeepSeek key and never falls back to paid API calls.

## Build and run

Requires macOS 14+, Apple Command Line Tools or Xcode, and network access for model calls. Run `xcode-select --install` first if you do not have the developer tools.

Build in a local development folder outside iCloud or other sync services.

```bash
mkdir -p ~/Developer
cd ~/Developer
git clone https://github.com/YuyanWu-wyy/academic-assistant.git
cd academic-assistant
./scripts/build.sh
```

Move `build/学术助手.app` into your Applications folder and open it. Builds use ad-hoc signing and are not Apple-notarized. The script does not install or replace an existing application.

In **模型设置**, select **ChatGPT 订阅（经 Codex）** after signing into the official local Codex client with ChatGPT, or select DeepSeek and enter your own [API key](https://platform.deepseek.com/api_keys). Enable Accessibility for global selection shortcuts, or use manual copy/paste and PDF import without that permission.

| Shortcut | Action |
| --- | --- |
| Control + Option + Command + P | Polish selected English |
| Control + Option + Command + R | Import the browser's paper URL |
| Control + Option + Command + D | Open Q&A with the selected passage |
| Command + Return | Process text / send a question |

Import a public PDF or local file, then choose **生成中文导读**. For papers behind a login, download them through your authorized browser session and import the file. Browser cookies are not reused.

## Paper index

Open **论文索引** from the writing or reading window. Existing full-paper reading records are indexed automatically, as are papers subsequently imported or opened through the assistant. Cards contain only a title, source link, tags, a brief (up to 600 characters), and identity/timestamp metadata. The index never copies PDFs, full text, notes or conversations.

Use **收藏浏览器论文** or **手动添加** to bookmark a title and URL without downloading a PDF or making an API call. Search by title, brief or topic keywords, edit cards, archive/restore them, and export Markdown. Automatic tags use local keyword aliases; briefs are extracted from existing overviews. Manual edits are preserved during subsequent synchronization.

The **关联图谱** view initially shows up to eight shared-tag neighbors. **分析这篇的关联** generates typed problem/method/result associations with inspectable evidence, as described below. These are not citations or independently verified scientific relationships. No browser-history scanning is performed. The existing full-paper reading workspace continues to retain its PDFs separately.

## Scope and privacy

Keys stay in Keychain. PDFs, extracted text, summaries, conversations and notes stay in `~/Library/Application Support/学术助手/Papers` until a requested model operation sends its context to the selected service. Enabled page images are also sent. API calls go to `https://api.deepseek.com`; this is not an offline model.

Related work is organized from the current paper's discussion and citations, without independent literature search. Model output can misread tables, equations, numbers or references; always verify important claims against the source. Page checks validate page bounds, not factual correctness.

Import limits: 1,000 pages / 50 MB / 8 million extracted characters; analysis: 2 million characters per request, also subject to the model's context limit. Page images: up to 80 pages per request. Long papers default to text only. The active conversation includes up to 16 recent turns; exports retain the complete history.

Default: `deepseek-flash`; optional: `deepseek-v4-pro`. The app enables page images only for Flash. See [DeepSeek's documentation](https://api-docs.deepseek.com/quick_start/pricing/) for availability and pricing.

## Development

```bash
./scripts/test.sh
./scripts/build.sh --universal
```

Tests use mocked model responses and synthetic PDFs, with no API key or live API calls. The universal build targets Apple Silicon and Intel; cross-compilation is not a substitute for testing on both hardware families.

Bundled writing and reading instructions are in `Resources/`. Optional personal overrides are read from `~/.codex/skills/academic-writing-editor/SKILL.md` and `~/.codex/skills/summarize-research-paper/SKILL.md`. These instructions are sent to the model with requests, so do not put secrets in them.

See [development notes](docs/DEVELOPMENT.md) and [contribution guidelines](CONTRIBUTING.md). The application icon is AI-generated. The project is licensed under MIT; DeepSeek is a separate service governed by its own terms.

### Window layout

Use the green window button or Control–Command–F for full screen. Drag the center divider to adjust the reading and writing panes; their widths are remembered. The compact toolbar keeps secondary guidance in tooltips.

### Ask your paper library

Use **论文索引 → 问论文库** to find remembered papers, ask follow-ups, or compare methods. Retrieval runs locally over titles, tags, briefs and common bilingual keyword aliases. **本地找论文** makes no model call. Vague descriptions may need more keywords or an improved card. **问这篇** scopes the conversation to one paper.

The default compact mode selects at most 3 papers and 2,000 excerpt characters per paper. Explicit detailed mode expands this to 6 papers and 5,000 characters each. Requests also include fixed rules, the question and up to 2,000 characters of recent conversation context. Character limits are not exact token counts. DeepSeek output caps are 2,400 and 6,000 tokens respectively; Codex uses these as length targets, not hard output caps. Each answer makes at most one request to the selected service, with no automatic paid retry; no matches means no Keychain read or API request. Library growth does not increase these per-request limits.

**复制提问材料 / 导出材料** creates portable Markdown locally, with the question, bounded context and source labels for Claude Code, Codex, ChatGPT or another tool. Nothing is sent automatically, and no third-party subscription or credentials are reused. PDF text, images and card source URLs/local paths are excluded; selected personal notes are included.

**关联图谱 → 分析这篇的关联** uses compact mode to generate problem/method/result relationships with evidence from both papers. These AI interpretations are not verified citation edges. Stored relations can be browsed without API calls; source changes invalidate stale relationships. Without content relations, the graph falls back to shared tags. Use detailed mode in library Q&A when you want broader comparisons.

Relations and short evidence are saved locally in `PaperIndex/relations.json`; library conversations last only for the app session. No extra PDF copies, cloud library or embeddings are created. The separate full-paper reader retains its existing explicit page/text/image scope and can use substantially more tokens.

## ChatGPT subscription access

The assistant runs the official local `codex exec` client and returns the answer inside its own window. Follow [official Codex sign-in](https://learn.chatgpt.com/docs/auth); API-key authentication is refused. Login checks make no inference request. Use a recent official CLI supporting `--ignore-user-config`, `--ephemeral` and structured output (tested: 0.167.0-alpha.4.1).

This uses Codex subscription allowances, not unlimited usage or shared web-chat history. Quota/auth/network failures stop the request without automatic API fallback. Existing installations keep their provider until explicitly changed in settings. The subscription path is text-only, with a 160,000-character request limit; oversize requests fail without truncation. Manually select DeepSeek for page images. Codex has fixed instruction overhead in addition to bounded paper context. Claude integration remains manual copy/export.
