#!/usr/bin/env bash
# build-intent-reminder.sh — UserPromptSubmit hook
# Purpose: the moment a prompt involves build/debug/design/feature work, inject a
# high-salience reminder (right before the model acts) to fire the matching PROCESS
# SKILL via the Skill tool BEFORE the first raw Bash/Read/Edit/Write — and surface a
# visible [build-intent -> skill: X] marker so you can SEE the gate fired.
# Installed because audited director sessions ground raw on build turns, firing zero
# process skills, invisibly. Enforcement-by-salience, not more buried prose.
# Self-gating: on pure routing/research/conversation turns the model is told to ignore it.
# Graceful degradation: this hook only INJECTS advisory text — it never shells out to a
# skill or plugin, so if no process-skill plugin is installed nothing breaks; the model is
# told to name the work + approach explicitly instead.
#
# PHASE-SPLIT UPGRADE (planner / generator / evaluator separation; research -> plan ->
# implement): When the prompt signals the IMPLEMENT phase (an approved plan is being
# executed / "go build it" / "ship the plan"), inject a SECOND directive: the implement
# phase must run in a FRESH-CONTEXT subagent/Workflow, NEVER inline in this control plane.
# This gives "direct, don't build" a mechanical boundary instead of a willpower test,
# targeting F1 (build-turn raw grinding) and F3 (director->builder drift). The marker
# becomes [build-intent -> skill: X | phase: implement -> SPIN OUT], so the spin-out is
# the enforced default and you can SEE whether the control plane held the line or grabbed
# the keys.

input=$(cat)

# Extract the user's prompt (jq if present, else python3), lowercased for matching.
if command -v jq >/dev/null 2>&1; then
  prompt=$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null)
else
  prompt=$(printf '%s' "$input" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("prompt",""))' 2>/dev/null)
fi
lc=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')

reminder='PROCESS-SKILL GATE (injected by hook): If this turn involves ANY build, debug, design, or feature work, you MUST invoke the matching process skill via the Skill tool BEFORE your first raw Bash/Read/Edit/Write — IF you have a process-skill plugin installed (e.g. brainstorming for a new feature / creative, writing-plans for multi-step work, systematic-debugging for a bug / wrong behavior, test-driven-development when implementing, frontend-design for ANY UI / website / component, verification-before-completion before claiming done). If no such skill exists in your setup, name the work and the approach explicitly instead. Open your reply with the marker [build-intent -> skill: <name>] (or [build-intent -> approach: <name>]) so the gate is visible. If this is pure routing / research / strategy / conversation, ignore this line entirely.'

# Phase-split directive — appended only when implement-phase intent is detected.
phase_split='PHASE-SPLIT GATE (injected by hook): This reads as the IMPLEMENT phase. Per "direct, don'\''t build," the implement phase ALWAYS runs in a FRESH-CONTEXT subagent / Workflow / worktree — NEVER inline in this control-plane window. Do NOT carry research/plan sludge into implementation here. Your move: (1) confirm the plan is approved, (2) hand the plan to a spun-out worker (subagent or Workflow tool) that runs Research+Plan-free with the matching build skill, (3) stay in the control plane and report its done-with-evidence outcome. Extend your opening marker to [build-intent -> skill: <name> | phase: implement -> SPIN OUT]. If you are about to Edit/Write/Bash the implementation in THIS window, STOP — that is the director->builder drift this gate exists to prevent.'

# Broad build/debug/design/feature intent keywords (false positives are harmless —
# the reminder is self-gating; false negatives are the real risk, so keep this wide).
kw='build|rebuild|create|implement|feature|fix |fixing|debug|broken|error|fail|crash|bug|refactor|redesign|design|website|landing|page |component|button|form |modal|layout|style|css|endpoint| api |function|deploy|migrat|integrat|wire up|render|screen|frontend|backend|component|scaffold|spruce|polish|revamp'

# Implement-phase signals: an approved plan is now being EXECUTED (vs. researched/planned).
# Kept tight so research/plan turns DON'T trip it — only the "now go do it" boundary does.
impl_kw='approved|go ahead|go build|build it|ship it|ship the plan|execute the plan|implement the plan|run the plan|start building|start the build|begin implementation|kick off the build|make it so|do it now|now build|now implement|plan is approved|green.?light|proceed with the build|proceed with implementation'

# ---------------------------------------------------------------------------
# ARM/DISARM + advisory routing ADDITIONS (additive; everything below fails open -> exit 0).
# Placed AFTER $kw and $impl_kw are defined so the build-intent reuse is real.
# ---------------------------------------------------------------------------
# Extract session_id (jq if present, else python3) for per-session flag keying.
# Absent/parse-fail -> constant fallback so a stale id never crashes the prompt.
if command -v jq >/dev/null 2>&1; then
  sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
