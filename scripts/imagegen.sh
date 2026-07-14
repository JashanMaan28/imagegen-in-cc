#!/usr/bin/env bash
# imagegen.sh — unified image generation/editing dispatcher for the imagegen Claude Code plugin.
#
# Usage:
#   imagegen.sh detect
#   imagegen.sh generate --prompt "..." [--output out.png] [--provider NAME]
#                        [--size WxH] [--aspect W:H] [--quality low|medium|high]
#                        [--input ref.png]... [--model MODEL]
#
# Providers (auto-detected in this order): openai, gemini, together, xai, codex, gemini-cli
# Configuration is via environment variables — see `imagegen.sh detect` output or README.
set -euo pipefail

PROVIDERS_ORDER="openai gemini together xai codex gemini-cli"

log() { printf '[imagegen] %s\n' "$*" >&2; }
die() { printf '[imagegen] error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

have python3 || die "python3 is required (used for JSON handling)"
have curl || die "curl is required"

gemini_key() { printf '%s' "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"; }

# ---------------------------------------------------------------------------
# provider availability
# ---------------------------------------------------------------------------
available() {
  case "$1" in
    openai)     [ -n "${OPENAI_API_KEY:-}" ] ;;
    gemini)     [ -n "$(gemini_key)" ] ;;
    together)   [ -n "${TOGETHER_API_KEY:-}" ] ;;
    xai)        [ -n "${XAI_API_KEY:-}" ] ;;
    codex)      have codex ;;
    gemini-cli) have gemini && [ -n "${NANOBANANA_API_KEY:-$(gemini_key)}" ] ;;
    *)          return 1 ;;
  esac
}

requirement_hint() {
  case "$1" in
    openai)     echo "set OPENAI_API_KEY" ;;
    gemini)     echo "set GEMINI_API_KEY (or GOOGLE_API_KEY)" ;;
    together)   echo "set TOGETHER_API_KEY (FLUX.1-schnell-Free model is free)" ;;
    xai)        echo "set XAI_API_KEY" ;;
    codex)      echo "install Codex CLI (npm i -g @openai/codex) and run 'codex login' — uses your ChatGPT plan, no API key" ;;
    gemini-cli) echo "install Gemini CLI + nanobanana extension, set NANOBANANA_API_KEY" ;;
  esac
}

cmd_detect() {
  local p ok_any=""
  echo "provider    status"
  echo "----------  ------"
  for p in $PROVIDERS_ORDER; do
    if available "$p"; then
      printf '%-11s ready\n' "$p"
      ok_any=1
    else
      printf '%-11s unavailable — %s\n' "$p" "$(requirement_hint "$p")"
    fi
  done
  echo
  if [ -n "${IMAGEGEN_PROVIDER:-}" ]; then
    echo "default provider (IMAGEGEN_PROVIDER): $IMAGEGEN_PROVIDER"
  else
    echo "default provider: first ready one in the order above (set IMAGEGEN_PROVIDER to override)"
  fi
  [ -n "$ok_any" ] || { echo "no providers available"; return 3; }
}

pick_provider() {
  local p
  for p in $PROVIDERS_ORDER; do
    if available "$p"; then echo "$p"; return 0; fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# JSON helpers (python3 does all JSON building/parsing; prompts never touch shell interpolation)
# ---------------------------------------------------------------------------
RESP="$(mktemp -t imagegen-resp.XXXXXX)"
trap 'rm -f "$RESP"' EXIT

# extract <mode> <outfile>  — reads API JSON from $RESP; writes image or echoes "url:<...>"
extract() {
  python3 - "$1" "$2" "$RESP" <<'PY'
import sys, json, base64
mode, out, resp = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(resp))
b64 = url = None
if mode == "openai":  # OpenAI-compatible: openai, together, xai
    items = data.get("data") or []
    if items:
        b64 = items[0].get("b64_json")
        url = items[0].get("url")
elif mode == "gemini":
    for c in data.get("candidates") or []:
        for part in (c.get("content") or {}).get("parts") or []:
            blob = part.get("inlineData") or part.get("inline_data") or {}
            if blob.get("data"):
                b64 = blob["data"]
                break
        if b64:
            break
if b64:
    with open(out, "wb") as f:
        f.write(base64.b64decode(b64))
    print("file")
elif url:
    print("url:" + url)
else:
    err = data.get("error") or data
    sys.stderr.write("no image in response: " + json.dumps(err)[:1000] + "\n")
    sys.exit(1)
PY
}

