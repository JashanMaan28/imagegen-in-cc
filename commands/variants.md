---
description: Generate several image variants of one prompt, compare them, and keep the best
argument-hint: <prompt> [count, default 4] [--provider name] [--preset hero] [--style flat]
---

Generate image variants for: **$ARGUMENTS**

Follow the imagegen skill (skills/imagegen/SKILL.md in this plugin). Specifically:

1. Extract the prompt, an optional variant count (default 4, max 8), and any flags from $ARGUMENTS. Expand the prompt into a detailed visual description.
2. Run (single call — the script handles the loop and numbers the outputs `-1`, `-2`, ...):
   `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" generate --prompt "<expanded prompt>" --output <stem>.png --variants <count> <flags>`
   Warn the user first if the codex provider will be used (each variant is a full agent run — slow and quota-hungry); suggest an API provider if one is available.
3. Read every generated variant, then present a comparison: one line per variant describing how it interprets the prompt, and your recommendation with reasoning.
4. Ask the user which to keep. Rename the winner to the clean filename (without `-N`) and delete the rejected variant files.
