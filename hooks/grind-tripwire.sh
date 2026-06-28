#!/usr/bin/env bash
# grind-tripwire.sh — PostToolUse hook (matched on Edit|Write|Bash). ADVISORY ONLY.
# ---------------------------------------------------------------------------
# WHY: Audited control-plane sessions DRIFT from directing into building — they
# grind inline (edit after edit, build/test loop after loop) instead of spinning
# the work into a fresh-context subagent/Workflow. build-intent-reminder.sh nudges
# at prompt time and pattern-marker-gate.sh gates the Stop; this is the MIDDLE: a
# running counter that, after enough BUILD-shaped tool calls in one session, tells
# the model (and once, you) "you are building, not directing — spin out."
#
# HOW: count BUILD-shaped calls per session in a counter file keyed by session_id.
# BUILD-shaped = Edit | Write, OR a Bash command that MUTATES/ITERATES (install,
# test, build, migrate, deploy, in-place edit, redirection). Read-only recon
# (cat/grep/ls/git status/git diff/git log/find/head/tail/echo/pwd/which) does
# NOT count — that is legitimate directing/inspection. Stay SILENT below 5; warn
# ONCE at exactly 5 (model-facing); warn STRONGER + plain-language note for you
# at exactly 10 (2x); SILENT above 10 (never nag repeatedly).
#
# HARD RULE: this hook NEVER blocks and ALWAYS exits 0. Any parse failure, missing
# field, or unexpected input fails OPEN (silent, exit 0). It only PRINTS advisory
# text (PostToolUse stdout = injected context) — it has no deny path at all.
# ---------------------------------------------------------------------------

# Fail open no matter what: if anything below explodes, still exit 0 silently.
input=$(cat 2>/dev/null) || exit 0

STATE_DIR="$HOME/.claude/hooks/state"

# --- parse the hook payload (jq if present, else python3; either may be absent) ---
tool_name=""
session_id=""
cmd=""
if command -v jq >/dev/null 2>&1; then
  tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
  session_id=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  tool_name=$(printf '%s' "$input" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get("tool_name","") or "")
except Exception:
    print("")' 2>/dev/null)
  session_id=$(printf '%s' "$input" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get("session_id","") or "")
except Exception:
    print("")' 2>/dev/null)
  cmd=$(printf '%s' "$input" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    ti=d.get("tool_input",{}) or {}
    print(ti.get("command","") or "")
except Exception:
    print("")' 2>/dev/null)
fi

# Constant fallback when session_id is absent — still works, never leaks a crash.
[ -z "$session_id" ] && session_id="no-session"
# Sanitize session_id for use in a filename (defensive — strip path separators etc).
safe_sid=$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9._-' '_')
[ -z "$safe_sid" ] && safe_sid="no-session"

counter_file="$STATE_DIR/grind-$safe_sid"

# Ensure the state dir exists; if we can't make it, fail open (silent, exit 0).
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# --- decide whether THIS call is BUILD-shaped -------------------------------
build_shaped="no"
case "$tool_name" in
  Edit|Write)
    build_shaped="yes"
    ;;
  Bash)
    # MUTATING / ITERATING patterns = building, not directing. Check these FIRST,
    # because a write signal (redirection, in-place edit) makes a command mutating
    # REGARDLESS of its leading verb — e.g. `echo data > out.txt` starts like recon
    # but actually writes a file, so it must count. Mutation wins over the recon
    # allowlist; only if NO mutation signal is present do we consult the recon list.
    if printf '%s' "$cmd" | grep -qE '(npm |pnpm |yarn |cargo |make |pytest|jest|vitest|go test|go build|tsc|migrate|alembic|deploy|docker |sed -i|>[[:space:]]|>>)'; then
      build_shaped="yes"
    # Read-only recon is legitimate directing — never count it. Anchor at the start
    # of the command (optionally after whitespace) so it matches the leading verb.
    elif printf '%s' "$cmd" | grep -qE '^[[:space:]]*(cat|grep|rg|ls|find|head|tail|echo|pwd|which|git[[:space:]]+(status|diff|log))([[:space:]]|$)'; then
      build_shaped="no"
    fi
    ;;
  *)
    # Only Edit|Write|Bash reach here via the matcher; anything else is a no-op.
    build_shaped="no"
    ;;
esac

# Not a build-shaped call → nothing to count, stay silent, exit 0.
if [ "$build_shaped" != "yes" ]; then
  exit 0
fi

# --- increment the per-session counter --------------------------------------
count=0
if [ -f "$counter_file" ]; then
  count=$(cat "$counter_file" 2>/dev/null)
fi
# Coerce to a clean integer; any garbage resets to 0 (fail open / never crash).
case "$count" in
  ''|*[!0-9]*) count=0 ;;
esac
count=$((count + 1))
# Persist; if the write fails we still proceed and fail open on the advisory.
printf '%s' "$count" > "$counter_file" 2>/dev/null

# --- advisory output (ADVISORY ONLY — no block, ever) -----------------------
TRIP_5='GRIND TRIPWIRE: this session has run 5 build-shaped calls inline — you are BUILDING, not directing. Spin the rest into a fresh-context subagent/Workflow, persist state to HANDOFF.md, and return to directing.'
TRIP_10='GRIND TRIPWIRE (2x): this session has now run 10 build-shaped calls inline — you have clearly slid from director to builder. STOP grinding here: hand the remaining work to a fresh-context subagent/Workflow now, persist state to HANDOFF.md, and return to the control plane. Heads up: this session started doing the building itself instead of directing it — handing this work to a separate worker now.'

if [ "$count" -eq 5 ]; then
  printf '%s\n' "$TRIP_5"
elif [ "$count" -eq 10 ]; then
  printf '%s\n' "$TRIP_10"
fi
# Below 5, between 6-9, and above 10: SILENT. Never nag repeatedly.

exit 0
