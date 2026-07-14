---
description: Edit an existing image with an AI instruction (background swap, style change, object add/remove)
argument-hint: <path/to/image> <what to change> [--provider name] [--output path.png]
---

Edit an image as requested: **$ARGUMENTS**

Follow the imagegen skill (skills/imagegen/SKILL.md in this plugin). Specifically:

1. Identify the input image path(s) and the edit instruction from $ARGUMENTS. Verify each input file exists (if not, ask the user for the correct path).
2. Default the output to `<input-stem>-edited.png` next to the input unless `--output` was given. Never overwrite the original.
3. Run:
   `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" generate --prompt "<edit instruction>" --input <input> --output <path> <flags>`
   Editing is supported by the openai, gemini, codex, and gemini-cli providers; if the auto-selected provider refuses, retry with one of those.
4. On success, Read both the original and the edited image, confirm the edit was applied, and report the output path and provider to the user.
