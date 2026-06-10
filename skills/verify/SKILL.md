---
name: verify
description: 방금 끝낸 기능을 독립 평가자(evaluator)로 검증하고 결과를 기록한다. 완료를 주장하기 전에 호출하라 — 검증 기록이 없으면 omniharness 완료 게이트가 세션 종료를 막는다.
---

# verify — 독립 검증 + 기록

자기 작업을 스스로 "됐다"고 하지 않는다. 생성 과정을 **못 본** 독립 평가자에게 맡긴다.

## 절차
1. 평가할 목표를 한 문장으로 정한다 — `feature_list.json`의 해당 `description`과 **글자 그대로 동일**하게(기록 id가 description으로 계산됨).
2. **evaluator 서브에이전트를 호출**한다(이 플러그인의 `evaluator`). 목표·수용 기준을 주고 PASS/FAIL 판정과 근거를 받는다.
3. 판정을 기록한다(완료 게이트가 이 기록을 본다):
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/verify_gate.py" --record "<feature description>" PASS "<근거 요약>"
   # FAIL이면:  ... --record "<feature description>" FAIL "<실패 이유>"
   ```
4. PASS면 `feature_list.json`의 해당 항목을 `passes:true`로. FAIL이면 고친 뒤 2부터 다시.

## 왜 강제인가
완료 게이트(`scripts/verify_gate.py`, Stop 훅)는 **PASS 기록 없는 `passes:true`를 발견하면 종료를 차단**한다.
따라서 독립 검증은 "권고"가 아니라 **완료의 전제조건**이다.
(한계: 게이트는 기록의 *존재*만 강제한다. evaluator를 건너뛰고 기록을 위조하는 우회는 막지 못한다 — 정직히 밝힌다.)
