#!/usr/bin/env bash
# pattern-marker-gate.sh — Stop hook (enforcement, not prose)
# ---------------------------------------------------------------------------
# WHY: Audited control-plane turns fire tools INVISIBLY (failure mode F2) — the
# reply never states which workflow PATTERN it ran, so misses are unauditable; and
# the verification gate is easy to skip, so "done/shipped" gets ASSERTED rather
# than being the output of a check that actually ran.
#
# Applies the "Building Effective Agents" patterns: choose + NAME the workflow
# pattern up front as a discrete, visible decision — router (classify -> handler),
# orchestrator-workers (decompose -> delegate -> synthesize), evaluator-optimizer
# (generate -> check against a gate -> loop), prompt-chaining. "Think like your
# agent" = state which pattern you're running.
#
# HOW (same salience mechanism that fixed F1 via build-intent-reminder.sh, now
# at the Stop boundary so it's GATEABLE, not just suggestable): when a turn
# finishes, scan what the assistant just produced. If the turn was non-trivial
# (it took ANY action — used a tool, routed, gated, or claimed work done/shipped)
# but the reply contains NO pattern marker [route -> X] / [orchestrate -> X] /
# [evaluate -> X] / [chain -> X] / [build-intent -> skill: X], BLOCK the stop and
# make the model re-emit its closing line with the pattern named. A "done /
# shipped / fixed / verified / complete" claim WITHOUT an [evaluate -> ...] marker
# is treated as a missing verification gate and is likewise blocked — turning the
# evaluator-optimizer pattern into the enforced verification gate ("done" = the
# output of a check that ran, never a bare assertion).
#
# Self-gating: pure conversational turns that took no action and made no done-claim
# pass straight through (no marker required) — false-positive cost is one extra
# closing line; false-negative cost is an invisible miss, so we err toward asking.
# Loop-safe: if the LAST stop was already blocked by this hook, let it through.
# ---------------------------------------------------------------------------

input=$(cat)

# --- parse the hook payload -------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)
  stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