else
  sid=$(printf '%s' "$input" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)
fi
[ -z "$sid" ] && sid="nosession"
# Sanitize sid to a safe filename token (defensive; ids are normally hex/uuid).
sid=$(printf '%s' "$sid" | tr -c 'a-zA-Z0-9._-' '_' 2>/dev/null)
[ -z "$sid" ] && sid="nosession"
state_dir="$HOME/.claude/hooks/state"
armed_flag="$state_dir/armed-$sid"

# Override tokens: caller explicitly opts into inline building -> never arm.
override_kw='build inline|edit here|inline is fine'
# Disarm tokens: non-build / context-boundary signals -> clear the flag so stale
# flags self-heal next turn (clear-by-default).
disarm_kw='build inline|stop|done|clear|/clear|new task'

# ARM / DISARM the inline-build-deny gate. Guarded so any failure is a no-op.
# Build intent reuses the existing $kw OR $impl_kw (impl phase is build intent
# without a noun). Stderr swallowed; this block can never crash the hook.
{
  mkdir -p "$state_dir" 2>/dev/null
  is_build=0
  if printf '%s' "$lc" | grep -qE "$kw" 2>/dev/null; then is_build=1; fi
  if printf '%s' "$lc" | grep -qE "$impl_kw" 2>/dev/null; then is_build=1; fi
  has_override=0
  if printf '%s' "$lc" | grep -qE "$override_kw" 2>/dev/null; then has_override=1; fi
  has_disarm=0
  if printf '%s' "$lc" | grep -qE "$disarm_kw" 2>/dev/null; then has_disarm=1; fi

  if [ "$is_build" = "1" ] && [ "$has_override" = "0" ] && [ "$has_disarm" = "0" ]; then
    touch "$armed_flag" 2>/dev/null   # ARM the inline-build-deny gate
  else
    rm -f "$armed_flag" 2>/dev/null   # DISARM / clear stale flag (default)
  fi
} 2>/dev/null

# Advisory routing nudges appended to whatever context we already inject.
# Each line is terse, advisory-only, self-gating. Built defensively so any failure
# yields an empty suffix (no extra text) rather than crashing the prompt.
route_suffix=""
{
  fanout_kw='parallel|dispatch|convene|personas|both agents|fan out|panel'
  heavy_kw='convene the team|all personas|the panel|big workflow'

  if printf '%s' "$lc" | grep -qE "$fanout_kw" 2>/dev/null; then
    route_suffix="$route_suffix [single-writer] partition into tasks with ZERO shared files — one named owner per artifact; advisors run in parallel, ONE writer converges; bring back one artifact, not a menu."
  fi
  # Mechanism ladder — ALWAYS appended.
  route_suffix="$route_suffix [mechanism-ladder] default to the cheapest rung that fits — answer inline / one skill / one subagent / panel-or-Workflow; climb only with a one-line reason."
  if printf '%s' "$lc" | grep -qE "$heavy_kw" 2>/dev/null; then
    route_suffix="$route_suffix [justify] state one line of why a panel/Workflow is needed before convening."
  fi
  # Build/implement intent -> skill-before-agent nudge.
  if printf '%s' "$lc" | grep -qE "$kw" 2>/dev/null || printf '%s' "$lc" | grep -qE "$impl_kw" 2>/dev/null; then
    route_suffix="$route_suffix [skill-before-agent] reach for the matching native skill before any build-crew agent; dispatch an agent only if no skill fits and you need an isolated worker."
  fi
} 2>/dev/null

emit() { # $1 = additionalContext, $2 = optional systemMessage
  if command -v jq >/dev/null 2>&1; then
    if [ -n "$2" ]; then
      jq -n --arg c "$1" --arg m "$2" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c},systemMessage:$m}'
    else
      jq -n --arg c "$1" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
    fi
  else
    printf '%s' "$1"   # fallback: plain stdout is injected as context
  fi
}

# Implement-phase intent fires the SPIN-OUT directive on its OWN — independent of the
# build-noun gate — because "ship it" / "the plan is approved" carry no build keyword
# yet ARE the exact moment the implement phase begins and inline grinding starts.
if printf '%s' "$lc" | grep -qE "$impl_kw"; then
  emit "IMPLEMENT-PHASE DETECTED in this prompt. $reminder $phase_split$route_suffix" "implement phase detected -> SPIN OUT to fresh-context subagent/Workflow; do NOT build inline in the control plane"
elif printf '%s' "$lc" | grep -qE "$kw"; then
  emit "BUILD-INTENT LIKELY DETECTED in this prompt. $reminder$route_suffix" "build-intent detected -> fire the matching process skill before raw work"
else
  emit "$reminder$route_suffix"
fi
exit 0
