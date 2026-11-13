# Development

The application uses Swift in Swift 5 language mode and macOS system frameworks only. The deployment target is macOS 14. The repository contains all resources needed to build; it does not copy files from an installed application.

| Path | Responsibility |
| --- | --- |
| `Sources/App.swift` | App lifecycle, writing window, settings, menu bar and global shortcuts |
| `Sources/Core.swift` | Writing prompts, LaTeX protection, DeepSeek HTTP client and response validation |
| `Sources/Keychain.swift` | API key persistence in macOS Keychain |
| `Sources/PaperCore.swift` | PDF library, import, reading scopes, prompts and Markdown export |
| `Sources/PaperReader.swift` | PDF reading UI, notes, overview and conversations |
| `Sources/BrowserPaperSource.swift` | Browser URL discovery through Accessibility |
| `Sources/ReadingHTML.swift` | Escaped Markdown rendering and local page links |
| `Sources/PaperIndex.swift` | Metadata-only cards, keyword aliases, search, deduplication, archive state and topic graph |
| `Sources/PaperIndexWindow.swift` | Index search/list UI, editable cards, browser bookmarks and graph navigation |
| `Resources/` | Standalone app metadata, icon, instructions and user guide |
| `Tests/` | Offline tests and synthetic PDF generator |
| `scripts/` | Build and test entry points |

Run `./scripts/test.sh` before submitting behavior changes. Test runners include bundled rules so they work without a personal Codex installation. No live API calls or Keychain reads are made by these tests. Test artifacts are written to ignored `build/` paths.

`./scripts/build.sh` builds for the host architecture. `./scripts/build.sh --universal` builds arm64 and x86_64 and combines them with `lipo`. The app is ad-hoc signed; distribution with Developer ID signing and notarization is not configured. Do not add signing certificates, credentials or real papers to this repository.

The public bundle identifier and Keychain service are `io.github.YuyanWu-wyy.AcademicAssistant`. A pre-release personal installation may use a different identifier and require its own key/permission setup. The build does not migrate or alter that installation.

To maintain an existing custom installation, `APP_BUNDLE_ID` can override the build's identifier. Keychain uses the running bundle's identifier as its service. Do not install a second copy while the original is running: the global shortcuts are shared. A changed ad-hoc signature can require macOS permissions to be renewed.

`IndexedPaper` intentionally has no PDF, page text, notes or conversation fields. `PaperIndexStore` writes only this bounded card schema. The index sync is idempotent, preserves manual edits and archive state, and reports corrupt-file errors instead of replacing the file with an empty index. Graph edges are deterministic shared-tag matches, not model-inferred citations.

Manual checks for a release: selected text in a browser editor and PDF; P/R/D shortcuts; direct and local PDF import; model connection; preview/copy; page links; notes and conversations after restart. These UI checks require the user's own permissions and, for model calls, their own API account.

The model is not a source of verified scientific facts. Preserve explicit material boundaries and citation warnings; do not silently truncate imported text or treat page existence as proof of a claim.
