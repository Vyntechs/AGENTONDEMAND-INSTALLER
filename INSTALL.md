# INSTALL — read this and follow it exactly

**You are Claude Code. Install the Universal AI Engineering Operating System into this machine's `~/.claude`. Do the whole thing autonomously. Ask the user exactly ONE thing — which trust level (default Level 1, see "Trust level" below) — and every other decision below is already made for you.**

This file is the authority. Follow it top to bottom. It is idempotent (safe to re-run), it backs up anything it replaces, and it never deletes or transmits user data.

**Success criterion — exactly one manual action remains for the user, at the very end:** start a new Claude Code session so the hooks load (they are read at session start; there is no in-session reload). You do everything else yourself — including any file merge. Never hand the user JSON to merge or rules to reconcile by hand.

---

## What you will do (the contract)

Install a small set of plain-text files under `~/.claude`:

- `~/.claude/CLAUDE.md` — the operating-system instructions (any existing personal `CLAUDE.md` is PRESERVED, never clobbered — see Step 3)
- `~/.claude/settings.json` — wires the hooks + permissions at the user's chosen **trust level** (MERGED into any existing file, never clobbered)
- `~/.claude/hooks/*.sh` — six bash hook scripts that make the rules fire mechanically
- `~/.claude/agents/agent-architect.md` — the one seed agent (a build-on-demand engine)
- `~/.claude/hooks/state/` — an empty working dir the hooks use at runtime

You make **no persistent changes outside `~/.claude`**. You do use a temporary directory (the system temp dir) to download/clone the package; remove it when you're done. Anything you replace under `~/.claude` is first copied to `<file>.bak-<timestamp>`.

---

## Permissions you need (and only these)

- **Run shell commands** (`Bash`) — to create dirs, copy files, `chmod`, and run `jq`.
- **Read/Write files under `~/.claude`** — and nowhere else.
- **Fetch files over the network** (`WebFetch` or `curl`) — read-only HTTP GET from the **single base URL** these files came from. No other hosts.

If your harness prompts for any of these, grant them. Do not transmit any of the user's data anywhere — this install only *downloads* static text and *writes* it locally.

---

## Prerequisites (verify; do not ask the user)

Run these checks first.

- **Claude Code** — you are running inside it, so this is satisfied.
- **bash** — required. Check: `command -v bash`.
- **A downloader** — `git` (preferred) **or** `curl` **or** your own `WebFetch` tool. At least one must work.
- **jq** — *optional, never a blocker*. It's only a convenience for merging the settings template into an existing `settings.json`. If `jq` is absent, **you merge the JSON yourself** — you are Claude: use the near-universal `python3` fallback (Step 3), or read both files and write the merged JSON directly. So `jq` is genuinely never required; **do not stop for it.**

If a **required** prereq is missing (no `bash`, or no way to download at all), STOP and tell the user the one command to install it (e.g. `apt-get install -y curl`). Do not do a partial install. (`jq` is **not** a required prereq — never treat a missing `jq` as a stop condition.)

---

## Trust level — the ONE question you ask

Ask the user this once; everything else is autonomous:

> **How hands-off should Claude be?** **1) Hands-off** *(default, recommended)* — works on its own, only stops for ~14 unrecoverable commands · **2) Watch commands** — auto-edits + safe read-only shell, asks before any other command · **3) Ask first** — proposes everything and waits for your yes. *Enter 1, 2, or 3 [default 1].*

If the user doesn't answer, can't be reached, or the session is non-interactive, use **Level 1**. (If you run `install.sh`, it asks this itself — answer it with `--level N` or `AOD_LEVEL=N`, or let it default to 1.)

All three levels share the **same `ask` seatbelt and the same hooks**; they differ only in `defaultMode` + `allow`. Use the chosen level's `permissions` block below as the settings' `permissions`, and keep the template's `hooks` block as-is.

**Level 1 — Hands-off** (`defaultMode: "acceptEdits"`):

