---
description: Regenerate a previous image with tweaks, using the recorded generation history
argument-hint: <file, description, or "last"> <what to change>
---

Regenerate a previously generated image with changes: **$ARGUMENTS**

1. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" history 20` to list recent generations (each entry shows timestamp, provider, output path, settings, and the original prompt).
2. Identify which entry the user means — by file path, by description, or the most recent one for "last". If genuinely ambiguous, ask.
3. Take the entry's recorded prompt and apply the user's requested change to it (edit the prompt text — don't just append the instruction). Keep the entry's provider, preset, style, size/aspect, and transparency settings unless the user overrides them.
4. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" generate ...` with the modified prompt and the same settings, writing to the same output path (this replaces the old image — mention that; if the user wants to keep both, add a suffix to the filename).
5. Read the result, verify the change landed, and report. The new generation is recorded in history automatically, so further tweaks can build on it.