api_error_snippet() {
  python3 - "$RESP" <<'PY'
import sys, json
try:
    data = json.load(open(sys.argv[1]))
    err = data.get("error") or data
    print(json.dumps(err)[:600])
except Exception:
    print(open(sys.argv[1], errors="replace").read()[:600])
PY
}

# post_json <url> <payload> <header>... ; echoes http code, body lands in $RESP
post_json() {
  local url="$1" payload="$2"; shift 2
  local args=(-sS -o "$RESP" -w '%{http_code}' -X POST "$url" -H "Content-Type: application/json")
  local h
  for h in "$@"; do args=("${args[@]}" -H "$h"); done
  curl "${args[@]}" --data-binary "$payload"
}

finish_from_extract() { # <mode> — writes $OUTPUT, downloading if the API returned a URL
  local mode="$1" result
  result="$(extract "$mode" "$OUTPUT")" || return 1
  case "$result" in
    url:*) curl -sSL -o "$OUTPUT" "${result#url:}" ;;
  esac
}

# ---------------------------------------------------------------------------
# size / aspect helpers
# ---------------------------------------------------------------------------
size_w() { printf '%s' "${SIZE%x*}"; }
size_h() { printf '%s' "${SIZE#*x}"; }

openai_size() { # snap requested size to an allowed gpt-image size
  [ -n "$SIZE" ] || { echo "auto"; return; }
  case "$SIZE" in
    1024x1024|1536x1024|1024x1536|auto) echo "$SIZE"; return ;;
  esac
  local w h; w="$(size_w)"; h="$(size_h)"
  if [ "$w" -gt "$h" ] 2>/dev/null; then echo "1536x1024"
  elif [ "$h" -gt "$w" ] 2>/dev/null; then echo "1024x1536"
  else echo "1024x1024"; fi
}

derived_aspect() { # explicit --aspect wins; else derive from --size
  if [ -n "$ASPECT" ]; then echo "$ASPECT"; return; fi
  [ -n "$SIZE" ] || return 0
  python3 - "$(size_w)" "$(size_h)" <<'PY'
import sys
w, h = float(sys.argv[1]), float(sys.argv[2])
ratios = {"1:1":1,"16:9":16/9,"9:16":9/16,"4:3":4/3,"3:4":3/4,"3:2":3/2,"2:3":2/3,"5:4":5/4,"4:5":4/5,"21:9":21/9}
print(min(ratios, key=lambda k: abs(ratios[k]-w/h)))
PY
}

# ---------------------------------------------------------------------------
# providers
# ---------------------------------------------------------------------------
gen_openai() {
  local models code
  if [ -n "$MODEL" ]; then models="$MODEL"
  elif [ -n "${OPENAI_IMAGE_MODEL:-}" ]; then models="$OPENAI_IMAGE_MODEL"
  else models="gpt-image-2 gpt-image-1"  # fall back if the account lacks the newer model
  fi
  local m
  for m in $models; do
    if [ "${#INPUTS[@]}" -gt 0 ]; then
      local args=(-sS -o "$RESP" -w '%{http_code}' https://api.openai.com/v1/images/edits
                  -H "Authorization: Bearer $OPENAI_API_KEY"
                  -F "model=$m" -F "prompt=$PROMPT" -F "size=$(openai_size)")
      [ -n "$QUALITY" ] && args=("${args[@]}" -F "quality=$QUALITY")
      local i
      for i in "${INPUTS[@]}"; do args=("${args[@]}" -F "image[]=@$i"); done
      code="$(curl "${args[@]}")"
    else
      local payload
      payload="$(MODEL_="$m" PROMPT_="$PROMPT" SIZE_="$(openai_size)" QUALITY_="$QUALITY" python3 <<'PY'
import json, os
p = {"model": os.environ["MODEL_"], "prompt": os.environ["PROMPT_"], "n": 1, "size": os.environ["SIZE_"]}
if os.environ.get("QUALITY_"): p["quality"] = os.environ["QUALITY_"]
print(json.dumps(p))
PY
)"
      code="$(post_json https://api.openai.com/v1/images/generations "$payload" "Authorization: Bearer $OPENAI_API_KEY")"
    fi
    if [ "$code" = "200" ]; then finish_from_extract openai; return; fi
    log "openai model '$m' failed (HTTP $code): $(api_error_snippet)"
  done
  die "openai: all attempted models failed"
}

