#!/usr/bin/env bash
# dispatch-gate.sh — PreToolUse hook (enforcement, not prose)
# matcher: Task|Agent  (the subagent/worker dispatch tools)
# ---------------------------------------------------------------------------
# WHY: A spun-out worker cannot see your conversation. If its brief carries no
# OBSERVABLE acceptance check, the worker reports back "done" as a bare assertion
# (the exact failure the verification rule forbids: "the spec is not complete
# until it answers: how will we know it worked?"). This gate makes that contract
# structural: a dispatch brief MUST contain an acceptance signal (a DONE-WHEN /
# VERIFY-BY) so the worker self-verifies before reporting.
#
# HOW: Read the PreToolUse payload. Extract the dispatch prompt text (the Task/
# Agent `prompt` field; fall back to scanning every string field of tool_input).
# If that text contains ANY acceptance signal -> ALLOW. If it has substantive
# text but NO acceptance signal -> DENY with a fix-forward reason. If we cannot
# find any prompt text at all (or anything goes wrong) -> ALLOW.
#
# FAIL OPEN, ALWAYS: any parse failure, missing field, unexpected shape, or
# empty extraction results in exit 0 with no deny. This hook can only ever ADD a
# requirement to a brief that already has plenty of text but forgot the check;
# it must never be the reason legitimate work is blocked on error.
# ---------------------------------------------------------------------------

# Read stdin; never let an empty/odd read abort us.
input=$(cat 2>/dev/null) || exit 0
[ -z "$input" ] && exit 0

# --- extract tool_name + the dispatch prompt text ---------------------------
# We pull two things:
#   tool_name        — to confirm this is a dispatch tool (advisory; matcher
#                      already scopes us, but we re-check defensively)
#   prompt_text      — tool_input.prompt if present, else ALL string values
#                      anywhere in tool_input (recursively), joined.
# Prefer python3 (robust recursive walk); fall back to jq; on any failure the
# variables stay empty and we ALLOW.
tool_name=""
prompt_text=""

if command -v python3 >/dev/null 2>&1; then
  # NOTE: the JSON payload arrives on stdin, so the python SCRIPT must NOT also
  # come from stdin (a heredoc into `python3 -` would clobber the piped JSON).
  # We pass the script via `python3 -c` and let stdin stay the payload.
  parsed=$(printf '%s' "$input" | python3 -c '
import sys, json

def walk_strings(node, out):
    # Collect every string value found anywhere under node.
    if isinstance(node, str):
        out.append(node)
    elif isinstance(node, dict):
        for v in node.values():
            walk_strings(v, out)
    elif isinstance(node, list):
        for v in node:
            walk_strings(v, out)

try:
    raw = sys.stdin.read()
    d = json.loads(raw)
except Exception:
    # Unparseable -> emit nothing -> caller fails open (ALLOW).
    sys.exit(0)

if not isinstance(d, dict):
    sys.exit(0)

tool_name = d.get("tool_name", "")
if not isinstance(tool_name, str):
    tool_name = ""

ti = d.get("tool_input", {})
if not isinstance(ti, dict):
    ti = {}

texts = []
# Primary: the explicit prompt field used by Agent/Task dispatch.
p = ti.get("prompt", "")
if isinstance(p, str) and p.strip():
    texts.append(p)
else:
    # Fallback: scan every string value in tool_input.
    walk_strings(ti, texts)

prompt_text = " ".join(t for t in texts if isinstance(t, str))

# Line 1: tool_name (single line). Line 2+: prompt text (newlines flattened).
print(tool_name.replace("\n", " ").replace("\r", " "))
print(prompt_text.replace("\n", " ").replace("\r", " "))
' 2>/dev/null)
  # First line = tool_name; the rest = prompt_text.
  tool_name=$(printf '%s' "$parsed" | sed -n '1p')
  prompt_text=$(printf '%s' "$parsed" | sed -n '2,$p')
elif command -v jq >/dev/null 2>&1; then
  tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
  # Prefer .tool_input.prompt; else flatten all string leaves of tool_input.
  prompt_text=$(printf '%s' "$input" | jq -r '
    if (.tool_input.prompt // "") != "" then .tool_input.prompt
    else [ .tool_input | .. | strings ] | join(" ")
    end' 2>/dev/null)
fi

# --- FAIL OPEN: no prompt text found at all -> ALLOW ------------------------
# (covers malformed JSON, missing tool_input, missing/empty prompt, parser crash)
prompt_trimmed=$(printf '%s' "$prompt_text" | tr -d '[:space:]')
[ -z "$prompt_trimmed" ] && exit 0

# --- acceptance-signal detection (case-insensitive) -------------------------
# Any of these phrases means the brief already states how done is observed.
# FAIL OPEN if our own tooling is missing/broken: if grep isn't available we
# cannot prove the brief lacks a check, so we must ALLOW (never block on our bug).
command -v grep >/dev/null 2>&1 || exit 0

# tr may also be absent on a broken PATH; if so, skip lowercasing (grep -i below
# already makes the match case-insensitive, so detection still works).
if command -v tr >/dev/null 2>&1; then
  lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
else
  lower="$prompt_text"
fi

# grep exit codes: 0 = matched (ALLOW), 1 = ran-and-no-match (proceed to DENY),
# >1 = grep ERROR. On error we FAIL OPEN (ALLOW) rather than risk a false deny.
printf '%s' "$lower" | grep -iqE 'done[ _-]?when|verify[ _-]?by|verified[ _-]?by|acceptance|verification step|verification command|success criteria|expected (output|result)|must pass|self[ _-]?test|test:'
grep_rc=$?
if [ "$grep_rc" -eq 0 ]; then
  exit 0   # ALLOW: brief carries an observable acceptance check.
elif [ "$grep_rc" -gt 1 ]; then
  exit 0   # ALLOW: grep errored — fail open, never block on our own failure.
fi
# grep_rc == 1 -> ran cleanly, found no acceptance signal -> fall through to DENY.

# --- DENY: substantive brief with no acceptance check -----------------------
reason='DISPATCH GATE: this worker brief has no observable acceptance check. Add a DONE-WHEN (what observable state = done) and a VERIFY-BY (the exact check the worker must run before reporting back), then re-dispatch.'

if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
elif command -v python3 >/dev/null 2>&1; then
  printf '%s' "$reason" | python3 -c 'import sys,json; r=sys.stdin.read(); print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":r}}))' 2>/dev/null \
    || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"DISPATCH GATE: this worker brief has no observable acceptance check. Add a DONE-WHEN and a VERIFY-BY, then re-dispatch."}}'
else
  # Last resort: hand-rolled JSON with the canonical (no-special-char) reason.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"DISPATCH GATE: this worker brief has no observable acceptance check. Add a DONE-WHEN and a VERIFY-BY, then re-dispatch."}}'
fi
exit 0
