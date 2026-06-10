---
name: promote
description: 격리된 스킬 후보(.claude/skills-proposed)를 검토 후 활성(.claude/skills)으로 승격한다. 사람이 자기생성 스킬을 활성화할 때.
---

# promote — 사람 승인 게이트

격리된 스킬은 사람이 검토해야 활성화된다(자기생성 스킬은 untrusted by default).

1. 후보 검토: `cat .claude/skills-proposed/$ARGUMENTS/SKILL.md`
2. 적절하면 승격: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/promote.py" "$ARGUMENTS"`
   → `.claude/skills/$ARGUMENTS/`로 이동 + content-hash 버전 기록.
   다음 세션부터 Claude Code가 **네이티브로** 이 스킬을 집어 쓴다.
