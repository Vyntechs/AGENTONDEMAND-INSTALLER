# Universal AI Engineering Operating System for Claude Code

This is one engineer's give-everything Claude Code setup, packaged so you can drop it onto your own machine in one paste. It turns a default Claude Code install into a **director's control plane**: it builds and pressure-tests its own agents on demand, plans before it acts, verifies before it calls anything done, compounds its own mistakes into a lessons file, and delegates work through the file system instead of holding it all in one chat.

The install starts with a tiny **Momentum Match**: Claude reads your situation, shows three elegant Markdown cards, marks the best lane `(Recommended)`, and lets you answer with one letter. No blank form. No hand-merged config. No "tell me your workflow" homework before the useful part starts.

Nothing in here is personal or secret. It's a *universal* `CLAUDE.md` plus the small enforcement layer that makes the rules actually fire. It works identically for any person, project, company, or domain — point it at your own repos and go.

---

## What it actually does

A long-running agent session drifts. Under load it forgets the rules buried in its instructions, starts grinding tasks inline instead of delegating, and asserts "done" without ever running a check. This setup fixes that with two layers:

1. **The operating system** (`CLAUDE.md`) — the rules: build the tool instead of grinding the task, plan before acting, spin the build out to a fresh-context worker, "done" means a check ran, compound every correction, one writer per artifact, name the workflow pattern, stop at real gates but execute resolved orders.
2. **The enforcement layer** (`hooks/` + `settings.json`) — because rules in prose get skipped under load, six hooks make the load-bearing ones fire *mechanically* right before the model acts (or block the stop). **Every hook fails open:** any parse error, missing tool, or odd input → it does nothing and gets out of the way. A missed nudge is a soft miss; a false block would be a disaster, so the hooks never block legitimate work on their own bug. Fail-open covers errors and missing tools, not intent: a gate will occasionally block legitimate work *by design* (a forced spin-out, a "name your pattern" nudge) — but every gate carries an override token, and you can delete any hook you don't want.

---

## Install

### Option A — the one-paste prompt (recommended)

Paste this to your own Claude Code — it points at this repo's `INSTALL.md` and runs the whole setup hands-off:

```
Read https://raw.githubusercontent.com/Vyntechs/AGENTONDEMAND-INSTALLER/main/INSTALL.md and follow it exactly to install the Universal AI Engineering Operating System into my ~/.claude on this machine.

It is an instruction file plus a few plain-text config files: a CLAUDE.md, six bash hook scripts, a settings.json template, and one agent file. Ask me exactly ONE thing using the Momentum Match cards in INSTALL.md: infer the best lane from context, mark that lane `(Recommended)`, and let me reply only A, B, or C. Map A to Level 1 / hands-off, B to Level 2 / watch-commands, and C to Level 3 / ask-first. If I do not pick, use the recommended lane, defaulting to A / Level 1 when context is ambiguous. After that, do the whole install autonomously; every other choice is already specified in INSTALL.md.

You have my permission to: fetch those files over the network from the same base URL, run shell commands to copy them, back up anything you replace with a timestamped .bak copy, merge the settings template into my existing settings.json without overwriting my values, and write only under ~/.claude. Make no persistent changes outside ~/.claude — only transient temp files in the system temp dir, removed when you're done — and do not send any of my data anywhere.

If a required tool is missing, stop and tell me the one command to install it. Merge anything that needs merging yourself — never hand me a JSON file or rules to reconcile by hand. When you're done, verify the install and show me a short checklist of what landed and where my backups are. The only thing I should have to do afterward is start a new Claude Code session — make that the final line of your report.
```

Your Claude reads `INSTALL.md`, fetches the rest, backs up anything it replaces, merges settings without clobbering your values, and verifies the result.

### Option B — the script

```bash
git clone https://github.com/Vyntechs/AGENTONDEMAND-INSTALLER.git && cd AGENTONDEMAND-INSTALLER
bash install.sh
```