```json
"permissions": {
  "allow": ["Read","Edit","Write","Grep","Glob","Bash","WebSearch","WebFetch","Agent","Task","TodoWrite","Skill"],
  "ask": ["Bash(sudo:*)","Bash(rm -rf:*)","Bash(rm -fr:*)","Bash(rm -r -f:*)","Bash(git push --force:*)","Bash(git push --force-with-lease:*)","Bash(git reset --hard:*)","Bash(git clean -f:*)","Bash(dd:*)","Bash(mkfs:*)","Bash(chmod -R:*)","Bash(npm publish:*)","Bash(gh repo create:*)","Bash(gh repo edit:*)"],
  "defaultMode": "acceptEdits"
}
```

**Level 2 — Watch commands** — same `ask` seatbelt, `defaultMode: "acceptEdits"`, and this `allow` (no bare `Bash`, so any non-listed command prompts; edits still auto-apply):

```json
"allow": ["Read","Edit","Write","Grep","Glob","WebSearch","WebFetch","Agent","Task","TodoWrite","Skill","Bash(ls:*)","Bash(cat:*)","Bash(grep:*)","Bash(rg:*)","Bash(find:*)","Bash(head:*)","Bash(tail:*)","Bash(pwd)","Bash(which:*)","Bash(echo:*)","Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git branch:*)"]
```

**Level 3 — Ask first** — same `ask` seatbelt, `defaultMode: "default"`, read-only `allow`:

```json
"allow": ["Read","Grep","Glob"]
```

**Apply rules (identical for the script and the manual fallback in Step 3):**

- **Fresh** `settings.json` (none exists): write `{ "permissions": <chosen level>, "hooks": <template hooks> }`.
- **Existing** `settings.json`: **ADD** — union `permissions.allow` and `permissions.ask` with the chosen level's (NEVER remove the user's own entries), append each `.hooks.*` entry (dedup), and **SET** `permissions.defaultMode` to the level's value (it is an explicit user choice now). To *tighten* an existing setup the user edits the file by hand — the installer only ever adds permissions.

---

## Step 1 — Locate the package

You were told to read this file at a URL ending in `/INSTALL.md`.

> Let **`BASE`** = that URL with the trailing `/INSTALL.md` removed.
> (In the README this is written as the placeholder `https://raw.githubusercontent.com/Vyntechs/AGENTONDEMAND-INSTALLER/main`.)

All other files live alongside this one under `BASE`.

