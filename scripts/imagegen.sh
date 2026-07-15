#!/usr/bin/env bash
# imagegen.sh — unified image generation/editing dispatcher for the imagegen Claude Code plugin.
#
# Usage:
#   imagegen.sh detect
#   imagegen.sh generate --prompt "..." [--output out.png] [--provider NAME]
#                        [--size WxH] [--aspect W:H] [--quality low|medium|high]
#                        [--preset hero|banner|og|card|avatar|icon|favicon]
#                        [--style flat|photo|watercolor|3d|isometric|pixel-art|line-art|sketch|cinematic]
#                        [--transparent] [--format png|webp|jpeg] [--max-width N] [--crop WxH]
#                        [--variants N] [--input ref.png]... [--model MODEL]
#   imagegen.sh placeholder --output out.png [--size WxH] [--label TEXT] [--prompt "intended prompt"]
#   imagegen.sh history [N]
#
# Providers (auto-detected in this order): openai, gemini, together, xai, codex, gemini-cli
# Configuration is via environment variables — see `imagegen.sh detect` output or README.
# Successful generations are logged to .imagegen/history.jsonl (disable: IMAGEGEN_NO_HISTORY=1).
set -euo pipefail

PROVIDERS_ORDER="openai gemini together xai codex gemini-cli"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POSTPROCESS="$SCRIPT_DIR/postprocess.py"

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
# presets & styles
# ---------------------------------------------------------------------------
apply_preset() { # explicit flags win over preset values
  case "$PRESET" in
    "")      ;;
    hero)    : "${SIZE:=1536x1024}"; : "${ASPECT:=16:9}" ;;
    banner)  : "${SIZE:=1536x1024}"; : "${ASPECT:=21:9}" ;;
    og)      : "${SIZE:=1536x1024}"; : "${ASPECT:=16:9}"; : "${CROP:=1200x630}" ;;
    card)    : "${SIZE:=1024x1536}"; : "${ASPECT:=2:3}" ;;
    avatar)  : "${SIZE:=1024x1024}"; : "${ASPECT:=1:1}" ;;
    icon)    : "${SIZE:=1024x1024}"; : "${ASPECT:=1:1}"; TRANSPARENT=1 ;;
    favicon) : "${SIZE:=1024x1024}"; : "${ASPECT:=1:1}"; TRANSPARENT=1; FAVICON_SET=1 ;;
    *) die "unknown preset: $PRESET (known: hero banner og card avatar icon favicon)" ;;
  esac
}

style_fragment() {
  case "$STYLE" in
    "")         ;;
    flat)       echo "Flat 2D vector illustration style: clean geometric shapes, smooth solid colors, minimal detail, no texture, no photorealism." ;;
    photo)      echo "Photorealistic: natural lighting, realistic materials, shallow depth of field, high dynamic range, shot on a full-frame camera." ;;
    watercolor) echo "Watercolor painting style: soft translucent washes, visible paper texture, gentle color bleeding, hand-painted feel." ;;
    3d)         echo "Soft 3D render style: smooth rounded forms, subtle global illumination, matte materials, studio lighting, high polish." ;;
    isometric)  echo "Isometric 3D illustration style: 45-degree angled view, clean geometry, consistent perspective, vibrant flat shading." ;;
    pixel-art)  echo "Pixel art style: crisp visible pixels, limited retro color palette, no anti-aliasing, 16-bit game aesthetic." ;;
    line-art)   echo "Minimal line art style: single-weight clean black strokes, no fill or shading, generous white space." ;;
    sketch)     echo "Hand-drawn pencil sketch style: loose expressive linework, light cross-hatching, monochrome graphite on paper." ;;
    cinematic)  echo "Cinematic style: dramatic lighting, film color grading, anamorphic framing, moody atmosphere, high production value." ;;
    *) die "unknown style: $STYLE (known: flat photo watercolor 3d isometric pixel-art line-art sketch cinematic)" ;;
  esac
}

# ---------------------------------------------------------------------------
# history
# ---------------------------------------------------------------------------
history_file() { printf '%s/history.jsonl' "${IMAGEGEN_HISTORY_DIR:-.imagegen}"; }

