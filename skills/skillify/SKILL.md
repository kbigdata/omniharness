---
name: skillify
description: 검증을 통과한 세션에서 재사용 가능한 패턴 1개를 Agent Skill 후보로 추출해 격리한다. 작업이 성공적으로 끝난 뒤 그 경험을 스킬로 굳히고 싶을 때 사용.
---

# skillify — Hermes 추출 → 결정론 게이트 → 격리

방금 **검증을 통과한** 세션에서, 다음에 또 쓸 **재사용 가능한 패턴 1개**를 추출한다.

## 절차
1. 재사용 패턴 후보를 아래 SKILL 마크다운으로 작성한다:
   ```
   ---
   name: <kebab-case>
   description: <언제 쓰는지 한 문장 — 트리거 조건 포함>
   ---
   <재사용 가능한 절차/체크리스트>
   ```
   - **일반화**: 이 세션 한정 값(경로·이름)은 제거·파라미터화한다. 일회성이면 추출하지 말고 멈춘다.
   - **안전**: 비밀·파괴 명령·외부 untrusted fetch를 넣지 않는다.
2. 후보를 임시 파일로 저장한다(예: `/tmp/skill_candidate.md`).
3. **결정론 게이트를 통과시킨다**(추출=창의적은 너가, 게이트=안전은 스크립트가):
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/skill_gate.py" /tmp/skill_candidate.md
   ```
   - `PROPOSED`면 `.claude/skills-proposed/<name>/`에 **격리**된다(자동 활성화 안 됨).
   - `REJECTED_*`면 사유를 보고하고 멈춘다 — 억지로 활성화하지 않는다.
4. 활성화는 사람의 일: `/omniharness:promote <name>`.
