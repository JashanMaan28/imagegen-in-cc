# Contributing to ImageGen

Thanks for helping make image generation in Claude Code better! Contributions of all kinds are welcome — new providers, bug fixes, docs, and ideas.

## Development setup

```bash
git clone https://github.com/JashanMaan28/imagegen-in-cc.git
cd imagegen-in-cc

# Try your local copy inside Claude Code:
claude plugin marketplace add ./
claude plugin install imagegen@imagegen-in-cc
```

Requirements: `bash`, `curl`, `python3`. The dispatcher targets bash 3.2 (macOS default) — avoid bash 4+ features (associative arrays, `${var,,}`, etc.).

## Adding a provider

Providers live in [`scripts/imagegen.sh`](scripts/imagegen.sh); most are ~20 lines of curl. To add one:

1. Write a `gen_<name>()` function that reads `$PROMPT`, `$OUTPUT`, `$SIZE`, `$QUALITY`, `$MODEL`, `$INPUTS` and writes the image to `$OUTPUT` (the `finish_from_extract` helper handles base64/URL responses for OpenAI-compatible and Gemini-shaped APIs).
2. Register the name in `PROVIDERS_ORDER`, `available()`, `requirement_hint()`, and the `case` in `cmd_generate`.
3. If the provider can't edit images (`--input`), fail early with a clear message pointing at providers that can.
4. Document it in [`skills/imagegen/providers.md`](skills/imagegen/providers.md) (auth, models, cost, limitations) and the README table.
5. Add an entry under `[Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md).

## Before opening a PR

```bash
bash -n scripts/imagegen.sh        # syntax check
claude plugin validate .           # plugin + marketplace manifest check
scripts/imagegen.sh detect         # sanity check detection
```

If you changed or added a provider, please run at least one real generation with it and mention the result (provider, model, rough cost) in the PR description.

## Releasing (maintainers)

1. Move `[Unreleased]` entries in `CHANGELOG.md` into a new version section.
2. Bump `version` in `.claude-plugin/plugin.json` (users only receive updates when this changes).
3. Commit, tag `vX.Y.Z`, push with `--tags`, and create a GitHub release from the changelog section.
