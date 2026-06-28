# Universal AI Engineering Operating System for Claude Code

This is one engineer's give-everything Claude Code setup, packaged so you can drop it onto your own machine in one paste. It turns a default Claude Code install into a **director's control plane**: it builds and pressure-tests its own agents on demand, plans before it acts, verifies before it calls anything done, compounds its own mistakes into a lessons file, and delegates work through the file system instead of holding it all in one chat.

Nothing in here is personal or secret. It's a *universal* `CLAUDE.md` plus the small enforcement layer that makes the rules actually fire. It works identically for any person, project, company, or domain — point it at your own repos and go.

---

## What it actually does

A long-running agent session drifts. Under load it forgets the rules buried in its instructions, starts grinding tasks inline instead of delegating, and asserts "done" without ever running a check. This setup fixes that with two layers:

1. **The operating system** (`CLAUDE.md`) — the rules: build the tool instead of grinding the task, plan before acting, spin the build out to a fresh-context worker, "done" means a check ran, compound every correction, one writer per artifact, name the workflow pattern, stop at real gates but execute resolved orders.
2. **The enforcement layer** (`hooks/` + `settings.json`) — because rules in prose get skipped under load, six hooks make the load-bearing ones fire *mechanically* right before the model acts (or block the stop). **Every hook fails open:** any parse error, missing tool, or odd input → it does nothing and gets out of the way. A missed nudge is a soft miss; a false block would be a disaster, so the hooks never block legitimate work on their own bug.

---

## Install

### Option A — the one-paste prompt (recommended)

Paste this to your own Claude Code — it points at this repo's `INSTALL.md` and runs the whole setup hands-off:

```
Read https://raw.githubusercontent.com/Vyntechs/AGENTONDEMAND-INSTALLER/main/INSTALL.md and follow it exactly to install the Universal AI Engineering Operating System into my ~/.claude on this machine.

It is an instruction file plus a few plain-text config files: a CLAUDE.md, six bash hook scripts, a settings.json template, and one agent file. Do the whole install autonomously and ask me nothing — every choice is already specified in INSTALL.md.

You have my permission to: fetch those files over the network from the same base URL, run shell commands to copy them, back up anything you replace with a timestamped .bak copy, merge the settings template into my existing settings.json without overwriting my values, and write only under ~/.claude. Do not touch anything outside ~/.claude, and do not send any of my data anywhere.

If a required tool is missing, stop and tell me the one command to install it. Merge anything that needs merging yourself — never hand me a JSON file or rules to reconcile by hand. When you're done, verify the install and show me a short checklist of what landed and where my backups are. The only thing I should have to do afterward is start a new Claude Code session — make that the final line of your report.
```

Your Claude reads `INSTALL.md`, fetches the rest, backs up anything it replaces, merges settings without clobbering your values, and verifies the result.

### Option B — the script

```bash
git clone https://github.com/Vyntechs/AGENTONDEMAND-INSTALLER.git && cd AGENTONDEMAND-INSTALLER
bash install.sh
```

`install.sh` does the same thing locally: timestamped backups, idempotent copy into `$HOME/.claude`, a merge into any existing `settings.json` (via `jq`, or a `python3` fallback if `jq` is missing — never a hand-merge), preservation of any existing `CLAUDE.md` (your prior file is appended verbatim below a fenced marker), and a verification block at the end.

**The only manual step, after either option: start a new Claude Code session** so the hooks load — they're read at session start and there is no in-session reload. Re-running is safe — it never duplicates hooks or permissions and only re-copies changed files.

### Prerequisites

- Claude Code installed.
- `bash` and a downloader (`git` preferred, or `curl`).
- `jq` *(optional, never a blocker)* — a convenience for merging into an **existing** `settings.json`. If it's missing the merge still happens automatically: the script falls back to `python3`, and the one-paste agent does the merge itself. You're never left with a manual JSON edit.

### Heads-up about your existing `CLAUDE.md`

If you already have a `~/.claude/CLAUDE.md`, the installer **preserves it**: it installs this OS and appends your prior file verbatim below a fenced `## Your previous personal global rules (preserved …)` heading, and also keeps a timestamped `.bak`. **You never hand-merge anything; nothing is lost.** Your `settings.json` is likewise *merged*, not replaced: your permissions and hooks are kept and these are added alongside (via `jq`, a `python3` fallback, or the agent itself — never a manual JSON edit).

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
Wires the six hooks to their events and sets baseline permissions (allow the common tools; `ask` before destructive/irreversible ones like `git push`, `rm -rf`, `npm publish`). The installer merges this into your existing settings without clobbering anything.

---

## Honest note

This is **one** setup that works for how I direct agents. It is opinionated, and I am very likely wrong about parts of it. The fail-open hooks are deliberately conservative, the context-fullness math is a rough byte-size proxy (the platform doesn't reliably hand the model a live token count), and some rules will fit your workflow better than others. Take what's useful, delete what isn't, and **if you have a better way, tell me** — that's the whole point of giving it away. No hype, no lock-in: it's plain text and bash you can read end to end before you run it.

---

Built by [Vyntechs](https://github.com/Vyntechs). MIT licensed — use it, fork it, ship it; just keep the credit.
