---
name: init
description: 현재 프로젝트에 omniharness 하네스를 스캐폴드한다 — AGENTS.md(헌법)·.claude/settings.json(권한)·wiki·feature_list.json·init.sh·claude-progress.txt. 새 프로젝트를 하네스로 만들 때 사용.
---

# init — 프로젝트를 하네스로

헌법·권한·위키·장기실행 인계 아티팩트를 스캐폴드한다(기존 파일은 보존):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh"
```

스캐폴드되는 것:
- **`AGENTS.md`** — 카파시 헌법 + 위키 스키마 + 세션 의례 (Claude Code가 네이티브 로드).
- **`.claude/settings.json`** — 권한 deny/ask (PreToolUse 훅과 함께 2겹 강제).
- **`wiki/`**, **`sources/`** — 카파시 위키.
- **`feature_list.json`**, **`init.sh`**, **`claude-progress.txt`** — 장기실행 인계.

## 다음 단계
1. `feature_list.json`을 목표 기능들(검증 단계 포함, `passes:false`)로 채운다.
2. **한 세션에 한 기능만** 작업한다(`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/next_feature.py"`로 확인).
3. 기능을 검증(가능하면 `evaluator` 서브에이전트로 독립 검증)한 뒤에만 `passes:true` → 커밋 → `claude-progress.txt` 갱신.
