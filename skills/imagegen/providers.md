# Provider reference

Auto-detect order: `openai`, `gemini`, `together`, `xai`, `codex`, `gemini-cli`. Set `IMAGEGEN_PROVIDER` to override the default, or pass `--provider` per call. Pass `--model` or set the per-provider model env var to override models.

## openai — OpenAI Images API
- Requires: `OPENAI_API_KEY`
- Models: tries `gpt-image-2`, falls back to `gpt-image-1`. Override: `OPENAI_IMAGE_MODEL`.
- Sizes: 1024x1024, 1536x1024, 1024x1536 (other `--size` values snap to nearest). `--quality low|medium|high` maps directly.
- Editing: yes (`/v1/images/edits`, multiple `--input` images allowed).
- Cost: ~$0.006 (low) to ~$0.21 (high) per 1024x1024 image. No transparent backgrounds on gpt-image-2.

## gemini — Google Gemini API (Nano Banana)
- Requires: `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) from Google AI Studio.
- Models: tries `gemini-3.1-flash-image`, falls back to `gemini-2.5-flash-image`. Override: `GEMINI_IMAGE_MODEL`. `gemini-3-pro-image` for highest quality.
- `--aspect` supported (1:1, 16:9, 9:16, 4:3, 3:2, 21:9, ...); `--size` is converted to the nearest aspect ratio.
- Editing: yes (reference images via `--input`, multiple allowed — good at composition/consistency).
- Cost: ~$0.04–$0.15 per image. No API free tier on image models.

## together — Together AI (FLUX)
- Requires: `TOGETHER_API_KEY`
- Default model: `black-forest-labs/FLUX.1-schnell-Free` — **free** (rate-limited). Paid: `FLUX.1.1-pro`, etc. Override: `TOGETHER_IMAGE_MODEL`.
- Arbitrary `--size` (width/height passed through). No editing.

## xai — xAI Grok
- Requires: `XAI_API_KEY`
- Models: `grok-imagine-image` (~$0.02, default), `grok-imagine-image-quality` (~$0.05). Override: `XAI_IMAGE_MODEL`.
- No size control, no editing.

## codex — OpenAI Codex CLI (no API key)
- Requires: `codex` CLI installed and logged in via ChatGPT account (`codex login`). Uses the user's ChatGPT plan quota — no API key or per-image billing.
- Runs `codex exec` with the built-in image_gen tool (gpt-image-2). Slow (a full agent turn, often 1–3 minutes) and consumes plan limits faster than text; prefer API providers when a key is configured.
- Editing: yes (describe the edit; reference images passed by absolute path).

## gemini-cli — Gemini CLI + nanobanana extension
- Requires: `gemini` CLI, the nanobanana extension (`gemini extensions install https://github.com/gemini-cli-extensions/nanobanana`), and `NANOBANANA_API_KEY` (falls back to `GEMINI_API_KEY`). Note: bills through the Gemini API key — the CLI's free OAuth tier does not cover image generation, so the direct `gemini` provider is usually the better choice.
- Editing: yes (first `--input` image only).
