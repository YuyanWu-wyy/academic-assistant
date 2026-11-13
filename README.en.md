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

This is an independent Swift application that calls the DeepSeek API directly. Codex, ChatGPT and DeepSeek Harness are not required. Bring your own DeepSeek API key; API usage is billed by DeepSeek.

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

In **DeepSeek 设置**, enter your own [API key](https://platform.deepseek.com/api_keys) and validate the connection. Enable Accessibility for global selection shortcuts, or use manual copy/paste and PDF import without that permission.

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

The **主题图谱** view connects papers by shared tags, not by citations or verified scientific relationships. It shows up to eight neighbors of the selected paper. No browser-history scanning is performed. The existing full-paper reading workspace continues to retain its PDFs separately.

## Scope and privacy

Keys stay in Keychain. PDFs, extracted text, summaries, conversations and notes stay in `~/Library/Application Support/学术助手/Papers` until a requested model operation sends its context to DeepSeek. Enabled page images are also sent. API calls go to `https://api.deepseek.com`; this is not an offline model.

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

Use **论文索引 → 问论文库** to find a remembered paper using a natural-language description, follow up on its content, or compare methods and experiments. Retrieval scans every active card in batches and then uses existing overviews and personal notes from up to seven candidates. Answers link to cards and expose short evidence quotes; **问这篇** limits a conversation to one paper.

The relationship graph can infer shared problems, similar or different methods, and result comparisons. Both papers must have matching evidence excerpts. Relations persist locally with source fingerprints; source edits invalidate stale edges. These are AI interpretations of existing material, not verified citations or causal claims. With only a title, detailed questions may remain unanswered.

Questions use DeepSeek API calls. Catalog retrieval sends title/tag/brief metadata; generation sends selected overview/note excerpts (up to 20,000 characters per paper), without PDF text or images. The card’s source URL or local path is omitted; text written in the selected notes is included. Short relations live in `PaperIndex/relations.json`; conversation history lasts only for the app session. No additional PDFs are stored.