**Primary fetch — clone the whole repo.** Cloning gets the entire tree in one shot, so the file set can never drift (a hand-maintained file list goes stale the moment a hook is added or renamed; cloning can't). Derive the clone URL from `BASE` — e.g. a GitHub raw base `https://raw.githubusercontent.com/Vyntechs/AGENTONDEMAND-INSTALLER/main` maps to the clone URL `https://github.com/Vyntechs/AGENTONDEMAND-INSTALLER.git`:

```bash
TMP="$(mktemp -d)"
git clone <CLONE_URL> "$TMP"
```

**Fallback — per-file download** (only if `git` is unavailable or the clone URL can't be derived). Download each of these from `BASE` into `$TMP` (use `curl -fsSL "<BASE>/<path>" -o "$TMP/<path>"`, or your `WebFetch` tool), preserving the `hooks/` and `agents/` subpaths (`mkdir -p "$TMP/hooks" "$TMP/agents"` first):

```
CLAUDE.md
settings.json.template
install.sh
agents/agent-architect.md
hooks/build-intent-reminder.sh
hooks/context-fill-flag.sh
hooks/dispatch-gate.sh
hooks/grind-tripwire.sh
hooks/inline-build-deny.sh
hooks/pattern-marker-gate.sh
```

Either way, after fetching, confirm all ten files exist and are non-empty. If any are missing, retry once (re-clone, or re-download the missing file), then STOP and report what could not be fetched. Do not install a partial set.

---

## Step 2 — Run the installer

Preferred path — run the bundled script, passing the trust level the user picked (`1`, `2`, or `3`; default `1`). It performs every backup, copy, and the settings merge described in Step 3, idempotently:

```bash
bash "$TMP/install.sh" --level <N>    # <N> = the level the user chose (default 1)
```

The script applies the chosen level's `permissions`, copies from `$TMP` into `$HOME/.claude`, backs up anything it replaces as `*.bak-<timestamp>`, merges into an existing `settings.json` (via `jq`, or a `python3` fallback if `jq` is absent **or the `jq` merge fails**), preserves an existing `CLAUDE.md` by appending it verbatim below a fenced marker, makes the hooks executable, and prints a verification block. (Run with no `--level` and it prompts; non-interactive, it defaults to Level 1.)

If you cannot or should not run the script, do the equivalent **manual steps** in Step 3 instead. Either way, finish with the **verification** in Step 4.

---

## Step 3 — Manual fallback (only if you did NOT run install.sh)

Do exactly this, in order. `TS="$(date +%Y%m%d-%H%M%S)"`.

1. **Make dirs:** `mkdir -p "$HOME/.claude/hooks/state" "$HOME/.claude/agents"`
2. **CLAUDE.md — MERGE, never clobber:**
   - If `~/.claude/CLAUDE.md` does **not** exist (or already contains the preserved-rules marker below): copy `$TMP/CLAUDE.md` into place (or leave the already-merged file as-is).
   - If it exists and differs: back it up to `~/.claude/CLAUDE.md.bak-$TS`, install `$TMP/CLAUDE.md`, then **append the user's prior file verbatim** to the end under a fenced heading so nothing is lost and the user never hand-reconciles two prose files:
     ```bash
     { cat "$TMP/CLAUDE.md"
       printf '\n\n---\n\n## Your previous personal global rules (preserved — integrate as desired)\n\n'
       cat "$HOME/.claude/CLAUDE.md.bak-$TS"
     } > "$HOME/.claude/CLAUDE.md.new" && mv "$HOME/.claude/CLAUDE.md.new" "$HOME/.claude/CLAUDE.md"
     ```
   - Do the merge yourself — **never** tell the user to merge it by hand. The `.bak-$TS` stays as a safety net.
3. **Hooks:** for each of the six `hooks/*.sh`, back up any existing same-named file (`.bak-$TS`), copy the new one in, and `chmod +x` it.
4. **Agent seed:** back up any existing `~/.claude/agents/agent-architect.md`, then copy the new one in.
5. **settings.json — MERGE, never clobber** (apply the user's chosen **trust level** — see "Trust level" above). In the commands below, treat the **template** as `settings.json.template` with its `permissions` block replaced by the chosen level's preset (for Level 1 the template is already that; for Levels 2/3 swap in the level's `allow` + `defaultMode`, keeping the same `ask` seatbelt and the template's `hooks`).
   - If `~/.claude/settings.json` does **not** exist: write the chosen level's preset — `{ "permissions": <chosen level>, "hooks": <template hooks> }` — to `~/.claude/settings.json`.
   - If it exists and **`jq` is available**: back it up (`.bak-$TS`), then deep-merge — **union** `permissions.allow` and `permissions.ask` (ADD the level's, never removing the user's), **set** `permissions.defaultMode` to the chosen level's value, and **append** each entry under every `.hooks.*` event (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, `Stop`) **without removing the user's**, de-duplicating identical entries so re-running adds nothing. Preserve every other top-level key (e.g. `env`) untouched. Use:
     ```bash
     jq -s '
       def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
       .[0] as $cur | .[1] as $tpl
       | $cur
       | .permissions = ($cur.permissions // {})
       | .permissions.allow = ((($cur.permissions.allow // []) + ($tpl.permissions.allow // [])) | uniq)
       | .permissions.ask   = ((($cur.permissions.ask   // []) + ($tpl.permissions.ask   // [])) | uniq)
       | .permissions.defaultMode = ($tpl.permissions.defaultMode // $cur.permissions.defaultMode)
       | .hooks = (reduce (($tpl.hooks // {}) | keys_unsorted[]) as $k
           (($cur.hooks // {}); .[$k] = (((.[$k] // []) + ($tpl.hooks[$k])) | uniq)))
     ' "$HOME/.claude/settings.json" "$TMP/settings.json.template" > /tmp/merged.$$ \
       && jq empty /tmp/merged.$$ && mv /tmp/merged.$$ "$HOME/.claude/settings.json"
     ```
   - If it exists and **`jq` is NOT available**: **you merge it yourself** — never hand the user a manual JSON edit. Back up the original (`.bak-$TS`) first, then use the near-universal `python3` fallback below (or read both files and write the merged JSON directly), applying the same rules (union `permissions.allow`/`ask` additively, **set** `defaultMode` to the chosen level, append each `.hooks.*` entry without removing the user's, dedup identical entries). Validate the result parses as JSON before moving it into place:
     ```bash
     python3 - "$HOME/.claude/settings.json" "$TMP/settings.json.template" > /tmp/merged.$$ <<'PY'
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
     if "defaultMode" in tp: p["defaultMode"] = tp["defaultMode"]
     h = cur.setdefault("hooks", {})
     for k, v in tpl.get("hooks", {}).items(): h[k] = uniq(h.get(k, []) + v)
     json.dump(cur, sys.stdout, indent=2)
     PY
     python3 -c 'import json,sys; json.load(open(sys.argv[1]))' /tmp/merged.$$ \
       && mv /tmp/merged.$$ "$HOME/.claude/settings.json"
     ```
   - Only if there is **no** JSON tool at all (no `jq` **and** no `python3`) AND you cannot otherwise produce the merged JSON yourself, STOP and tell the user the one command to add a tool (e.g. `brew install jq`) — an acceptable missing-tool blocker, never a hand-merge.

---

## Step 4 — Verify (always do this, then report)

Confirm and report each:

1. These files exist and are non-empty:
   `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/agents/agent-architect.md`, and all six `~/.claude/hooks/*.sh`.
2. Every `~/.claude/hooks/*.sh` is **executable** and passes a syntax check: `bash -n <hook>`.
3. `~/.claude/settings.json` is **valid JSON**: `jq empty ~/.claude/settings.json` (or `python3 -c 'import json,sys; json.load(open(sys.argv[1]))' ~/.claude/settings.json` if no `jq`).
4. If `jq` is present, confirm the merge took: `~/.claude/settings.json` has entries under `.hooks.PreToolUse`, `.hooks.PostToolUse`, `.hooks.UserPromptSubmit`, `.hooks.SessionStart`, and `.hooks.Stop`, and the user's pre-existing keys still exist.

Then clean up the temp dir (`rm -rf "$TMP"`) and give the user a short report:

- a one-line summary,
- the checklist of what landed and where,
- **the path of any `*.bak-<timestamp>` backups** (a backed-up `CLAUDE.md` is a safety net only — the user's prior rules are already preserved inline under the fenced marker, so no hand-merge is needed),
- **which trust level was applied** (1 Hands-off / 2 Watch-commands / 3 Ask-first) and **how to change it** — re-run the installer with `--level N`, or edit `permissions.defaultMode` / `permissions.allow` in `~/.claude/settings.json` directly (on an existing file the install ADDED the level's permissions and SET its mode, but never removed permissions you already had, so tighten by editing the file),
- a `Skipped/Failed: <list, or "None">` line.

If anything failed, say so plainly — do not claim success you did not verify.

End the report with this as the **single, unmissable last line** — it is the one and only manual action left for the user:

> **▶ Start a new Claude Code session now so the hooks load.**

---

## Notes

- **Idempotent:** re-running makes no duplicate hooks or permissions and re-copies only changed files.
- **Reversible:** every replaced file has a timestamped `.bak-` copy next to it; to undo, restore those and remove the added entries from `settings.json`.
- **No personal data:** these files contain no names, emails, tokens, or machine-specific paths. They use `$HOME`/`~` only.
