---
description: Check which image-generation providers are available and help configure them
---

Help the user set up image generation providers for the imagegen plugin.

1. Run: `"${CLAUDE_PLUGIN_ROOT}/scripts/imagegen.sh" detect`
2. Show the user a short summary: which providers are ready, and which env var or CLI each unavailable one needs (the detect output includes hints; skills/imagegen/providers.md in this plugin has full details including pricing).
3. Recommend based on their situation:
   - Has a ChatGPT subscription and the Codex CLI → `codex` works with zero configuration (`npm i -g @openai/codex && codex login`).
   - Wants free API generation → Together AI's `FLUX.1-schnell-Free` (just needs a free `TOGETHER_API_KEY` from api.together.ai).
   - Wants best quality/editing → `OPENAI_API_KEY` (gpt-image) or `GEMINI_API_KEY` (Nano Banana, from aistudio.google.com).
4. If they want a key configured, tell them to add `export <VAR>="..."` to their shell profile (~/.zshrc), then restart Claude Code. Do not ask the user to paste the key into the chat.
5. If they want a default provider, suggest `export IMAGEGEN_PROVIDER=<name>`.
6. Offer to run a cheap test generation once a provider is ready.