`install.sh` does the same thing locally: timestamped backups, idempotent copy into `$HOME/.claude`, a merge into any existing `settings.json` (via `jq`, or a `python3` fallback if `jq` is missing **or the `jq` merge fails** — only an already-invalid `settings.json` is left for you to fix), preservation of any existing `CLAUDE.md` (your prior file is appended verbatim below a fenced marker), and a verification block at the end.

The direct script path uses the same lanes: **A Ship Mode** maps to Level 1, **B Co-Pilot Mode** maps to Level 2, and **C Glass Box Mode** maps to Level 3. Numeric `--level 1/2/3` still works for automation.

**The only manual step, after either option: start a new Claude Code session** so the hooks load — they're read at session start and there is no in-session reload. Re-running is safe — it never duplicates hooks or permissions, and re-copies only changed files (the `settings.json` merge is recomputed each run but adds nothing if unchanged).

### Prerequisites

- Claude Code installed.
- `bash` and a downloader (`git` preferred, or `curl`).
- `jq` *(optional, never a blocker)* — a convenience for merging into an **existing** `settings.json`. If it's missing the merge still happens automatically: the script falls back to `python3`, and the one-paste agent does the merge itself. You're never left with a manual JSON edit.

### Permissions — pick your trust level

The installer asks **one question** the first time: how hands-off do you want Claude to be? You pick once, and it writes the matching permissions into `~/.claude/settings.json`. All three levels share the same **seatbelt** — a short list of *unrecoverable* commands that always pause for a one-tap confirm (`sudo`, `rm -rf`, `git push --force`, `git reset --hard`, `dd`, `mkfs`, `chmod -R`, `npm publish`, and creating/editing GitHub repos). The levels differ only in how much *else* runs without asking:

- **Level 1 — Hands-off** *(default, recommended).* Claude runs your normal work — edits, reads, tests, `git` commits/pushes/merges, builds — without stopping to ask. Only the seatbelt commands pause. The smoothest day-to-day setup, and what most people want.
- **Level 2 — Watch the commands.** File edits still apply on their own and safe look-around commands (`ls`, `cat`, `grep`, `git status/diff/log`, …) run freely — but any *other* shell command asks first. A middle ground: you see what it's about to run without approving every keystroke.
- **Level 3 — Ask first.** Claude can read your files but proposes everything else and waits for your yes. Most control, most prompts — good for a brand-new machine or a repo you want to be careful with.

**It's a one-time pick.** A non-interactive install (e.g. `curl … | bash`) defaults to Ship Mode / Level 1 and says so. You can also choose up front without the prompt: `bash install.sh --level B`, `AOD_LEVEL=C bash install.sh`, or the numeric `--level 2` / `AOD_LEVEL=3` equivalents.

**Change your mind later?** Re-run the installer with `--level A`, `--level B`, or `--level C` (numeric 1/2/3 also works), or just edit `permissions.defaultMode` / `permissions.allow` in `~/.claude/settings.json` by hand. One caveat for an **existing** `settings.json`: the installer only ever **adds** permissions (and sets the mode for the level you pick) — it never removes a permission you already granted, so to *tighten* a setup, edit the file directly.

**Want zero prompts, ever?** Beyond Level 1, set `"defaultMode": "bypassPermissions"` (or launch Claude Code with `--dangerously-skip-permissions`). That removes the seatbelt too — Claude will run *any* command, including destructive ones, with no confirm. Only do this on a machine and project you're fully comfortable handing the keys to.

### Heads-up about your existing `CLAUDE.md`

If you already have a `~/.claude/CLAUDE.md`, the installer **preserves it**: it installs this OS and appends your prior file verbatim below a fenced `## Your previous personal global rules (preserved …)` heading, and also keeps a timestamped `.bak`. **Your prior `CLAUDE.md` is never hand-merged and nothing is lost.** Your `settings.json` is likewise *merged*, not replaced: your permissions and hooks are kept and these are added alongside (via `jq`, with a `python3` fallback when `jq` is absent or its merge fails, or the agent itself). The one case it can't auto-merge is an existing `settings.json` that is already invalid JSON — that it leaves untouched for you to fix.