record_history() { # <type> <output-path>
  [ -n "${IMAGEGEN_NO_HISTORY:-}" ] && return 0
  local f; f="$(history_file)"
  mkdir -p "$(dirname "$f")"
  TYPE_="$1" OUTPUT_="$2" PROVIDER_="${PROVIDER:-}" PROMPT_="$PROMPT_RAW" STYLE_="$STYLE" \
  PRESET_="$PRESET" SIZE_="$SIZE" ASPECT_="$ASPECT" QUALITY_="$QUALITY" MODEL_="$MODEL" \
  TRANSPARENT_="${TRANSPARENT:-}" LABEL_="$LABEL" INPUTS_="$(printf '%s\n' "${INPUTS[@]-}")" \
  python3 >> "$f" <<'PY'
import json, os, datetime
e = {"ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
for key, env in [("type", "TYPE_"), ("provider", "PROVIDER_"), ("prompt", "PROMPT_"),
                 ("style", "STYLE_"), ("preset", "PRESET_"), ("size", "SIZE_"),
                 ("aspect", "ASPECT_"), ("quality", "QUALITY_"), ("model", "MODEL_"),
                 ("label", "LABEL_"), ("output", "OUTPUT_")]:
    v = os.environ.get(env, "")
    if v:
        e[key] = v
if os.environ.get("TRANSPARENT_"):
    e["transparent"] = True
inputs = [i for i in os.environ.get("INPUTS_", "").split("\n") if i]
if inputs:
    e["inputs"] = inputs
print(json.dumps(e))
PY
}

cmd_history() {
  local f; f="$(history_file)"
  [ -f "$f" ] || { echo "no history yet ($f)"; return 0; }
  python3 - "$f" "${HIST_N:-10}" <<'PY'
import sys, json
with open(sys.argv[1]) as fh:
    lines = fh.read().splitlines()[-int(sys.argv[2]):]
for line in lines:
    try:
        e = json.loads(line)
    except ValueError:
        continue
    parts = [e.get("ts", "?"), e.get("type", "?"), e.get("provider", "-"), e.get("output", "?")]
    extras = [f"{k}={e[k]}" for k in ("preset", "style", "size", "aspect") if e.get(k)]
    if e.get("transparent"):
        extras.append("transparent")
    prompt = e.get("prompt", "")
    if len(prompt) > 100:
        prompt = prompt[:97] + "..."
    print("  ".join(parts) + ("  [" + " ".join(extras) + "]" if extras else ""))
    if prompt:
        print("    " + prompt)
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
# post-processing pipeline (transparent → crop/resize/convert → favicon set)
# ---------------------------------------------------------------------------
post_process() { # <path> ; echoes final path
  local out="$1"
  if [ -n "${TRANSPARENT:-}" ]; then
    python3 "$POSTPROCESS" transparent "$out" >&2
  fi
  if [ -n "${FORMAT:-}" ] || [ -n "${MAX_WIDTH:-}" ] || [ -n "${CROP:-}" ]; then
    local final="$out"
    [ -n "${FORMAT:-}" ] && final="${out%.*}.$FORMAT"
    local cargs=()
    [ -n "${MAX_WIDTH:-}" ] && cargs=("${cargs[@]}" --max-width "$MAX_WIDTH")
    [ -n "${CROP:-}" ] && cargs=("${cargs[@]}" --crop "$CROP")
    python3 "$POSTPROCESS" convert "$out" "$final" ${cargs[@]+"${cargs[@]}"} >&2
    [ "$final" != "$out" ] && rm -f "$out"
    out="$final"
  fi
  if [ -n "${FAVICON_SET:-}" ]; then
    python3 "$POSTPROCESS" favicon "$out" "$(dirname "$out")" >&2
  fi
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# generate command
# ---------------------------------------------------------------------------
cmd_generate() {
  [ -n "$PROMPT" ] || die "--prompt is required"
  apply_preset
  if [ -z "$OUTPUT" ]; then
    OUTPUT="./imagegen-$(date +%Y%m%d-%H%M%S).png"
    log "no --output given, using $OUTPUT"
  fi
  case "$OUTPUT" in *.png) ;; *)
    [ -z "${TRANSPARENT:-}" ] || die "--transparent requires a .png output (add --format webp to convert after keying)"
  esac
  local i
  for i in "${INPUTS[@]-}"; do
    [ -z "$i" ] || [ -f "$i" ] || die "input image not found: $i"
  done
  if [ -z "$PROVIDER" ]; then
    PROVIDER="$(pick_provider)" || die "no providers available — run 'imagegen.sh detect' for setup hints"
  fi
  available "$PROVIDER" || die "provider '$PROVIDER' not available — $(requirement_hint "$PROVIDER")"

  PROMPT_RAW="$PROMPT"
  local frag; frag="$(style_fragment)"
  [ -n "$frag" ] && PROMPT="$PROMPT $frag"
  [ -n "${TRANSPARENT:-}" ] && PROMPT="$PROMPT The subject must be isolated and centered on a pure solid white #FFFFFF background with no shadows, no reflections, and nothing else in the frame."

  local n="${VARIANTS:-1}"
  case "$n" in ''|*[!0-9]*) die "--variants must be a number" ;; esac
  [ "$n" -ge 1 ] && [ "$n" -le 8 ] || die "--variants must be between 1 and 8"
  [ "$n" -gt 1 ] && [ "$PROVIDER" = "codex" ] && log "warning: $n variants via codex will be slow (a full agent run each)"

  mkdir -p "$(dirname "$OUTPUT")"
  log "provider: $PROVIDER"
  local orig_output="$OUTPUT" idx=1 final
  while [ "$idx" -le "$n" ]; do
    OUTPUT="$orig_output"
    [ "$n" -gt 1 ] && OUTPUT="${orig_output%.*}-$idx.${orig_output##*.}"
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
    final="$(post_process "$OUTPUT")"
    record_history generate "$final"
    printf 'OK %s %s (%s bytes)\n' "$PROVIDER" "$final" "$(wc -c < "$final" | tr -d ' ')"
    idx=$((idx + 1))
  done
}

