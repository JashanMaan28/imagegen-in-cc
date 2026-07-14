# Privacy Policy — ImageGen plugin

_Last updated: 2026-07-14_

## Summary

The ImageGen plugin runs entirely on your machine and collects **no data whatsoever**. There is no telemetry, no analytics, no account, and no server operated by this project.

## What the plugin does with your data

- **Prompts and images are sent only to the AI provider you choose** (OpenAI, Google Gemini, Together AI, xAI, or your locally installed Codex/Gemini CLI). This happens only when you explicitly run a generation or edit, and only to that one provider. Each provider processes your prompt under its own privacy policy and terms:
  - OpenAI: https://openai.com/policies/privacy-policy
  - Google: https://policies.google.com/privacy
  - Together AI: https://www.together.ai/privacy
  - xAI: https://x.ai/legal/privacy-policy
- **API keys** are read from environment variables you set yourself and are used only in the `Authorization` header of requests to the corresponding provider. They are never written to disk, logged, or sent anywhere else by this plugin.
- **Generated images** are saved only to the local file path you (or Claude, on your instruction) specify.

## What this project collects

Nothing. The plugin makes no network requests other than the provider API calls described above.

## Questions

Open an issue at https://github.com/JashanMaan28/imagegen-in-cc/issues or email jmaan1337@gmail.com.
