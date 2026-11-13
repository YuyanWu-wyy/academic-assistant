# Contributing

Bug reports and focused pull requests are welcome. Include the macOS version, browser, expected behavior and a minimal reproduction using synthetic text or a public paper you are allowed to share.

Never include API keys, login credentials, private papers, unpublished research, personal reading records or screenshots containing them. Replace identifiers in diagnostic examples with placeholders.

For code changes:

1. Keep the app buildable with macOS system frameworks, without requiring a personal installed copy.
2. Run `./scripts/test.sh` and `./scripts/build.sh`.
3. Add focused regression coverage when changing behavior; use mocked network responses and synthetic PDFs.
4. Describe any UI, permission, data handling or prompt changes in the pull request.

Please discuss large redesigns in an issue first. Keep model output separate from original source text, require review before manuscript replacement, and preserve per-paper context boundaries.
