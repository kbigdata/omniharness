# omniharness — a safety-net plugin for Claude Code

[![CI](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml/badge.svg)](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/kbigdata/omniharness?sort=semver)](https://github.com/kbigdata/omniharness/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![No Python framework](https://img.shields.io/badge/python-framework--free-blue)

*[한국어 README](README.md)*

**omniharness** adds **safety guards and automatic checks** to Claude Code.
Once installed, in any project Claude will:

- 💥 **Block dangerous commands automatically** — e.g. `rm -rf /`, `sudo`, reading secrets (`.env`, `id_rsa`)
- 🔍 **Have its work checked by a separate agent** — not the one that did the work, but a fresh agent that didn't see the process and only reviews the result
- 🔄 **Resume long tasks after an interruption** — picks up from saved progress and the remaining to-do list
- 📚 **Turn repeated work into reusable skills, and accumulate what it learns into a wiki**

> What you install is just a few Markdown, JSON, and shell files. (No Python package.)

---

## What it does for you

> *A hook = a user script Claude Code runs automatically **right before / right after** using a tool, or **when it tries to stop**.*

| Feature | What it does | How it's built |
|---|---|---|
| **Block dangerous commands** | Reject `rm -rf /`, `sudo`, reading secrets, etc. **before** they run | Pre-tool hook + project permission settings (`.claude/settings.json`) — two layers |
| **Activity log** | Record every tool call Claude makes | Post-tool hook → `.omniharness/audit.jsonl` |
| **No early exit** | Block stopping while tasks remain | Stop hook → checks the to-do list (`feature_list.json`) |
| **Independent review** | A separate agent that **didn't see** the work judges the result pass/fail | Subagent (`agents/evaluator.md`) — runs read-only in a separate worktree |
| **Resume long tasks** | Continue across interruptions using progress files | `feature_list.json` · `claude-progress.txt` |
| **Skill automation** | Save a successful approach as a reusable skill (**a human must approve** to activate) | `/omniharness:skillify` → check → `/omniharness:promote` |
| **Knowledge wiki** | Accumulate verified learnings as wiki docs | `/omniharness:wiki-ingest` |
| **Working rules** | Auto-load good principles (think first · keep it simple · minimal changes · verify first) each session | `AGENTS.md` created by `init` |

## Install / local test

```bash
# install
/plugin marketplace add https://github.com/kbigdata/omniharness
/plugin install omniharness

# test a local, unpublished version
claude --plugin-dir /path/to/omniharness
```

## Usage

```
/omniharness:init               # create starter files in the current project (rules, permissions, wiki, progress)
# (then, while working) dangerous commands are auto-blocked; results are reviewed by a separate agent
/omniharness:skillify           # save a successful task as a reusable skill candidate
/omniharness:promote <name>     # activate a skill after human review
/omniharness:wiki-ingest        # record verified learnings into the wiki
/omniharness:wiki-lint          # check whether wiki content has drifted from reality
```

## Verifying it works

- **Offline (no API key)**: `bash tests/run.sh`
  — feeds sample input to the hook scripts and asserts correct behavior
  (dangerous/secret **blocked**, normal command **allowed**, activity logged, skill save/dedup/activate, stop-guard, starter files).
- **Real Claude Code**: run `claude --plugin-dir .` and confirm a dangerous command is **actually blocked**.

## Folder layout

```
.claude-plugin/{plugin.json, marketplace.json}   # plugin info
hooks/hooks.json                                 # which hooks run when
scripts/*.py, scaffold.sh                         # hook / check / init scripts (individual scripts, not a framework)
agents/evaluator.md                               # independent review agent
skills/{init,skillify,wiki-ingest,promote,wiki-lint}/SKILL.md
templates/                                        # starter files init copies into your project
docs/                                             # design rationale
tests/run.sh                                      # offline check
```
