# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `--transparent` flag: real alpha transparency on any provider via white-key + alpha un-mixing post-processing (Pillow).
- Size presets (`--preset hero|banner|og|card|avatar|icon|favicon`); `og` auto-crops to 1200x630, `favicon` emits a full favicon set.
- Style presets (`--style flat|photo|watercolor|3d|isometric|pixel-art|line-art|sketch|cinematic`).
- `--variants N`: generate up to 8 numbered takes of one prompt; new `/variants` command compares them and keeps the winner.
- Generation history: every generation/placeholder logged to `.imagegen/history.jsonl`; new `history` subcommand and `/reimagine` command to regenerate past images with tweaks.
- `placeholder` subcommand + `/placeholder` command: instant zero-cost placeholder images that record the intended prompt for later real generation.
- Web-asset post-processing: `--format webp|jpeg|png`, `--max-width N`, `--crop WxH` (`scripts/postprocess.py`, also usable standalone).
- Skill now instructs Claude to write descriptive alt text (based on the actual image) when embedding generated assets.
- Cross-agent installation through `npx skills add JashanMaan28/imagegen-in-cc`, with a live skills.sh listing and install-count badge.

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
