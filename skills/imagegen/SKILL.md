---
name: imagegen
description: Generate or edit images with AI providers (Codex CLI, OpenAI gpt-image, Google Gemini/Nano Banana, Together AI FLUX, xAI Grok). Use when the user asks to generate, create, draw, or edit an image, or when a task needs image assets — website heroes, backgrounds, icons, logos, favicons, illustrations, placeholders, textures, or mockup imagery.
---

# Image generation

Generate images by running the bundled dispatcher script. It auto-detects which provider is configured on this machine and handles all API differences.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" generate \
  --prompt "<detailed visual description>" \
  --output <path.png> \
  [--provider openai|gemini|together|xai|codex|gemini-cli] \
  [--preset hero|banner|og|card|avatar|icon|favicon] \
  [--style flat|photo|watercolor|3d|isometric|pixel-art|line-art|sketch|cinematic] \
  [--transparent] [--format webp|jpeg|png] [--max-width N] [--crop WxH] \
  [--size 1536x1024] [--aspect 16:9] [--quality low|medium|high] \
  [--variants N] [--input reference.png]...
```

## Workflow

1. **Check providers once per session** (skip if you already know one works):
   `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" detect`
   If none are ready, show the user the detect output — it contains setup hints for each provider — and stop (or offer placeholders, which need no provider).
2. **Write a strong prompt.** Describe subject, composition, lighting, color palette, and mood in 2–5 sentences. Use `--style` for the aesthetic instead of describing it yourself — it appends a curated fragment. For UI/web assets, state the intended use ("hero background for a developer-tools landing page") and demand "no text, no words, no letters" unless text is wanted.
3. **Use presets for web assets** instead of picking dimensions manually:

   | Preset | Effect |
   |---|---|
   | `hero` | 1536x1024, 16:9 |
   | `banner` | 1536x1024, 21:9 |
   | `og` | 16:9 generation, auto-cropped to exactly 1200x630 |
   | `card` | 1024x1536 portrait, 2:3 |
   | `avatar` | 1024x1024 square |
   | `icon` | 1024x1024 + transparent background automatically |
   | `favicon` | icon + emits favicon.ico, favicon-16/32.png, apple-touch-icon.png |

4. **Run the script.** Omit `--provider` to use the best available one. Use `run_in_background` or a generous timeout (≥ 5 min) for the `codex` provider — it runs a full agent turn per image.
5. **Verify visually.** The script prints `OK <provider> <path> (<bytes>)` per image. Read the generated file to confirm it matches the request before using it. If it misses, refine the prompt and regenerate (or use `--variants 3` and pick the best).
6. **Place it with care.** Write to the project's asset directory (`public/`, `assets/`, `static/`) with a descriptive filename. **Always write descriptive alt text** when embedding into HTML/JSX/Markdown — you just looked at the image, so describe what it actually shows, not the prompt. For web delivery add `--format webp --max-width 1600` (or convert existing files with `scripts/postprocess.py convert`), so pages don't ship multi-MB PNGs.

## Transparent backgrounds

Image APIs can't reliably output transparency, so `--transparent` does it properly: it forces a pure-white background in the prompt, then keys the white out with alpha un-mixing and trims to content (requires Pillow: `pip3 install --user pillow`). Output must be `.png` (optionally add `--format webp` — alpha survives). The `icon` and `favicon` presets enable this automatically.

## Editing images

Pass one or more `--input` images with an instruction as the prompt. Works with `openai`, `gemini`, `codex`, and `gemini-cli` (not `together`/`xai`). Never overwrite the user's original — write to a new file.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" generate \
  --prompt "make the background a sunset gradient, keep the subject unchanged" \
  --input original.png --output original-sunset.png
```

## Placeholders (free, instant)

While prototyping or when no provider is configured, don't spend money — create labeled placeholder images and record the intended prompt for later:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" placeholder --output public/hero.png \
  --preset hero --label "Hero" --prompt "<the real prompt to use later>"
```

Later, "replace the placeholders" = read the `placeholder` entries from history and run real `generate` calls with the recorded prompts to the same paths.

## History

Every generation and placeholder is logged to `.imagegen/history.jsonl` in the working directory (prompt, provider, settings, output path). Use `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" history 20` to review it — e.g. to regenerate an earlier image with a tweaked prompt while keeping its settings. Suggest adding `.imagegen/` to `.gitignore` unless the team wants prompts versioned. Disable logging with `IMAGEGEN_NO_HISTORY=1`.

## Cost awareness

Each generation costs real money or quota (roughly $0.01–$0.25 per image; codex consumes the user's ChatGPT plan limits). Generate deliberately: one image per asset, refine prompts instead of spraying variants, prefer placeholders during layout work, and ask before generating more than ~5 images in one task.

For per-provider details (models, env vars, pricing, limitations) see [providers.md](providers.md).
