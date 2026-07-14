---
description: Generate an image from a prompt (auto-selects the best available provider)
argument-hint: <prompt> [--provider name] [--size WxH] [--aspect 16:9] [--quality high] [--output path.png]
---

Generate an image for this request: **$ARGUMENTS**

Follow the imagegen skill (skills/imagegen/SKILL.md in this plugin). Specifically:

1. Separate any trailing flags (`--provider`, `--size`, `--aspect`, `--quality`, `--output`, `--model`) from the prompt text in $ARGUMENTS.
2. Expand the user's prompt into a detailed visual description (subject, style, composition, lighting, palette). Keep the user's explicit wishes verbatim; add craft, don't change intent.
3. If no `--output` was given, choose a descriptive filename in the current directory (e.g. `./sunset-fox.png`).
4. Run:
   `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" generate --prompt "<expanded prompt>" --output <path> <flags>`
   Use a timeout of at least 5 minutes if the codex provider will be used.
5. If it fails because no provider is configured, run `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" detect` and show the user the setup hints.
6. On success, Read the image to verify it matches the request, then tell the user the file path and which provider generated it. If it clearly misses the request, offer to regenerate with a refined prompt (don't loop without asking).
