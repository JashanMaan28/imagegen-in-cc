# ImageGen for Claude Code

Generate and edit images directly from Claude Code — heroes, icons, illustrations, placeholders, or anything you can describe — using whichever AI provider you already have access to.

```
/imagine a watercolor fox in a snowy forest --aspect 16:9
```

## Providers

| Provider | Needs | Cost | Editing |
|---|---|---|---|
| `codex` | Codex CLI + ChatGPT login (**no API key**) | your ChatGPT plan quota | ✅ |
| `openai` | `OPENAI_API_KEY` | ~$0.006–$0.21 / image | ✅ |
| `gemini` | `GEMINI_API_KEY` | ~$0.04–$0.15 / image | ✅ |
| `together` | `TOGETHER_API_KEY` | **free** (FLUX.1-schnell-Free) | ❌ |
| `xai` | `XAI_API_KEY` | ~$0.02 / image | ❌ |
| `gemini-cli` | Gemini CLI + nanobanana ext + key | as gemini | ✅ |

The plugin auto-detects what's configured and picks the best option; override with `--provider` or `export IMAGEGEN_PROVIDER=<name>`.

## Install

```
/plugin marketplace add JashanMaan28/imagegen-in-cc
/plugin install imagegen@imagegen-in-cc
```

Then run `/imagegen-setup` to see which providers are ready on your machine.

## Usage

- `/imagine <prompt> [--provider name] [--size 1536x1024] [--aspect 16:9] [--quality high] [--output path.png]` — generate an image.
- `/image-edit <path> <instruction>` — edit an existing image (background swap, style change, add/remove objects).
- `/imagegen-setup` — check provider availability and get setup help.
- **Automatic**: Claude invokes the `imagegen` skill on its own when a task needs image assets — e.g. "build me a landing page with a hero image" just works.

Everything runs through one script you can also use directly:

```bash
scripts/imagegen.sh detect
scripts/imagegen.sh generate --prompt "isometric city at dusk" --output city.png --aspect 16:9
scripts/imagegen.sh generate --prompt "make the sky stormy" --input city.png --output city-storm.png
```

## Configuration

| Env var | Purpose |
|---|---|
| `IMAGEGEN_PROVIDER` | default provider (`openai`, `gemini`, `together`, `xai`, `codex`, `gemini-cli`) |
| `OPENAI_API_KEY` / `OPENAI_IMAGE_MODEL` | OpenAI key / model override (default `gpt-image-2`, falls back to `gpt-image-1`) |
| `GEMINI_API_KEY` or `GOOGLE_API_KEY` / `GEMINI_IMAGE_MODEL` | Gemini key / model override (default `gemini-3.1-flash-image`, falls back to `gemini-2.5-flash-image`) |
| `TOGETHER_API_KEY` / `TOGETHER_IMAGE_MODEL` | Together key / model (default `black-forest-labs/FLUX.1-schnell-Free`) |
| `XAI_API_KEY` / `XAI_IMAGE_MODEL` | xAI key / model (default `grok-imagine-image`) |
| `NANOBANANA_API_KEY` | key for the gemini-cli provider (falls back to `GEMINI_API_KEY`) |

Requirements: `bash`, `curl`, `python3` (all preinstalled on macOS/Linux).

## Adding a provider

Providers live in [`scripts/imagegen.sh`](scripts/imagegen.sh) as small `gen_<name>()` functions (most are ~20 lines of curl). Add the function, register the name in `PROVIDERS_ORDER`, `available()`, and `requirement_hint()`, document it in `skills/imagegen/providers.md`, and open a PR.

## License

MIT
