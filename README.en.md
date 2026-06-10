# omniharness — a harness plugin for Claude Code

[![CI](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml/badge.svg)](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/kbigdata/omniharness?sort=semver)](https://github.com/kbigdata/omniharness/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![No Python framework](https://img.shields.io/badge/python-framework--free-blue)

*[한국어 README](README.md)*

**omniharness** turns Claude Code into a workspace that **controls itself, accumulates what it learns,
and automates what it does well**. A single `/omniharness:init` gives any project these three pillars:

| | Pillar | One line |
|---|---|---|
| 🛡️ | **Harness** | Blocks dangerous commands, reviews results independently, resumes long tasks after interruptions |
| 📚 | **Wiki** | Accumulates verified learnings as docs to reuse in later work |
| 🤖 | **Hermes — skill automation** | Auto-extracts successful work into reusable skills (activated only after human approval) |

> What you install is just a few Markdown, JSON, and shell files. (No Python package.)

---

## 🛡️ Harness — control and verification

**What's a harness?** A control layer that applies *rules, blocking, and verification* when you hand a task to an LLM.
The model is capable, but it sometimes runs dangerous commands, convinces itself its own output is "good,"
and stops a long task halfway. A harness catches these **by force**.

> *A hook = a script Claude Code runs automatically right before/after using a tool, or when it tries to stop.*

| Feature | Why you need it | How it works |
|---|---|---|
| **Block dangerous commands** | The model may accidentally run `rm -rf /`, `sudo`, or read secrets (`.env`, `id_rsa`) | A hook inspects and rejects **before** the tool runs + project permission settings — two layers |
| **Independent review** | The agent that did the work can't judge its own output objectively (self-eval bias) | A separate agent that **didn't see** the process judges the result pass/fail |
| **Resume long tasks** | Session end / context limits cut long tasks short | Resumes from progress + to-do files; **also blocks stopping** while tasks remain |
| **Working rules** | Repeating "think first · keep it simple · minimal changes · verify first" every time is tedious | Written in `AGENTS.md`, **auto-loaded each session** |
| **Activity log** | You need to track and audit what was done | Records every tool call to `.omniharness/audit.jsonl` |

## 📚 Wiki — accumulate what you learn

**What is it?** Verified learnings from the project ("this module works like X", "watch out for trap Y")
accumulated as structured wiki docs.

**Why you need it?** Claude forgets what it learned once a session ends. Without a wiki, the next session
re-explores the same code and repeats the same mistakes. With one, later work references it directly and is
**faster and more accurate**. (Inspired by Andrej Karpathy's idea of an "agent-maintained knowledge wiki".)

```
/omniharness:wiki-ingest        # record verified learnings into the wiki
/omniharness:wiki-lint          # check whether the wiki has drifted from the current code
```

## 🤖 Hermes — automatic skill generation

**What is it?** Auto-extracts a once-successful procedure into a reusable "skill".

**Why you need it?** Re-explaining and redoing the same kind of task from scratch every time is wasteful.
Save a success as a skill and you can **reuse it with one call** next time.

**Safety** — extracted skills are *not* turned on automatically. They're quarantined as candidates and
require **human review and approval** to activate, so unverified skills are never applied blindly.

```
/omniharness:skillify           # successful task → reusable skill candidate
/omniharness:promote <name>     # review, then activate
```

---

## Install

```bash
# install
/plugin marketplace add https://github.com/kbigdata/omniharness
/plugin install omniharness

# test a local, unpublished version
claude --plugin-dir /path/to/omniharness
```

## Usage

First, initialize once inside your project.

```
/omniharness:init
```

This creates the **harness, wiki, and skill starter files** (working rules, permission settings, progress files,
wiki folder). From then on, dangerous-command blocking and independent review apply automatically. The rest:

| Command | What it does |
|---|---|
| `/omniharness:skillify` | successful task → reusable skill candidate |
| `/omniharness:promote <name>` | review, then activate the skill |
| `/omniharness:wiki-ingest` | record verified learnings into the wiki |
| `/omniharness:wiki-lint` | check whether the wiki drifted from current code |

## Verifying it works

- **Offline (no API key)**: `bash tests/run.sh`
  — feeds sample input to the hook scripts and asserts correct behavior
  (dangerous/secret **blocked**, normal command **allowed**, activity logged, skill save/dedup/activate, stop-guard, starter files).
- **Real Claude Code**: run `claude --plugin-dir .` and confirm a dangerous command is **actually blocked**.

## Folder layout

```
.claude-plugin/{plugin.json, marketplace.json}   # plugin info
hooks/hooks.json                                 # which hooks run when
scripts/*.py, scaffold.sh                         # hook / check / init scripts
agents/evaluator.md                               # independent review agent
skills/{init,skillify,wiki-ingest,promote,wiki-lint}/SKILL.md
templates/                                        # starter files init copies into your project
docs/                                             # design rationale
tests/run.sh                                      # offline check
```
