# omniharness — a harness plugin for Claude Code

[![CI](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml/badge.svg)](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/kbigdata/omniharness?sort=semver)](https://github.com/kbigdata/omniharness/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![No Python framework](https://img.shields.io/badge/python-framework--free-blue)

*[한국어 README](README.md)*

**omniharness** adds an **enforced safety net · a completion-verification gate · automatic handoff context ·
skill/wiki accumulation** to Claude Code. Install with a single `/omniharness:init`.

This README clearly separates **what is enforced by code** from **what is left to the model as advice** — no overclaiming.

> What you install is just a few Markdown, JSON, and Python/shell files. (No Python package or framework.)

---

## What is enforced vs. advised (read this first)

| Feature | Class | What actually happens |
|---|---|---|
| Block dangerous commands | 🔒 **Enforced (code)** | PreToolUse hook `policy.py` + `.claude/settings.json` — denies `rm -rf`/`sudo`/secret reads. **Independent of model cooperation** |
| Completion gate (independent verify) | 🔒 **Enforced (code)** | Stop hook `verify_gate.py` — **blocks finishing if a `passes:true` feature has no PASS verify record** |
| No early exit | 🔒 **Enforced (code)** ¹ | Stop hook `stop_guard.py` — blocks finishing while features remain. ¹requires `feature_list.json` to be populated |
| Activity log | 🔒 **Enforced (code)** | PostToolUse hook `audit.py` → `.omniharness/audit.jsonl` |
| Skill quarantine·promote | 🔒 **Enforced (code)** | `skill_gate.py` (rejects unsafe/duplicate, quarantines) + `promote.py` (activates only after **human approval**) |
| Wiki drift check | 🔒 **Enforced (code)** | `wiki_lint.py` — checks frontmatter·status·orphans (**checks only, never fixes**) |
| Handoff context surfacing | 🔁 **Auto-injected** | SessionStart hook `session_context.py` — injects progress·next feature·wiki·git log **at session start** |
| Skill-capture nudge | 🔁 **Auto-injected** | PostToolUse hook `skill_nudge.py` — suggests `skillify` once, only for **verified** features |
| Independent evaluation | 🧩 **Subagent** | `evaluator` (`isolation: worktree`) — when invoked, judges PASS/FAIL from a context that didn't see the work |
| Working-rules load | 🔁 auto / following is advice | `AGENTS.md` auto-loads each session. **Following its content is model advice**, not enforced |
| *Writing* skills · *writing* wiki | ✍️ **Model advice** | Extraction·page authoring is done **by the model**. The plugin only triggers·gates·checks |

🔒 Enforced = code blocks/runs even if the model refuses. 🔁 Auto-injected = a hook feeds context in. ✍️ Advice = the model still has to do it.

---

## 🛡️ Harness — control and verification

> *A hook = a script Claude Code runs automatically before/after a tool, at session start, or at stop.*

- **Block dangerous commands** — if the model tries `rm -rf /`·`sudo`·reading secrets, it's denied **before** the tool runs. Permission settings + hook, two layers.
- **Completion gate** — the model easily believes its own output is "done" (self-eval bias). So **finishing is impossible without verification**: `/omniharness:verify` runs the independent `evaluator` for a PASS/FAIL and records it; without that PASS record, **stopping is blocked**.
- **No early exit** — if `feature_list.json` has unfinished features, stopping is blocked (requires the list to be populated).
- **Activity log** — every tool call is recorded to `audit.jsonl`.

## 📚 Wiki — accumulate, and auto-surface it

- **Manual ingest**: verified declarative learnings recorded via `/omniharness:wiki-ingest` (the model writes the page).
- **Auto-surface**: at the next session start, `wiki/index.md` and progress are **auto-injected into context**, so the same code isn't re-explored.
- **Enforced check**: `/omniharness:wiki-lint` (`wiki_lint.py`) reports stale/broken pages (doesn't fix them).
- (From Andrej Karpathy's idea of an "agent-maintained knowledge wiki".)

## 🤖 Hermes — triggered skill capture (NOT auto-generation)

Successful work is **not auto-generated** into skills. Instead, an honest 4-step path:

1. **Nudge (auto-injected)** — when a feature completes with verification, a hook suggests `/omniharness:skillify`.
2. **Write (model)** — `/omniharness:skillify` has the model draft a skill candidate.
3. **Gate (enforced)** — `skill_gate.py` rejects unsafe/duplicate and **quarantines** it.
4. **Approve (human)** — `/omniharness:promote <name>` activates it only after human review.

## Limits (non-goals)

Stated honestly:

- **Not an unattended autonomous loop.** It does not auto-generate/update skills or wiki without a human. That needs an outer driver running *outside* the session — out of scope for this plugin (which runs *inside* the session).
- **The completion gate only enforces the *existence* of a verify record.** It can't stop a workaround that skips the evaluator and forges a record.
- **Rule *following* is not enforced.** `AGENTS.md` auto-loads, but obeying it is up to the model — only dangerous *actions* are blocked by code.

---

## Install

```bash
/plugin marketplace add https://github.com/kbigdata/omniharness
/plugin install omniharness

# test a local, unpublished version
claude --plugin-dir /path/to/omniharness
```

## Usage

```
/omniharness:init               # create starter files (rules·permissions·progress·wiki)
/omniharness:verify <desc>      # run the independent evaluator + record PASS/FAIL (required before "done")
/omniharness:skillify           # successful task → reusable skill candidate
/omniharness:promote <name>     # activate a skill after human review
/omniharness:wiki-ingest        # record verified learnings into the wiki
/omniharness:wiki-lint          # check the wiki for drift
```

## Verifying it works

- **Offline (no API key)**: `bash tests/run.sh` — 24 assertions feeding sample input to the hook/gate scripts
  (dangerous/secret blocked, normal allowed, completion gate block/allow, handoff injection, skill nudge·quarantine·dedup·promote, stop-guard, wiki lint).
- **Real Claude Code (demonstrated)**: with `claude --plugin-dir .` we observed
  ① SessionStart **actually injecting** handoff context, ② the Stop gate **actually blocking** an unverified completion, ③ PreToolUse **actually blocking** a dangerous command.

## Folder layout

```
.claude-plugin/{plugin.json, marketplace.json}   # plugin info
hooks/hooks.json                                 # registers SessionStart·PreToolUse·PostToolUse·Stop
scripts/                                          # hook·gate·util scripts (individual scripts)
  policy.py audit.py stop_guard.py verify_gate.py session_context.py skill_nudge.py
  skill_gate.py promote.py wiki_lint.py next_feature.py scaffold.sh
agents/evaluator.md                               # independent evaluation subagent
skills/{init,verify,skillify,promote,wiki-ingest,wiki-lint}/SKILL.md
templates/                                        # starter files init copies into your project
docs/                                             # design rationale
tests/run.sh                                      # offline check (24 assertions)
```
