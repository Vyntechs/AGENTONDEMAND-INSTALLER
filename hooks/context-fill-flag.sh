#!/usr/bin/env bash
# context-fill-flag.sh — UserPromptSubmit hook (ADVISORY ONLY — NEVER blocks)
# ---------------------------------------------------------------------------
# WHY: Long sessions drift into the "dumb zone" once the context window fills —
# the model starts dropping earlier facts, repeating itself, and making avoidable
# mistakes. You have no token gauge in front of you, so it's easy to keep pushing
# a saturated session instead of /save -> /clear. This hook injects ONE salient
# line, escalating with fullness, recommending the save/clear cycle BEFORE the
# next epic. Enforcement-by-salience, not prose.
#
# CONTRACT: UserPromptSubmit. stdin = JSON {prompt, session_id, transcript_path,
# ...}. Anything we print to stdout is injected as context for this turn. We
# print AT MOST one short advisory line; we NEVER deny, NEVER block, ALWAYS
# exit 0. A failing UserPromptSubmit hook can block the prompt, so every step is
# guarded and the default on ANY error / missing signal is SILENT exit 0.
#
# THE SIGNAL PROBLEM: a UserPromptSubmit payload does NOT reliably carry a live
# token count. So we look for a usable signal in this priority order:
#   1) An explicit usage/token field in the payload, if one is ever present
#      (we probe several plausible field names; future-proofing, harmless if
#      absent).
#   2) Else, the BYTE SIZE of the transcript file at transcript_path, used as a
#      proxy for how full the context window is.
#   3) Else (no usable signal at all): exit 0 SILENT. We never guess loudly.
#
# BYTES->FULLNESS HEURISTIC (documented, deliberately conservative):
#   The session transcript is JSONL on disk and accumulates the running
#   conversation. We anchor a FULL (~100%) window at 8 MiB of transcript:
#       FULL_BYTES = 8 * 1024 * 1024 = 8388608
#       fullness% = transcript_bytes * 100 / FULL_BYTES   (capped 0..100)
#   Rationale / calibration: assuming a ~1M-token context window and that on-disk
#   JSONL runs very roughly ~3-4 bytes per live token after JSON overhead, ~3-4M
#   bytes of *live* conversation maps toward a full window; we set the 100% anchor
#   higher (8 MiB) ON PURPOSE so we UNDER-claim fullness rather than nag early —
#   a false "you're full" is annoying, and this hook fires on every prompt. Real
#   observed transcripts: a long-but-fine ~3 MB session reads ~37% (correctly
#   SILENT); warnings only begin past ~4 MiB. Token estimate (when a real usage
#   field exists) assumes a 1,000,000-token window unless the payload also tells
#   us the limit. Tune FULL_BYTES / TOKEN_WINDOW below if your window size differs.
#
# THRESHOLDS (advisory text only — no blocking at any level):
#   <50%   : SILENT
#   50-69% : recommend /save then /clear before the next epic
#   70-84% : STRONGLY recommend /save then /clear soon
#   85%+   : STOP: /save then /clear now; this session is in the dumb zone
# ---------------------------------------------------------------------------

# Fail open no matter what: if anything below explodes, we still exit 0 silently.
{
  input=$(cat 2>/dev/null) || input=""

  # --- tunables -------------------------------------------------------------
  FULL_BYTES=8388608      # 8 MiB transcript ~= 100% full (see heuristic above)
  TOKEN_WINDOW=1000000    # assumed ~1M-token window if a real token count appears

  # --- helper: extract a field via jq, else python3, else empty -------------
  get_field() {
    # $1 = jq filter, $2 = python expression returning the value
    local val=""
    if command -v jq >/dev/null 2>&1; then
      val=$(printf '%s' "$input" | jq -r "$1" 2>/dev/null)
    fi
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      if command -v python3 >/dev/null 2>&1; then
        val=$(printf '%s' "$input" | python3 -c "$2" 2>/dev/null)
      fi
    fi
    [ "$val" = "null" ] && val=""
    printf '%s' "$val"
  }

  # --- 1) try an explicit usage/token signal first --------------------------
  # We probe several plausible nestings; ALL are optional and absent today.
  # If found, interpret as live tokens used against TOKEN_WINDOW.
  tokens=$(get_field \
    '(.usage.total_tokens // .usage.input_tokens // .total_tokens // .token_count // .context.used_tokens // empty) | numbers' \
    'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
def first(*keys):
    cur=d
    for k in keys:
        if isinstance(cur,dict) and k in cur:
            cur=cur[k]
        else:
            return None
    return cur
for path in (("usage","total_tokens"),("usage","input_tokens"),("total_tokens",),("token_count",),("context","used_tokens")):
    v=first(*path)
    if isinstance(v,(int,float)):
        print(int(v)); break')

  pct=""

  if printf '%s' "$tokens" | grep -qE '^[0-9]+$' && [ "$tokens" -gt 0 ] 2>/dev/null; then
    # We have a real token count. Optionally honor an explicit window limit.
    limit=$(get_field \
      '(.usage.context_window // .context.window // .context_limit // empty) | numbers' \
      'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
def first(*keys):
    cur=d
    for k in keys:
        if isinstance(cur,dict) and k in cur:
            cur=cur[k]
        else:
            return None
    return cur
for path in (("usage","context_window"),("context","window"),("context_limit",)):
    v=first(*path)
    if isinstance(v,(int,float)) and v>0:
        print(int(v)); break')
    if ! printf '%s' "$limit" | grep -qE '^[0-9]+$' || [ "${limit:-0}" -le 0 ] 2>/dev/null; then
      limit=$TOKEN_WINDOW
    fi
    pct=$(( tokens * 100 / limit ))
  else
    # --- 2) fall back to transcript byte size as a fullness proxy -----------
    transcript=$(get_field \
      '.transcript_path // ""' \
      'import sys,json
try:
    print(json.load(sys.stdin).get("transcript_path","") or "")
except Exception:
    pass')
    if [ -n "$transcript" ] && [ -f "$transcript" ]; then
      bytes=$(stat -f '%z' "$transcript" 2>/dev/null || stat -c '%s' "$transcript" 2>/dev/null || echo "")
      if printf '%s' "$bytes" | grep -qE '^[0-9]+$'; then
        pct=$(( bytes * 100 / FULL_BYTES ))
      fi
    fi
  fi

  # --- 3) no usable signal -> SILENT (never guess loudly) -------------------
  if [ -z "$pct" ]; then exit 0; fi

  # Cap into 0..100 for clean display.
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100

  # --- emit the single advisory line by band (never blocks) -----------------
  if [ "$pct" -ge 85 ] 2>/dev/null; then
    printf '[context ~%s%% full — STOP: /save then /clear now; this session is in the dumb zone]\n' "$pct"
  elif [ "$pct" -ge 70 ] 2>/dev/null; then
    printf '[context ~%s%% full — STRONGLY recommend /save then /clear soon]\n' "$pct"
  elif [ "$pct" -ge 50 ] 2>/dev/null; then
    printf '[context ~%s%% full — recommend /save then /clear before the next epic]\n' "$pct"
  fi
  # else: below 50% -> SILENT

} 2>/dev/null

exit 0
