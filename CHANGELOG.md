# Changelog

## 1.7.0 — 2026-11-13

- Add a shared model setting for ChatGPT subscription access through the official local Codex CLI, covering writing, paper reading and library Q&A.
- Check subscription login without reading credentials; refuse API-key login and never automatically fall back to a paid API.
- Bound text input and process output, stop cancelled/timed-out requests, and validate structured completions. Subscription mode is text-only.
- Preserve compact local retrieval and document subscription limits, official client requirements and privacy boundaries.

## 1.6.0 — 2026-11-13

- Retrieve papers locally without uploading the entire catalog; library size no longer scales model requests or context limits.
- Default to compact evidence, with explicit detailed mode, bounded history/output and no automatic paid retries.
- Add zero-call local search and portable Markdown copy/export for use with other AI tools.
- Keep stored relations and existing reading data intact; add large-catalog and budget regression tests.

## 1.5.0 — 2026-11-13

- Find remembered papers through natural-language catalog retrieval, then ask follow-up questions or compare papers using existing overviews and notes.
- Show clickable paper sources and locally bound supporting excerpts; reject mismatched source identifiers. Constrain structured API output and allow one bounded format/source correction.
- Save typed, evidence-backed content relations locally, invalidate changed sources and exclude archived papers.
- Add explicit single-paper scope, cancellation and session-only conversation history without additional PDF storage.
- Add offline integration coverage for retrieval, follow-ups, evidence validation and graph persistence.

## 1.4.0 — 2026-11-13

- Simplify the reader toolbar and remove introductory slogans.
- Support native full screen (Control–Command–F) and persistent draggable reading/writing dividers.

- Automatically index full papers imported or opened through the assistant.
- Save lightweight title/link/tag/brief cards without copying PDFs or full text.
- Search bilingual topic keywords and explore a clickable shared-topic graph.
- Bookmark browser papers without downloads or API calls; edit, archive, restore and export cards.
- Preserve manual card edits during automatic synchronization and add offline index regression tests.

## 1.3.0 — 2026-11-13

First public source distribution.

- Standalone source and resource layout; build no longer depends on a personal installed application.
- Bundled help document and generic installation paths.
- Offline tests, synthetic PDF fixture generation and macOS CI.
- Optional universal build for Apple Silicon and Intel.
- Chinese and English documentation, privacy notes and MIT license.

Includes the existing writing workflow (polish, explain, translate and LaTeX checks), Chinese PDF overview and Q&A, per-paper notes, Markdown export, page ranges and long-document support.
