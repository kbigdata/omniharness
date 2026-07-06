# omniharness — a harness plugin for Claude Code

[![CI](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml/badge.svg)](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/kbigdata/omniharness?sort=semver)](https://github.com/kbigdata/omniharness/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![No Python framework](https://img.shields.io/badge/python-framework--free-blue)

*[한국어 README](README.md)*

**omniharness** adds an **enforced safety net · a completion-verification gate · automatic handoff context ·
skill/wiki accumulation** to Claude Code. Install with `/plugin install`, then apply to a project with `/omniharness:init`.

What is enforced by code and what is left to the model as advice are separated in the table below.

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

🔒 Enforced = code blocks/runs even if the model refuses. 🔁 Auto-injected = a hook automatically inserts the needed information into context, without the model asking. ✍️ Advice = the model still has to do it.

---

## 🛡️ Harness — control and verification

> *A hook = a script Claude Code runs automatically before/after a tool, at session start, or at stop.*

- **Block dangerous commands** — if the model tries `rm -rf /`·`sudo`·reading secrets, it's denied **before** the tool runs. Two layers of defense: permission settings + the hook.
- **Completion gate** — the model easily believes its own output is "done" (self-eval bias). So **finishing is impossible without verification**: `/omniharness:verify` runs the independent `evaluator` for a PASS/FAIL and records it; without that PASS record, **stopping is blocked**.
- **No early exit** — if `feature_list.json` has unfinished features, stopping is blocked (requires the list to be populated).
- **Activity log** — every tool call is recorded to `audit.jsonl`.

## 📚 Wiki — accumulate, and auto-surface it

- **Manual ingest**: verified declarative learnings recorded via `/omniharness:wiki-ingest` (the model writes the page).
- **Auto-surface**: at the next session start, `wiki/index.md` and progress are **auto-injected into context**, so the same code isn't re-explored.
- **Enforced check**: `/omniharness:wiki-lint` (`wiki_lint.py`) reports stale/broken pages (doesn't fix them).
- (From Andrej Karpathy's idea of an "agent-maintained knowledge wiki".)

## 🤖 Hermes — triggered skill capture (NOT auto-generation)

Successful work is **not auto-generated** into skills. Instead, a 4-step path:

1. **Nudge (auto-injected)** — when a feature completes with verification, a hook suggests `/omniharness:skillify`.
2. **Write (model)** — `/omniharness:skillify` has the model draft a skill candidate.
3. **Gate (enforced)** — `skill_gate.py` rejects unsafe/duplicate and **quarantines** it.
4. **Approve (human)** — `/omniharness:promote <name>` activates it only after human review.

## Limits (non-goals)

- **The plugin hooks themselves are not an unattended autonomous loop.** Hooks only enforce/verify *inside* the session. A fully autonomous loop is handled by the *outside*-the-session driver [`scripts/autoloop.py`](scripts/autoloop.py) (**experimental** — 48 offline assertions + live-model validation: single-feature run · two forgery defenses · multi-feature chain · real regression-break detection · impossible-feature escalate-and-continue). Design·rules·validation log: [`docs/자동루프-설계.md`](docs/자동루프-설계.md).
- **The completion gate only enforces the *existence* of a verify record.** It can't stop a workaround that skips the evaluator and forges a record.
- **Rule *following* is not enforced.** `AGENTS.md` auto-loads, but obeying it is up to the model — only dangerous *actions* are blocked by code.
- **Command blocking is a best-effort backstop, not a sandbox.** It catches common accidents and direct secret access, but not obfuscation, base64, or alternate-tool bypasses. The real boundary is Claude Code permissions + `settings.json` + not running untrusted code in the first place.

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

> New-project setup (detailed): [`docs/적용-매뉴얼.md`](docs/적용-매뉴얼.md)

### (Experimental) Fully autonomous loop

An *outside*-the-session driver takes `feature_list.json` and repeats **implement → out-of-model verify → regression → commit** unattended. Cross-platform (Python + subprocess, no SDK).

```bash
python3 scripts/autoloop.py --project . --regress "pytest -q"   # or scripts/autoloop.sh / .ps1 / .bat
python3 scripts/autoloop.py --project . --dry-run               # control flow only, no claude

# Isolated container operation (recommended) — build the image, mount plugin ro, inject credentials
docker build -t omniharness-autoloop docker/

# Nightly scheduled operation — colima up → credential injection → container run → logs → cleanup, in one script
bash scripts/nightly.sh          # set OMNI_TARGET to pick the project (register with launchd/cron)
```

> **Caution**: the default `--permission-mode` is `bypassPermissions` (so the evaluator can actually run tests) — run **only in an isolated environment (container)**. In unattended environments, pin the claude binary with `CLAUDE_BIN`. Verified: 48 offline assertions + live-model (single run · forgery defense · multi-feature chain · regression-break detection · stall escalate/continue) + **an unattended run to completion inside an isolated container** + **nightly scheduled (launchd) operation** (completed features get a verify-first re-check instead of re-implementation). Five rules·blockers·ops lessons: [`docs/자동루프-설계.md`](docs/자동루프-설계.md).

## Verifying it works

- **Offline (no API key)**: `bash tests/run.sh` — 48 assertions feeding sample input to the hook/gate scripts
  (dangerous/secret blocked + **bypass cases**·over-block regressions, completion gate block/allow, handoff + **wiki-index** injection, skill nudge·quarantine·dedup·promote, stop-guard, next_feature, scaffold preserve/force, wiki-lint positive detection, two Stop hooks together, **autonomous-loop driver** (control flow·escalate·forgery-defense)).
- **Live integration (auth required)**: `bash tests/live.sh` — uses real `claude --plugin-dir` to verify hook *wiring* and e2e flows
  (Stop gate·`.env` block, **skill-capture e2e**, **wiki-ingest e2e**). Skips without auth. CI runs it only when the `ANTHROPIC_API_KEY` secret is set.
  - Advisory/enforced split: the model **writing** a candidate (advisory) is best-effort → WARN if absent; only the deterministic steps FAIL.
  - Enforced steps (`skill_gate` quarantine·no auto-activation·`promote`, `wiki_lint` clean) are asserted by **the harness invoking the scripts directly** — under headless `-p`, running a script outside the working dir hits a permission prompt that would otherwise mask the enforced step.
  - **SessionStart injection (handoff·wiki index) is best-effort (WARN) in the live test** — under single-shot `-p`, `additionalContext` reaching the model is unreliable (measured ~50%, 0/6 across six consecutive runs). The **enforced assertion lives offline** (`session_context.py` run directly, at the hook-output level).
- **Demonstrated**: SessionStart handoff·wiki-index **injection deterministically confirmed at hook-output level** (live model reach is intermittent),
  the Stop gate **actually blocking** an unverified completion (allow after PASS),
  PreToolUse **actually blocking** `dd if=` and **`cat .env`** (no `.env` leak), `skill_nudge` suggestion **actually injected**,
  model-written candidate → `skill_gate` **actually quarantined** (inactive until promote, active after `promote`), model-written wiki page → `wiki_lint` **actually clean**.

## Folder layout

```
.claude-plugin/{plugin.json, marketplace.json}   # plugin info
hooks/hooks.json                                 # registers SessionStart·PreToolUse·PostToolUse·Stop
scripts/                                          # hook·gate·util scripts (individual scripts)
  policy.py audit.py stop_guard.py verify_gate.py session_context.py skill_nudge.py
  skill_gate.py promote.py wiki_lint.py next_feature.py scaffold.sh scaffold.ps1
  autoloop.py autoloop.sh autoloop.ps1 autoloop.bat  # (experimental) outside-session autonomous driver
docker/Dockerfile                                 # (experimental) isolated image for the autonomous loop
agents/evaluator.md                               # independent evaluation subagent
skills/{init,verify,skillify,promote,wiki-ingest,wiki-lint}/SKILL.md
templates/                                        # starter files init copies into your project
docs/                                             # design rationale
tests/run.sh                                      # offline check (48 assertions)
tests/live.sh                                     # live integration smoke (auth / CI-guarded)
```
