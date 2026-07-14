---
name: imagegen
description: Generate or edit images with AI providers (Codex CLI, OpenAI gpt-image, Google Gemini/Nano Banana, Together AI FLUX, xAI Grok). Use when the user asks to generate, create, draw, or edit an image, or when a task needs image assets — website heroes, backgrounds, icons, logos, illustrations, placeholders, textures, or mockup imagery.
---

# Image generation

Generate images by running the bundled dispatcher script. It auto-detects which provider is configured on this machine and handles all API differences.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" generate \
  --prompt "<detailed visual description>" \
  --output <path.png> \
  [--provider openai|gemini|together|xai|codex|gemini-cli] \
  [--size 1536x1024] [--aspect 16:9] [--quality low|medium|high] \
  [--input reference.png]...
```

## Workflow

1. **Check providers once per session** (skip if you already know one works):
   `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" detect`
   If none are ready, show the user the detect output — it contains setup hints for each provider — and stop.
2. **Write a strong prompt.** Describe subject, style, composition, lighting, color palette, and mood in 2–5 sentences. For UI/web assets, state the intended use ("hero background for a developer-tools landing page") and demand "no text, no words, no letters" unless text is wanted (models render text poorly).
3. **Run the script.** Omit `--provider` to use the best available one. Use `run_in_background` or a generous timeout (≥ 5 min) for the `codex` provider — it runs a full agent turn.
4. **Verify visually.** The script prints `OK <provider> <path> (<bytes>)` on success. Read the generated image file to confirm it matches the request before using or presenting it. If it misses, refine the prompt and regenerate.
5. **Place it.** When generating assets for a project, write to the project's asset directory (e.g. `public/`, `assets/`, `static/`) with a descriptive filename, then wire it into the code.

## Editing images

Pass one or more `--input` images with an instruction as the prompt:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" generate \
  --prompt "make the background a sunset gradient, keep the subject unchanged" \
  --input original.png --output edited.png
```

Editing works with the `openai`, `gemini`, `codex`, and `gemini-cli` providers (not `together`/`xai`).

## Sizing guidance for web assets

| Asset | Suggested flags |
|---|---|
| Hero / banner | `--size 1536x1024` or `--aspect 16:9` |
| Portrait card / mobile | `--size 1024x1536` or `--aspect 9:16` |
| Icon / avatar / logo | `--size 1024x1024` (downscale in code/CSS) |
| Social preview (OG) | `--aspect 16:9` |

Note: gpt-image-2 does not support transparent backgrounds; for icons request "flat solid #FFFFFF background" and note the limitation, or use the gemini provider.

## Cost awareness

Each generation costs real money or quota (roughly $0.01–$0.25 per image; codex consumes the user's ChatGPT plan limits). Generate deliberately: one image per asset, refine the prompt instead of generating many variants, and ask before generating more than ~5 images in one task.

For per-provider details (models, env vars, pricing, limitations) see [providers.md](providers.md).