gen_gemini() {
  local models m code key aspect
  key="$(gemini_key)"
  aspect="$(derived_aspect || true)"
  if [ -n "$MODEL" ]; then models="$MODEL"
  elif [ -n "${GEMINI_IMAGE_MODEL:-}" ]; then models="$GEMINI_IMAGE_MODEL"
  else models="gemini-3.1-flash-image gemini-2.5-flash-image"
  fi
  for m in $models; do
    local payload
    payload="$(PROMPT_="$PROMPT" ASPECT_="$aspect" INPUTS_="$(printf '%s\n' "${INPUTS[@]-}")" python3 <<'PY'
import json, os, base64, mimetypes
parts = []
for path in filter(None, os.environ.get("INPUTS_", "").split("\n")):
    mime = mimetypes.guess_type(path)[0] or "image/png"
    with open(path, "rb") as f:
        parts.append({"inline_data": {"mime_type": mime, "data": base64.b64encode(f.read()).decode()}})
parts.append({"text": os.environ["PROMPT_"]})
cfg = {"responseModalities": ["TEXT", "IMAGE"]}
if os.environ.get("ASPECT_"):
    cfg["imageConfig"] = {"aspectRatio": os.environ["ASPECT_"]}
print(json.dumps({"contents": [{"parts": parts}], "generationConfig": cfg}))
PY
)"
    code="$(post_json "https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent" "$payload" "x-goog-api-key: $key")"
    if [ "$code" = "200" ]; then finish_from_extract gemini; return; fi
    log "gemini model '$m' failed (HTTP $code): $(api_error_snippet)"
  done
  die "gemini: all attempted models failed"
}

gen_together() {
  [ "${#INPUTS[@]}" -eq 0 ] || die "together: image editing not supported by this provider adapter — use openai, gemini, or codex"
  local m code payload
  m="${MODEL:-${TOGETHER_IMAGE_MODEL:-black-forest-labs/FLUX.1-schnell-Free}}"
  payload="$(MODEL_="$m" PROMPT_="$PROMPT" W_="$(size_w)" H_="$(size_h)" python3 <<'PY'
import json, os
p = {"model": os.environ["MODEL_"], "prompt": os.environ["PROMPT_"], "n": 1, "response_format": "b64_json"}
try:
    p["width"], p["height"] = int(os.environ["W_"]), int(os.environ["H_"])
except (ValueError, KeyError):
    p["width"] = p["height"] = 1024
if "schnell" in p["model"].lower():
    p["steps"] = 4
print(json.dumps(p))
PY
)"
  code="$(post_json https://api.together.xyz/v1/images/generations "$payload" "Authorization: Bearer $TOGETHER_API_KEY")"
  [ "$code" = "200" ] || die "together failed (HTTP $code): $(api_error_snippet)"
  finish_from_extract openai
}

gen_xai() {
  [ "${#INPUTS[@]}" -eq 0 ] || die "xai: image editing not supported by this provider adapter — use openai, gemini, or codex"
  local m code payload
  m="${MODEL:-${XAI_IMAGE_MODEL:-grok-imagine-image}}"
  payload="$(MODEL_="$m" PROMPT_="$PROMPT" python3 <<'PY'
import json, os
print(json.dumps({"model": os.environ["MODEL_"], "prompt": os.environ["PROMPT_"], "n": 1, "response_format": "b64_json"}))
PY
)"
  code="$(post_json https://api.x.ai/v1/images/generations "$payload" "Authorization: Bearer $XAI_API_KEY")"
  [ "$code" = "200" ] || die "xai failed (HTTP $code): $(api_error_snippet)"
  finish_from_extract openai
}

gen_codex() {
  local abs_out workdir task i
  mkdir -p "$(dirname "$OUTPUT")"
  abs_out="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
  workdir="$(dirname "$abs_out")"
  if [ "${#INPUTS[@]}" -gt 0 ]; then
    task="Edit an image using your image generation tool. Reference image(s):"
    for i in "${INPUTS[@]}"; do
      task="$task $(cd "$(dirname "$i")" && pwd)/$(basename "$i")"
    done
    task="$task. Instruction: $PROMPT."
  else
    task="Generate an image using your image generation tool. Description: $PROMPT."
  fi
  [ -n "$SIZE" ] && task="$task Target dimensions: $SIZE."
  [ -n "$QUALITY" ] && task="$task Quality: $QUALITY."
  task="$task Save the final image to exactly this absolute path: $abs_out (overwrite if it exists). Do not create or modify any other files. Reply with only the saved file path."
  log "invoking codex exec (this can take a minute or two)..."
  codex exec --skip-git-repo-check -s workspace-write -C "$workdir" "$task" >&2 ||
    die "codex exec failed"
  [ -s "$abs_out" ] || die "codex finished but did not write $abs_out"
}

