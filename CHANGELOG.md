# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-14

### Added

- Initial release.
- `scripts/imagegen.sh` — unified dispatcher with six providers:
  - `codex` — OpenAI Codex CLI via ChatGPT login (no API key)
  - `openai` — OpenAI Images API (`gpt-image-2`, falls back to `gpt-image-1`)
  - `gemini` — Google Gemini API / Nano Banana (`gemini-3.1-flash-image`, falls back to `gemini-2.5-flash-image`)
  - `together` — Together AI (`FLUX.1-schnell-Free`, free tier)
  - `xai` — xAI Grok (`grok-imagine-image`)
  - `gemini-cli` — Gemini CLI with the nanobanana extension
- Provider auto-detection (`detect` subcommand) with per-provider setup hints.
- Image editing via `--input` (openai, gemini, codex, gemini-cli).
- Size/aspect/quality flags with per-provider mapping and model overrides via env vars.
- `imagegen` skill — Claude generates assets automatically when a task needs them.
- Slash commands: `/imagine`, `/image-edit`, `/imagegen-setup`.
- Self-hosted plugin marketplace (`.claude-plugin/marketplace.json`).

[Unreleased]: https://github.com/JashanMaan28/imagegen-in-cc/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/JashanMaan28/imagegen-in-cc/releases/tag/v0.1.0