# ---------------------------------------------------------------------------
# placeholder command
# ---------------------------------------------------------------------------
cmd_placeholder() {
  [ -n "$OUTPUT" ] || die "--output is required for placeholder"
  apply_preset
  local pargs=(placeholder "$OUTPUT" --size "${SIZE:-1024x1024}")
  [ -n "$LABEL" ] && pargs=("${pargs[@]}" --label "$LABEL")
  mkdir -p "$(dirname "$OUTPUT")"
  python3 "$POSTPROCESS" "${pargs[@]}" >&2
  PROMPT_RAW="$PROMPT"
  PROVIDER=""
  record_history placeholder "$OUTPUT"
  printf 'OK placeholder %s\n' "$OUTPUT"
}

# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------
CMD="${1:-}"
[ -n "$CMD" ] && shift || true

HIST_N=10
if [ "$CMD" = "history" ] && [ $# -gt 0 ]; then
  case "$1" in *[!0-9]*) ;; *) HIST_N="$1"; shift ;; esac
fi

PROMPT="" PROMPT_RAW="" OUTPUT="" SIZE="" ASPECT="" QUALITY="" MODEL=""
PRESET="" STYLE="" TRANSPARENT="" FORMAT="" MAX_WIDTH="" CROP="" VARIANTS="" LABEL="" FAVICON_SET=""
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
    --preset)      PRESET="$2"; shift 2 ;;
    --style)       STYLE="$2"; shift 2 ;;
    --transparent) TRANSPARENT=1; shift ;;
    --format)      FORMAT="$2"; shift 2 ;;
    --max-width)   MAX_WIDTH="$2"; shift 2 ;;
    --crop)        CROP="$2"; shift 2 ;;
    --variants)    VARIANTS="$2"; shift 2 ;;
    --label)       LABEL="$2"; shift 2 ;;
    --input|-i)    INPUTS[${#INPUTS[@]}]="$2"; shift 2 ;;
    -h|--help)     sed -n '2,17p' "$0"; exit 0 ;;
    *)             die "unknown option: $1 (see --help)" ;;
  esac
done

case "$CMD" in
  detect|providers) cmd_detect ;;
  generate|edit)    cmd_generate ;;
  placeholder)      cmd_placeholder ;;
  history)          cmd_history ;;
  ""|-h|--help)     sed -n '2,17p' "$0" ;;
  *)                die "unknown command: $CMD (use: detect | generate | placeholder | history)" ;;
esac