**License:** ships MIT by default — the publisher sets the copyright holder in `LICENSE` at publish time (swap in CC0 instead if you want zero-attribution).

---

## What each piece does

### `CLAUDE.md` — the operating system
The universal rulebook. Highlights:
- **Prime directive — build the tool, don't grind the task.** For any reusable or recurring need: pause, research, plan, build a reusable sub-agent, pressure-test it against a real check case, then return and use it. A strict build-or-not test (reusable / <30% overlap / crisp single mandate) prevents both gaps and agent bloat.
- **Plan before acting** on anything non-trivial; **spin the build out** to a fresh-context worker so the control session stays clean.
- **"Done" means a check ran** — never "no errors," never a bare assertion. Quote the command and its output.
- **Compound every correction** into `tasks/lessons.md` so the system gets faster over time.
- **Parallel work, single writer per artifact.** **File-system delegation** via `inbox/` → returns folder (the folder is the status). **Name the workflow pattern** on every action turn. **Mechanism ladder** — use the cheapest rung that fits.

### `agents/agent-architect.md` — the one seed agent
The build-if-missing engine. The gift is **the engine that creates agents on demand**, not a library of pre-made ones. When a genuinely reusable need appears with no agent for it, the architect researches it, designs a well-formed persona (frontmatter + single mandate + anti-scope + output contract, matching your existing roster), validates it against a check case, installs it, and reports provenance. Every other role (planner, researcher, critic, validator) is a discipline you run on demand — not a file you carry around.

### `hooks/` — the enforcement layer (six scripts)
- **`build-intent-reminder.sh`** *(UserPromptSubmit)* — when a prompt smells like build/debug/design/feature work, injects a high-salience reminder to fire the matching process skill *before* the first raw tool call, arms the inline-build gate, and on the implement phase injects the spin-out directive.
- **`inline-build-deny.sh`** *(PreToolUse: Edit/Write, hard gate)* — while a build phase is "armed," denies edits to real source files in the control session, forcing the build to spin out. Self-healing armed flag; always allows docs/notes/plans, `.claude/` config, and spun-out subagents.
- **`dispatch-gate.sh`** *(PreToolUse: Task/Agent, hard gate)* — denies any worker brief that lacks an observable acceptance check (a DONE-WHEN / VERIFY-BY), so spun-out workers can't report "done" as a bare assertion.
- **`grind-tripwire.sh`** *(PostToolUse, advisory)* — counts build-shaped tool calls per session; warns once at 5 and harder at 10 that you're building, not directing. Read-only recon doesn't count.
- **`context-fill-flag.sh`** *(UserPromptSubmit, advisory)* — estimates context fullness and nudges you to save/clear before the session drifts into the "dumb zone." Banded at 50/70/85%, silent below.
- **`pattern-marker-gate.sh`** *(Stop, gate)* — blocks a turn that claims done without a real verification pattern, or took action without naming its pattern, or handed a clear order back as a question. Evidence-aware and loop-safe.

### `settings.json.template`
Wires the six hooks to their events and sets a **hands-free baseline**: it allows the common tools and turns on `acceptEdits`, so normal work (edits, tests, `git` commits/pushes/merges, builds) runs without prompting. `ask` pauses only on a few *unrecoverable* commands (`sudo`, `rm -rf`, `git push --force`, `git reset --hard`, `npm publish`, …) — plain `git push` is **not** gated. The installer merges this into your existing settings without clobbering anything.

---

## Honest note

This is **one** setup that works for how I direct agents. It is opinionated, and I am very likely wrong about parts of it. The fail-open hooks are deliberately conservative, the context-fullness math is a rough byte-size proxy (the platform doesn't reliably hand the model a live token count), and some rules will fit your workflow better than others. Take what's useful, delete what isn't, and **if you have a better way, tell me** — that's the whole point of giving it away. No hype, no lock-in: it's plain text and bash you can read end to end before you run it.

---

Built by [Vyntechs](https://github.com/Vyntechs). MIT licensed — use it, fork it, ship it; just keep the credit.
