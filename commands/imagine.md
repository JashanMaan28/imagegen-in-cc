---
description: Generate an image from a prompt (auto-selects the best available provider)
argument-hint: <prompt> [--preset hero|icon|favicon...] [--style flat|photo...] [--transparent] [--provider name] [--size WxH] [--quality high] [--output path.png]
---

Generate an image for this request: **$ARGUMENTS**

Follow the imagegen skill (skills/imagegen/SKILL.md in this plugin). Specifically:

1. Separate any trailing flags (`--preset`, `--style`, `--transparent`, `--provider`, `--size`, `--aspect`, `--quality`, `--format`, `--output`, `--model`, `--variants`) from the prompt text in $ARGUMENTS. If the request obviously matches a preset or style (e.g. "a hero image", "a flat-style icon"), apply the matching flag even if not spelled out.
2. Expand the user's prompt into a detailed visual description (subject, composition, lighting, palette). Keep the user's explicit wishes verbatim; add craft, don't change intent. Don't describe the aesthetic if a `--style` flag covers it.
3. If no `--output` was given, choose a descriptive filename in the current directory (e.g. `./sunset-fox.png`).
4. Run:
   `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" generate --prompt "<expanded prompt>" --output <path> <flags>`
   Use a timeout of at least 5 minutes if the codex provider will be used.
5. If it fails because no provider is configured, run `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" detect` and show the user the setup hints (and mention `/placeholder` as the free alternative).
6. On success, Read the image to verify it matches the request, then tell the user the file path and which provider generated it. If it clearly misses the request, offer to regenerate with a refined prompt (don't loop without asking).
