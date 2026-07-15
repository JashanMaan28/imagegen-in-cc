---
description: Create instant zero-cost placeholder images (swap for real AI generations later)
argument-hint: <what it's for> [--size 1200x630 | --preset hero] [--output path.png]
---

Create placeholder image(s) for: **$ARGUMENTS**

1. For each placeholder the user needs, run:
   `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" placeholder --output <path.png> --size <WxH or use --preset> --label "<short name>" --prompt "<the full AI prompt you would use for the real image>"`
   This is instant and free — no AI provider involved. The `--prompt` is not used now, but it is recorded in `.imagegen/history.jsonl` so the real image can be generated later without re-deriving the prompt.
2. Wire the placeholders into the project like real assets (correct paths, dimensions, alt text).
3. Tell the user: when they're ready to spend on real generations, say "replace the placeholders" — then read the `placeholder` entries from `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" history`, and run a real `generate` with each recorded prompt to the same output path.
