#!/usr/bin/env bash
# install.sh — Universal AI Engineering Operating System installer
# -----------------------------------------------------------------------------
# Copies this workflow OS into $HOME/.claude, IDEMPOTENTLY, with timestamped
# backups of anything it replaces. Merges settings.json.template into an existing
# settings.json WITHOUT clobbering your values: via jq, or python3 — used both
# when jq is absent AND as a fallback if the jq merge itself fails. Only a
# settings.json that is already invalid JSON is left for you to fix. An existing
# CLAUDE.md is preserved: the OS is installed and your prior file is appended
# verbatim below a fenced marker.
#
# You pick a Momentum Match lane once (A Ship Mode [default] / B Co-Pilot Mode /
# C Glass Box Mode) via --level A|B|C, the AOD_LEVEL env var, or an interactive
# prompt. Numeric 1/2/3 values remain supported. All three share the same
# unrecoverable-command seatbelt + hooks; they differ only in defaultMode + allow.
#
# No personal paths, no secrets, no network calls. Run it from a checkout/clone:
#     bash install.sh            # picks a Momentum Match lane interactively (default A)
#     bash install.sh --level B  # or AOD_LEVEL=B bash install.sh — A/B/C or 1/2/3
# Re-running is safe: unchanged files are skipped, identical merges add nothing.
# -----------------------------------------------------------------------------
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.claude"
TS="$(date +%Y%m%d-%H%M%S)"
STAMP=".bak-$TS"

log() { printf '%s\n' "$*"; }

backup() { # $1 = destination path; back up only if it exists
  if [ -e "$1" ]; then
    cp -p "$1" "$1$STAMP"
    log "  backed up: $1 -> $1$STAMP"
  fi
}

install_file() { # $1 = source, $2 = destination — back up + copy only if changed
  local s="$1" d="$2"
  if [ ! -f "$s" ]; then
    log "  MISSING SOURCE: $s (skipped)"
    return 0
  fi
  if [ -f "$d" ] && cmp -s "$s" "$d"; then
    log "  current: $d"
    return 0
  fi
  backup "$d"
  cp "$s" "$d"
  log "  installed: $d"
}

# --- trust levels ------------------------------------------------------------
# THREE presets share the SAME 14-entry unrecoverable-command seatbelt (ask) and
# the SAME hooks; they differ only in defaultMode + allow:
#   1 Hands-off (default/recommended) — acceptEdits + broad Bash allow
#   2 Watch commands                  — acceptEdits (edits auto-apply), only read-only
#                                       Bash pre-allowed; any other command prompts
#   3 Ask first                       — default mode, read-only allow; everything prompts once
level_name() {
  case "$1" in
    2) printf 'Watch commands' ;;
    3) printf 'Ask first' ;;
    *) printf 'Hands-off' ;;
  esac
}

normalize_level() {
  case "$1" in
    1|A|a) printf '1' ;;
    2|B|b) printf '2' ;;
    3|C|c) printf '3' ;;
    *) return 1 ;;
  esac
}

# Emit the permissions JSON for a level (allow + shared seatbelt + defaultMode).
level_permissions() {
  local mode allow
  case "$1" in
    2) mode='"acceptEdits"'
       allow='["Read","Edit","Write","Grep","Glob","WebSearch","WebFetch","Agent","Task","TodoWrite","Skill","Bash(ls:*)","Bash(cat:*)","Bash(grep:*)","Bash(rg:*)","Bash(find:*)","Bash(head:*)","Bash(tail:*)","Bash(pwd)","Bash(which:*)","Bash(echo:*)","Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git branch:*)"]' ;;
    3) mode='"default"'
       allow='["Read","Grep","Glob"]' ;;
    *) mode='"acceptEdits"'
       allow='["Read","Edit","Write","Grep","Glob","Bash","WebSearch","WebFetch","Agent","Task","TodoWrite","Skill"]' ;;
  esac
  cat <<JSON
{
  "allow": $allow,
  "ask": [
    "Bash(sudo:*)",
    "Bash(rm -rf:*)",
    "Bash(rm -fr:*)",
    "Bash(rm -r -f:*)",
    "Bash(git push --force:*)",
    "Bash(git push --force-with-lease:*)",
    "Bash(git reset --hard:*)",
    "Bash(git clean -f:*)",
    "Bash(dd:*)",
    "Bash(mkfs:*)",
    "Bash(chmod -R:*)",
    "Bash(npm publish:*)",
    "Bash(gh repo create:*)",
    "Bash(gh repo edit:*)"
  ],
  "defaultMode": $mode
}
JSON
}

