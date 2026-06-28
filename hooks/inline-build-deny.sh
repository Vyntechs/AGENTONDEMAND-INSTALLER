#!/usr/bin/env bash
# inline-build-deny.sh — PreToolUse hook (matched on Edit|Write), HARD-DENY
# ---------------------------------------------------------------------------
# WHY: the control plane is a director, not a builder. When a build/implement
# phase is "armed" (state/armed-<session_id> exists), implementation MUST be spun
# out to a fresh-context subagent or the Workflow tool — NEVER ground inline in
# this control-plane window (failure modes F1 build-turn raw grinding, F3
# director->builder drift). This hook is the MECHANICAL boundary behind "direct,
# don't build": while armed, any Edit/Write to a real SOURCE file is DENIED, so
# the only way to implement is to hand the approved plan off. Editing
# plans/notes/.md/config stays allowed so the control plane can still think out
# loud and tune its own guardrails.
#
# FAIL OPEN — HARD RULE: any parse failure, missing field, or unexpected input
# results in ALLOW (exit 0, no output). A false block across every session is a
# disaster; a missed block is merely a soft miss. We err toward permissive.
#   - Not armed (no flag file)            -> ALLOW
#   - session_id missing                  -> treated as NOT armed -> ALLOW
#   - file_path missing/empty             -> ALLOW
#   - file_path is .md/.markdown/.txt     -> ALLOW (plans/notes/docs)
#   - path contains /memory/|/tasks/|/notes/|HANDOFF -> ALLOW
#   - path is under /.claude/ config (settings.json or the hooks dir) -> ALLOW
#     (never block edits to the guardrail config itself)
#   - malformed JSON / any error          -> ALLOW
#   - else (armed + a real source file)   -> DENY
# ---------------------------------------------------------------------------

# Read stdin; never let an empty/odd payload cause a non-zero exit.
input=$(cat 2>/dev/null) || exit 0

# --- parse the hook payload (jq if present, else python3); fail open ---------
tool_name=""
file_path=""
session_id=""
agent_id=""    # present + non-empty ONLY when the call comes from a subagent
agent_type=""  # ditto — the spun-out worker the gate is meant to ALLOW
if command -v jq >/dev/null 2>&1; then
  tool_name=$(printf '%s' "$input"  | jq -r '.tool_name // ""'            2>/dev/null) || tool_name=""
  file_path=$(printf '%s' "$input"  | jq -r '.tool_input.file_path // ""' 2>/dev/null) || file_path=""
  session_id=$(printf '%s' "$input" | jq -r '.session_id // ""'          2>/dev/null) || session_id=""
  agent_id=$(printf '%s' "$input"   | jq -r '.agent_id // ""'            2>/dev/null) || agent_id=""
  agent_type=$(printf '%s' "$input" | jq -r '.agent_type // ""'          2>/dev/null) || agent_type=""
else
  tool_name=$(printf '%s' "$input"  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_name",""))'                      2>/dev/null) || tool_name=""
  file_path=$(printf '%s' "$input"  | python3 -c 'import sys,json;print((json.load(sys.stdin).get("tool_input") or {}).get("file_path",""))' 2>/dev/null) || file_path=""
  session_id=$(printf '%s' "$input" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("session_id",""))'                    2>/dev/null) || session_id=""
  agent_id=$(printf '%s' "$input"   | python3 -c 'import sys,json;print(json.load(sys.stdin).get("agent_id",""))'                      2>/dev/null) || agent_id=""
  agent_type=$(printf '%s' "$input" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("agent_type",""))'                    2>/dev/null) || agent_type=""
fi

# jq prints the literal "null" string in some odd shapes — normalize to empty.
[ "$tool_name" = "null" ]  && tool_name=""
[ "$file_path" = "null" ]  && file_path=""
[ "$session_id" = "null" ] && session_id=""
[ "$agent_id" = "null" ]   && agent_id=""
[ "$agent_type" = "null" ] && agent_type=""

# --- ALLOW gate 0: the call comes from a SPUN-OUT SUBAGENT => ALLOW ----------
# ROOT-CAUSE FIX: subagent tool calls execute under the PARENT session_id, so
# keying the gate on session_id alone makes an armed control plane also block its
# own spun-out workers — the exact opposite of intent (the worker IS where
# building is supposed to happen). The payload distinguishes them: a subagent call
# carries a non-empty `agent_id`/`agent_type`; the main control-plane session does
# not. When this is a subagent, ALLOW unconditionally — spinning the build out is
# precisely what the gate wants. The gate still blocks the control plane's OWN
# inline edits (no agent_id) below.
[ -n "$agent_id" ] && exit 0
[ -n "$agent_type" ] && exit 0

# --- ALLOW gate 1: no session id => cannot be armed => fail open ------------
[ -z "$session_id" ] && exit 0

# --- ALLOW gate 2: not armed (flag file absent) => fail open ----------------
armed_flag="$HOME/.claude/hooks/state/armed-${session_id}"
[ -f "$armed_flag" ] || exit 0

# --- ALLOW gate 3: no file_path to evaluate => fail open --------------------
[ -z "$file_path" ] && exit 0

# --- ALLOW gate 4: allowed (non-source) paths ------------------------------
# Docs/plans/notes by extension or directory, and the guardrail config itself.
# Case-insensitive on the path so e.g. .MD / Handoff also pass.
lc_path=$(printf '%s' "$file_path" | tr '[:upper:]' '[:lower:]')
case "$lc_path" in
  *.md|*.markdown|*.txt) exit 0 ;;                 # docs / plans / notes
  */memory/*|*/tasks/*|*/notes/*) exit 0 ;;        # working-memory dirs
  *handoff*) exit 0 ;;                              # HANDOFF.md and kin
  */.claude/*) exit 0 ;;                           # never block guardrail config
  *settings.json|*settings.local.json) exit 0 ;;   # settings live config
esac

# --- DENY: armed + a real source file --------------------------------------
reason='INLINE-BUILD GATE: a build/implement phase is armed, so implementation must NOT run inline in the control plane. Hand the approved plan to a fresh-context subagent or the Workflow tool and report its done-with-evidence here. (Editing .md/notes/plans is allowed; send any non-build message to clear a stale flag, or say "build inline" to override.)'

if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null && exit 0
fi

# Fallback emitter (no jq): python3, then a hand-rolled JSON as last resort.
python3 - "$reason" <<'PY' 2>/dev/null && exit 0
import sys, json
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.argv[1]}}))
PY

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"INLINE-BUILD GATE: a build/implement phase is armed; spin implementation out to a fresh-context subagent or the Workflow tool instead of editing source inline."}}'
exit 0