else
  transcript=$(printf '%s' "$input" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("transcript_path",""))' 2>/dev/null)
  stop_active=$(printf '%s' "$input" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(str(d.get("stop_hook_active",False)).lower())' 2>/dev/null)
fi

# Loop guard: never block twice in a row (Stop hooks can re-fire).
if [ "$stop_active" = "true" ]; then exit 0; fi
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# --- pull the text of the assistant's most recent turn ----------------------
# Transcript is JSONL; take assistant text emitted AFTER the last user message,
# plus the tool_use names in that span (to detect "took action").
IFS=$'\t' read -r last_assistant_text used_tool verif last_user_text <<EOF
$(python3 - "$transcript" <<'PY'
import sys, json, re
path = sys.argv[1]
rows = []
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try: rows.append(json.loads(line))
                except Exception: pass
except Exception:
    # 4 fields => 3 tabs; fail open with empty values
    print("\t\t\t"); sys.exit(0)

# find index of last user message
last_user = -1
for i, r in enumerate(rows):
    if r.get("type") == "user" or r.get("role") == "user":
        last_user = i

# --- extract the LAST user message's text ---------------------------------
def extract_text(r):
    parts = []
    try:
        msg = r.get("message", r)
        content = msg.get("content", "")
        if isinstance(content, str):
            parts.append(content)
        elif isinstance(content, list):
            for b in content:
                if isinstance(b, dict) and b.get("type") == "text":
                    parts.append(b.get("text", ""))
                elif isinstance(b, str):
                    parts.append(b)
    except Exception:
        pass
    return " ".join(parts)

last_user_msg = ""
if last_user >= 0:
    try:
        last_user_msg = extract_text(rows[last_user])
    except Exception:
        last_user_msg = ""
last_user_msg = (last_user_msg or "").lower().replace("\n", " ").replace("\t", " ")
last_user_msg = re.sub(r"\s+", " ", last_user_msg).strip()[:200]

# --- verification-evidence detection in the assistant span ----------------
# Bash commands that count as a real check, plus spun-out workers that may have
# verified on our behalf (Task/Agent/Workflow tool calls).
VERIF_CMD = re.compile(
    r"\b(test|pytest|jest|vitest|go test|build|tsc|lint|eslint|curl|git diff|playwright|verify)\b",
    re.IGNORECASE,
)
VERIF_TOOLS = {"task", "agent", "workflow"}

texts, used, verif = [], "no", "no"
for r in rows[last_user+1:]:
    if r.get("type") == "assistant" or r.get("role") == "assistant":
        msg = r.get("message", r)
        content = msg.get("content", "")
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            for b in content:
                if not isinstance(b, dict): continue
                if b.get("type") == "text": texts.append(b.get("text",""))
                if b.get("type") == "tool_use":
                    used = "yes"
                    name = str(b.get("name", "") or "")
                    # spun-out worker may have verified
                    if name.strip().lower() in VERIF_TOOLS:
                        verif = "yes"
                    # Bash with a verification-shaped command
                    if name.strip().lower() == "bash":
                        ti = b.get("input", {}) or {}
                        cmd = ""
                        if isinstance(ti, dict):
                            cmd = str(ti.get("command", "") or "")
                        if VERIF_CMD.search(cmd):
                            verif = "yes"

# collapse to one line for the shell read
joined = " ".join(texts).replace("\n", " ").replace("\t", " ")
print(joined + "\t" + used + "\t" + verif + "\t" + last_user_msg)
PY
)
EOF

txt=$(printf '%s' "$last_assistant_text" | tr '[:upper:]' '[:lower:]')

# --- detection --------------------------------------------------------------
# A pattern marker of the expected shape was emitted.
has_marker=$(printf '%s' "$txt" | grep -qE '\[(route|orchestrate|evaluate|chain|build-intent)[^]]*->' && echo yes || echo no)

# Turn took an ACTION worth auditing: used a tool, OR routed/gated/dispatched.
took_action="no"
[ "$used_tool" = "yes" ] && took_action="yes"
printf '%s' "$txt" | grep -qE 'rout(e|ed|ing)|dispatch|spin( |-)?out|hand(ed|ing)? off|conven|escalat|delegat|gate' && took_action="yes"

# Turn claims completion — this is the evaluator-optimizer trigger.
claims_done=$(printf '%s' "$txt" | grep -qE 'verified by:|now live|shipped|it.?s (done|fixed|working|live)|task (is )?(done|complete)|all (tests )?pass|merged|deployed|completed|is (done|fixed|complete|live)|(^| )verified' && echo yes || echo no)
# Did it actually name the evaluate/verification pattern for that claim?
has_eval=$(printf '%s' "$txt" | grep -qE '\[evaluate[^]]*->|verification-before-completion' && echo yes || echo no)

# --- decide -----------------------------------------------------------------
block() {
  reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  else
    printf '{"decision":"block","reason":"%s"}' "$reason"
  fi
  exit 0
}

# Gate 1 (evaluator-optimizer / verification): a done-claim with NO verification
# marker AND no real execution-evidence this turn (evidence loosens the gate).
if [ "$claims_done" = "yes" ] && [ "$has_eval" = "no" ] && [ "$verif" = "no" ]; then
  block "VERIFICATION GATE (Stop hook): this turn claims work is done/shipped/fixed but ran NO visible verification pattern. 'Done' must be the OUTPUT of a check, not an assertion (evaluator-optimizer). Before you stop: invoke verification-before-completion (or confirm the spun-out worker's gate ran green), then re-state your closing line with the marker [evaluate -> verification-before-completion] and a real 'Verified by: <what ran + result>'. If nothing was actually verified, say so plainly instead of claiming done. Also report in plain language and end with a 'Skipped/Failed:' line."
fi

# Gate 2 (F2 / name-the-pattern): an action-taking turn with no pattern marker.
if [ "$took_action" = "yes" ] && [ "$has_marker" = "no" ]; then
  block "PATTERN-MARKER GATE (Stop hook): this turn took action (tool/route/gate) without naming the workflow PATTERN, so the tool use is invisible/unauditable (failure mode F2). Per 'Building Effective Agents', naming the pattern is a discrete, visible decision. Add ONE opening marker naming the pattern AND the skill/agent, then stop again: [route -> <persona/skill>] (classify->handler) | [orchestrate -> N workers, synthesize] (decompose->delegate->synthesize) | [evaluate -> verification-before-completion] (generate->gate->loop) | [chain -> step1 then step2] | [build-intent -> skill: <name>] (build/debug/design). Pure conversation that took no action needs no marker."
fi

# --- Gate 3 (re-ask gate) ---------------------------------------------------
# Block iff the user gave a SHORT clear order last turn AND the assistant handed
# it back as a question / A-B menu AND no genuinely-new hard gate was raised.
# FAIL OPEN: empty/unparseable last_user => skip entirely.
lu=$(printf '%s' "$last_user_text" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
if [ -n "$lu" ]; then
  # (a) short clear order?
  short_order="no"
  # whole-message single affirmations (optional trailing period)
  if printf '%s' "$lu" | grep -qiE '^(yes|yep|ok|okay|do it|go|go ahead|proceed|approved|ship it|ship|merge it|merge|b|a|confirmed)\.?$'; then
    short_order="yes"
  fi
  # OR <= 4 words AND contains an explicit go-token
  word_count=$(printf '%s\n' "$lu" | tr -s '[:space:]' ' ' | wc -w | tr -d ' ')
  if [ "${word_count:-99}" -le 4 ] && printf '%s' "$lu" | grep -qiE 'approved|ship it|do it|go ahead|merge it|proceed'; then
    short_order="yes"
  fi

  # (b) assistant turn ends with a question OR contains an A/B menu token?
  asks_back="no"
  ltxt_trimmed=$(printf '%s' "$txt" | sed -E 's/[[:space:]]+$//')
  case "$ltxt_trimmed" in
    *\?) asks_back="yes" ;;
  esac
  if printf '%s' "$txt" | grep -qiE 'a/b|option a|which (one|do you)|should i|or merge now|pick one'; then
    asks_back="yes"
  fi

  # (c) a genuinely-new hard gate / real escalation is ALLOWED (do not block).
  real_escalation="no"
  if printf '%s' "$txt" | grep -qiE 'new gate|spends money|irreversible|publish|live data'; then
    real_escalation="yes"
  fi

  if [ "$short_order" = "yes" ] && [ "$asks_back" = "yes" ] && [ "$real_escalation" = "no" ]; then
    block "RE-ASK GATE: you gave a clear order last turn; a resolved decision earns ZERO follow-up questions. Execute it now — if a safety check is unrun, run it silently or execute and note it in ONE line. Do not hand the order back as a menu."
  fi
fi

exit 0