# py_set_perms: write ($1 template) with .permissions replaced by ($2 perms json)
# into ($3). Used to build the effective template when jq is absent.
py_set_perms() {
  python3 - "$1" "$2" "$3" 2>/dev/null <<'PY'
import json, sys
t = json.load(open(sys.argv[1])); p = json.load(open(sys.argv[2]))
t["permissions"] = p
json.dump(t, open(sys.argv[3], "w"), indent=2)
PY
  [ -s "$3" ] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$3" 2>/dev/null
}

# build_eff_tpl: $1=template $2=perms-json $3=output — template's hooks with the
# chosen level's permissions. jq first, python3 fallback, else the template as-is.
build_eff_tpl() {
  if command -v jq >/dev/null 2>&1 \
     && jq --slurpfile p "$2" '.permissions = $p[0]' "$1" > "$3" 2>/dev/null \
     && [ -s "$3" ]; then
    return 0
  fi
  if command -v python3 >/dev/null 2>&1 && py_set_perms "$1" "$2" "$3"; then
    return 0
  fi
  cp "$1" "$3"   # no JSON tool: fall back to the template as-is (Level 1)
}

# Resolve the chosen level: --level A/B/C flag > AOD_LEVEL env > interactive prompt > A.
LEVEL=""
level_src="flag"
while [ $# -gt 0 ]; do
  case "$1" in
    --level=*) LEVEL="${1#--level=}" ;;
    --level)   if [ $# -ge 2 ]; then LEVEL="$2"; shift; else LEVEL=""; fi ;;
  esac
  shift
done
if [ -z "$LEVEL" ] && [ -n "${AOD_LEVEL:-}" ]; then LEVEL="$AOD_LEVEL"; level_src="env"; fi
# Validate a flag/env value; anything but 1/2/3 -> warn + Level 1.
if [ -n "$LEVEL" ]; then
  if normalized="$(normalize_level "$LEVEL")"; then
    LEVEL="$normalized"
  else
    log "WARN: invalid Momentum Match lane '$LEVEL' (expected A, B, C, 1, 2, or 3) — using A / Level 1 (Ship Mode)."
    LEVEL=1; level_src="default"
  fi
fi
# Interactive prompt only if nothing was specified. Read from /dev/tty so a piped
# install (curl|bash) can still ask. No tty -> fall through to the default.
if [ -z "$LEVEL" ]; then
  ttydev=""
  if [ -t 0 ]; then ttydev="/dev/stdin"
  elif { : </dev/tty; } 2>/dev/null; then ttydev="/dev/tty"; fi
  if [ -n "$ttydev" ]; then
    log "Momentum Match — choose the install lane (change anytime in ~/.claude/settings.json):"
    log "  A) Ship Mode      — Level 1 hands-off autonomy; only stops for unrecoverable commands   [recommended]"
    log "  B) Co-Pilot Mode  — Level 2 watch-commands; auto-edits, asks before non-obvious shell"
    log "  C) Glass Box Mode — Level 3 ask-first; proposes changes before acting"
    printf '%s' "Reply A, B, or C [default A]: "
    reply=""; read -r reply <"$ttydev" 2>/dev/null || reply=""
    if [ -z "$reply" ]; then
      LEVEL=1; level_src="prompt-default"
    elif normalized="$(normalize_level "$reply")"; then
      LEVEL="$normalized"; level_src="prompt"
    else
      log "WARN: '$reply' is not A/B/C or 1/2/3 — using A / Level 1 (Ship Mode)."
      LEVEL=1; level_src="prompt-default"
    fi
  fi
fi
# Non-interactive with no flag/env -> A / Level 1 (recommended default).
if [ -z "$LEVEL" ]; then LEVEL=1; level_src="default-noninteractive"; fi

log "Universal AI Engineering OS — installing into $DEST"
mkdir -p "$DEST" "$DEST/hooks" "$DEST/hooks/state" "$DEST/agents"

# --- CLAUDE.md (MERGE, never clobber) ----------------------------------------
# A fresh machine just gets the OS. An EXISTING personal CLAUDE.md is PRESERVED:
# we install the OS, then append your prior file verbatim below a fenced marker
# so nothing is lost and you never hand-reconcile two prose files. The full
# original is also kept as a timestamped .bak. Idempotent: once merged we leave
# it in place (restore the .bak and re-run to adopt a newer OS version).
log "CLAUDE.md:"
claude_src="$SRC/CLAUDE.md"
claude_dst="$DEST/CLAUDE.md"
claude_marker="## Your previous personal global rules (preserved — integrate as desired)"
if [ ! -f "$claude_src" ]; then
  log "  MISSING SOURCE: $claude_src (skipped)"
elif [ ! -f "$claude_dst" ]; then
  cp "$claude_src" "$claude_dst"
  log "  installed: $claude_dst (fresh)"
elif cmp -s "$claude_src" "$claude_dst"; then
  log "  current: $claude_dst"
elif grep -qF "$claude_marker" "$claude_dst"; then
  log "  current: $claude_dst (already merged; your previous rules preserved below the marker)"
  log "           restore the .bak and re-run to adopt a newer OS version."
else
  backup "$claude_dst"
  { cat "$claude_src"
    printf '\n\n---\n\n%s\n\n' "$claude_marker"
    cat "$claude_dst$STAMP"
  } > "$claude_dst.new.$$" && mv "$claude_dst.new.$$" "$claude_dst"
  log "  merged: $claude_dst (OS installed; your previous CLAUDE.md preserved below the marker + in $claude_dst$STAMP)"
fi

# --- hooks -------------------------------------------------------------------
log "hooks:"
for h in build-intent-reminder context-fill-flag dispatch-gate grind-tripwire inline-build-deny pattern-marker-gate; do
  install_file "$SRC/hooks/$h.sh" "$DEST/hooks/$h.sh"
  [ -f "$DEST/hooks/$h.sh" ] && chmod +x "$DEST/hooks/$h.sh"
done

# --- agent seed --------------------------------------------------------------
log "agents:"
install_file "$SRC/agents/agent-architect.md" "$DEST/agents/agent-architect.md"

# --- settings.json (MERGE, never clobber) ------------------------------------
log "settings.json:"
tpl="$SRC/settings.json.template"
dst="$DEST/settings.json"

# jq merge program: union permissions.allow/ask, SET defaultMode from the chosen
# level (template/preset wins — the level is now an explicit user choice; we still
# ADD the level's permissions to your own and never remove yours), append hook
# entries per event, dedup deep-equal entries (=> idempotent).
read -r -d '' MERGE <<'JQ' || true
def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
.[0] as $cur | .[1] as $tpl
| $cur
| .permissions = ($cur.permissions // {})
| .permissions.allow = ((($cur.permissions.allow // []) + ($tpl.permissions.allow // [])) | uniq)
| .permissions.ask   = ((($cur.permissions.ask   // []) + ($tpl.permissions.ask   // [])) | uniq)
| .permissions.defaultMode = ($tpl.permissions.defaultMode // $cur.permissions.defaultMode)
| .hooks = (
    reduce (($tpl.hooks // {}) | keys_unsorted[]) as $k
      (($cur.hooks // {});
       .[$k] = (((.[$k] // []) + ($tpl.hooks[$k])) | uniq))
  )
JQ

# python3 merge: $1=current $2=template $3=output. Same rules as the jq program.
# Returns 0 ONLY when a valid merged JSON was written to $3. Used both when jq is
# absent AND as the fallback when the jq merge itself fails — so we never hand the
# user a JSON to reconcile by hand.
py_merge() {
  python3 - "$1" "$2" > "$3" 2>/dev/null <<'PY'
import json, sys
cur = json.load(open(sys.argv[1])); tpl = json.load(open(sys.argv[2]))
def uniq(seq):
    out = []
    for x in seq:
        if x not in out: out.append(x)
    return out
p = cur.setdefault("permissions", {}); tp = tpl.get("permissions", {})
p["allow"] = uniq(p.get("allow", []) + tp.get("allow", []))
p["ask"]   = uniq(p.get("ask", [])   + tp.get("ask", []))
if "defaultMode" in tp:
    p["defaultMode"] = tp["defaultMode"]
h = cur.setdefault("hooks", {})
for k, v in tpl.get("hooks", {}).items():
    h[k] = uniq(h.get(k, []) + v)
json.dump(cur, sys.stdout, indent=2)
PY
  [ -s "$3" ] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$3" 2>/dev/null
}

# Announce the chosen level + how to change it (so the default path is explicit).
level_note=""
case "$level_src" in
  default-noninteractive) level_note=" — applied by default (no --level flag or AOD_LEVEL set)" ;;
  default)                level_note=" — defaulted to 1 after an invalid choice" ;;
  prompt-default)         level_note=" — default taken at the prompt" ;;
esac
log "  Trust level: $LEVEL ($(level_name "$LEVEL"))$level_note"
log "  Change anytime: re-run with --level A/B/C (or 1/2/3), or edit permissions.defaultMode/allow in $dst."

# The chosen level's defaultMode (for the change-note below).
case "$LEVEL" in 3) new_mode="default" ;; *) new_mode="acceptEdits" ;; esac

if [ ! -f "$tpl" ]; then
  log "  MISSING SOURCE: $tpl (skipped)"
else
  # Build an EFFECTIVE template = the template's hooks block with permissions set
  # to the chosen level's preset, then run the same merge machinery against it.
  # FRESH install -> exactly the level picked. EXISTING install -> the level's
  # permissions are ADDED (allow/ask unioned; your own entries are never removed)
  # and defaultMode is SET to the level (an explicit choice now). To TIGHTEN later,
  # edit settings.json by hand — the installer only ever adds permissions.
  eff_tpl="$(mktemp)"; perms_tmp="$(mktemp)"
  level_permissions "$LEVEL" > "$perms_tmp"
  build_eff_tpl "$tpl" "$perms_tmp" "$eff_tpl"

  # Capture the existing defaultMode (for the change-note) before we merge.
  old_mode=""
  if [ -f "$dst" ]; then
    if command -v jq >/dev/null 2>&1; then
      old_mode="$(jq -r '.permissions.defaultMode // ""' "$dst" 2>/dev/null || true)"
    elif command -v python3 >/dev/null 2>&1; then
      old_mode="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("permissions",{}).get("defaultMode",""))' "$dst" 2>/dev/null || true)"
    fi
  fi

  # Compute the merged JSON into a temp file. For a FRESH install the base is the
  # effective template, so a re-run is a byte-identical no-op (true idempotency).
  # jq first; python3 is the fallback both when jq is ABSENT and when jq FAILS.
  base="$dst"; [ -f "$dst" ] || base="$eff_tpl"
  tmp="$(mktemp)"
  merged="no"
  if command -v jq >/dev/null 2>&1 \
     && jq -s "$MERGE" "$base" "$eff_tpl" > "$tmp" 2>/dev/null \
     && [ -s "$tmp" ] && jq empty "$tmp" 2>/dev/null; then
    merged="yes"
  elif command -v python3 >/dev/null 2>&1 && py_merge "$base" "$eff_tpl" "$tmp"; then
    merged="yes"
  fi

  if [ "$merged" = "yes" ]; then
    if [ ! -f "$dst" ]; then
      mv "$tmp" "$dst"
      log "  installed: $dst (fresh, Level $LEVEL)"
    elif cmp -s "$tmp" "$dst"; then
      rm -f "$tmp"
      log "  current: $dst"
    else
      backup "$dst"
      mv "$tmp" "$dst"
      log "  merged: $dst (your existing values preserved; Level $LEVEL permissions + hooks added)"
      if [ -n "$old_mode" ] && [ "$old_mode" != "$new_mode" ]; then
        log "  changed defaultMode: $old_mode -> $new_mode per Level $LEVEL (your settings backed up at $dst$STAMP)"
      fi
    fi
  else
    rm -f "$tmp"
    if command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
      # A JSON tool is present, so a FRESH install would have succeeded; reaching
      # here means an EXISTING settings.json that is not valid JSON.
      log "  WARN: could not merge into $dst — your existing settings.json may not be valid JSON."
      log "        Fix it (or install jq) and re-run; $dst was left UNTOUCHED, nothing was lost."
    elif [ ! -f "$dst" ]; then
      cp "$eff_tpl" "$dst"
      log "  installed: $dst (fresh; no JSON tool, applied the Level 1 template)"
    else
      log "  WARN: neither jq nor python3 found — cannot merge into existing $dst."
      log "        Install one and re-run: 'brew install jq' (macOS) or 'apt-get install -y jq' (Debian/Ubuntu)."
      log "        Existing $dst left UNTOUCHED; nothing was lost."
    fi
  fi
  rm -f "$eff_tpl" "$perms_tmp"
fi

# --- verification ------------------------------------------------------------
log ""
log "Verification:"
ok=1
for f in \
  CLAUDE.md \
  settings.json \
  agents/agent-architect.md \
  hooks/build-intent-reminder.sh \
  hooks/context-fill-flag.sh \
  hooks/dispatch-gate.sh \
  hooks/grind-tripwire.sh \
  hooks/inline-build-deny.sh \
  hooks/pattern-marker-gate.sh
do
  if [ -f "$DEST/$f" ]; then
    log "  OK       $f"
  else
    log "  MISSING  $f"
    ok=0
  fi
done

# hooks executable + syntax-valid
for h in "$DEST"/hooks/*.sh; do
  [ -f "$h" ] || continue
  [ -x "$h" ] || { log "  WARN not executable: $h"; ok=0; }
  bash -n "$h" 2>/dev/null || { log "  WARN bash syntax error: $h"; ok=0; }
done

# settings.json is valid JSON (via jq, else python3)
if [ -f "$dst" ]; then
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$dst" 2>/dev/null; then
      log "  OK       settings.json is valid JSON"
    else
      log "  WARN     settings.json is NOT valid JSON"; ok=0
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$dst" 2>/dev/null; then
      log "  OK       settings.json is valid JSON"
    else
      log "  WARN     settings.json is NOT valid JSON"; ok=0
    fi
  fi
fi

log ""
if [ "$ok" = "1" ]; then
  log "Done. The workflow OS is installed in $DEST."
  log "Backups (if any) are alongside each replaced file as *$STAMP."
  log "Start a NEW Claude Code session so the hooks load."
  exit 0
else
  log "Finished WITH WARNINGS — see lines above. Nothing was deleted; backups are *$STAMP."
  exit 1
fi