gen_gemini_cli() {
  local tmpdir pq newest
  tmpdir="$(mktemp -d -t imagegen-nb.XXXXXX)"
  pq="${PROMPT//\"/\\\"}"
  local cmd="/generate \"$pq\" --count=1"
  [ "${#INPUTS[@]}" -gt 0 ] && {
    cp "${INPUTS[@]}" "$tmpdir/"
    cmd="/edit \"$(basename "${INPUTS[0]}")\" \"$pq\""
  }
  log "invoking gemini CLI (nanobanana extension)..."
  ( cd "$tmpdir" && NANOBANANA_API_KEY="${NANOBANANA_API_KEY:-$(gemini_key)}" gemini "$cmd" >&2 ) ||
    { rm -rf "$tmpdir"; die "gemini CLI invocation failed (is the nanobanana extension installed?)"; }
  newest="$(ls -t "$tmpdir/nanobanana-output"/* 2>/dev/null | head -1 || true)"
  [ -n "$newest" ] || { rm -rf "$tmpdir"; die "gemini CLI produced no output in nanobanana-output/"; }
  mkdir -p "$(dirname "$OUTPUT")"
  mv "$newest" "$OUTPUT"
  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# generate command
# ---------------------------------------------------------------------------
cmd_generate() {
  [ -n "$PROMPT" ] || die "--prompt is required"
  if [ -z "$OUTPUT" ]; then
    OUTPUT="./imagegen-$(date +%Y%m%d-%H%M%S).png"
    log "no --output given, using $OUTPUT"
  fi
  local i
  for i in "${INPUTS[@]-}"; do
    [ -z "$i" ] || [ -f "$i" ] || die "input image not found: $i"
  done
  if [ -z "$PROVIDER" ]; then
    PROVIDER="$(pick_provider)" || die "no providers available — run 'imagegen.sh detect' for setup hints"
  fi
  available "$PROVIDER" || die "provider '$PROVIDER' not available — $(requirement_hint "$PROVIDER")"
  mkdir -p "$(dirname "$OUTPUT")"
  log "provider: $PROVIDER"
  case "$PROVIDER" in
    openai)     gen_openai ;;
    gemini)     gen_gemini ;;
    together)   gen_together ;;
    xai)        gen_xai ;;
    codex)      gen_codex ;;
    gemini-cli) gen_gemini_cli ;;
    *)          die "unknown provider: $PROVIDER (known: $PROVIDERS_ORDER)" ;;
  esac
  [ -s "$OUTPUT" ] || die "generation reported success but $OUTPUT is missing or empty"
  printf 'OK %s %s (%s bytes)\n' "$PROVIDER" "$OUTPUT" "$(wc -c < "$OUTPUT" | tr -d ' ')"
}

# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------
CMD="${1:-}"
[ -n "$CMD" ] && shift || true

PROMPT="" OUTPUT="" SIZE="" ASPECT="" QUALITY="" MODEL=""
PROVIDER="${IMAGEGEN_PROVIDER:-}"
INPUTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --prompt)      PROMPT="$2"; shift 2 ;;
    --output|-o)   OUTPUT="$2"; shift 2 ;;
    --provider)    PROVIDER="$2"; shift 2 ;;
    --size)        SIZE="$2"; shift 2 ;;
    --aspect)      ASPECT="$2"; shift 2 ;;
    --quality)     QUALITY="$2"; shift 2 ;;
    --model)       MODEL="$2"; shift 2 ;;
    --input|-i)    INPUTS[${#INPUTS[@]}]="$2"; shift 2 ;;
    -h|--help)     sed -n '2,12p' "$0"; exit 0 ;;
    *)             die "unknown option: $1 (see --help)" ;;
  esac
done

case "$CMD" in
  detect|providers) cmd_detect ;;
  generate|edit)    cmd_generate ;;
  ""|-h|--help)     sed -n '2,12p' "$0" ;;
  *)                die "unknown command: $CMD (use: detect | generate)" ;;
esac
