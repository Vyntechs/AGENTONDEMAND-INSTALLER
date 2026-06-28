#!/usr/bin/env bash
# install.sh — Universal AI Engineering Operating System installer
# -----------------------------------------------------------------------------
# Copies this workflow OS into $HOME/.claude, IDEMPOTENTLY, with timestamped
# backups of anything it replaces. Merges settings.json.template into an existing
# settings.json WITHOUT clobbering your values (via jq, or a python3 fallback if
# jq is absent — never a hand-merge). An existing CLAUDE.md is preserved: the OS
# is installed and your prior file is appended verbatim below a fenced marker.
#
# No personal paths, no secrets, no network calls. Run it from a checkout/clone:
#     bash install.sh
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

# jq merge program: union permissions.allow/ask, keep existing defaultMode,
# append hook entries per event, dedup deep-equal entries (=> idempotent).
read -r -d '' MERGE <<'JQ' || true
def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
.[0] as $cur | .[1] as $tpl
| $cur
| .permissions = ($cur.permissions // {})
| .permissions.allow = ((($cur.permissions.allow // []) + ($tpl.permissions.allow // [])) | uniq)
| .permissions.ask   = ((($cur.permissions.ask   // []) + ($tpl.permissions.ask   // [])) | uniq)
| .permissions.defaultMode = ($cur.permissions.defaultMode // $tpl.permissions.defaultMode)
| .hooks = (
    reduce (($tpl.hooks // {}) | keys_unsorted[]) as $k
      (($cur.hooks // {});
       .[$k] = (((.[$k] // []) + ($tpl.hooks[$k])) | uniq))
  )
JQ

if [ ! -f "$tpl" ]; then
  log "  MISSING SOURCE: $tpl (skipped)"
elif [ ! -f "$dst" ]; then
  cp "$tpl" "$dst"
  log "  installed: $dst (fresh copy)"
elif command -v jq >/dev/null 2>&1; then
  backup "$dst"
  tmp="$(mktemp)"
  if jq -s "$MERGE" "$dst" "$tpl" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq empty "$tmp" 2>/dev/null; then
    mv "$tmp" "$dst"
    log "  merged: $dst (your existing values preserved; hooks + permissions added)"
  else
    rm -f "$tmp"
    log "  WARN: jq merge failed — left $dst UNTOUCHED. Merge $tpl by hand."
  fi
elif command -v python3 >/dev/null 2>&1; then
  # No jq: merge with python3 (near-universal on macOS/Linux) — same rules, no
  # hand-merge ever handed to the user.
  backup "$dst"
  tmp="$(mktemp)"
  if python3 - "$dst" "$tpl" > "$tmp" 2>/dev/null <<'PY'
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
if "defaultMode" not in p and "defaultMode" in tp:
    p["defaultMode"] = tp["defaultMode"]
h = cur.setdefault("hooks", {})
for k, v in tpl.get("hooks", {}).items():
    h[k] = uniq(h.get(k, []) + v)
json.dump(cur, sys.stdout, indent=2)
PY
  then
    if [ -s "$tmp" ] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp" 2>/dev/null; then
      mv "$tmp" "$dst"
      log "  merged: $dst (via python3; your existing values preserved; hooks + permissions added)"
    else
      rm -f "$tmp"
      log "  WARN: python3 merge produced invalid output — left $dst UNTOUCHED. Install jq and re-run."
    fi
  else
    rm -f "$tmp"
    log "  WARN: python3 merge failed — left $dst UNTOUCHED. Install jq and re-run (e.g. 'brew install jq')."
  fi
else
  log "  WARN: neither jq nor python3 found — cannot merge into existing $dst."
  log "        Install one and re-run: 'brew install jq' (macOS) or 'apt-get install -y jq' (Debian/Ubuntu)."
  log "        Existing $dst left UNTOUCHED; nothing was lost."
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
else
  log "Finished WITH WARNINGS — see lines above. Nothing was deleted; backups are *$STAMP."
fi
