#!/usr/bin/env python3
"""Stop 훅 — feature_list.json에 미통과 기능이 남으면 종료를 차단(계속 진행) (GAP §4: 조기완료 방지).

opt-in: feature_list.json이 있고 미통과 항목이 있을 때만 발동. 없으면 개입하지 않는다.
보완 가정(GAP §4.3): 모델이 일을 다 안 끝내고 종료 선언 → 모델이 끈질겨지면 이 가드 완화 검토.
"""
import json
import os
import sys


def main():
    try:
        json.load(sys.stdin)  # 입력 소비
    except Exception:
        pass
    root = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    fl = os.path.join(root, "feature_list.json")
    if not os.path.exists(fl):
        sys.exit(0)
    try:
        feats = json.load(open(fl, encoding="utf-8"))
    except Exception:
        sys.exit(0)
    pending = [f for f in feats if isinstance(f, dict) and not f.get("passes")]
    if pending:
        print(json.dumps({
            "decision": "block",
            "reason": f"미통과 기능 {len(pending)}개 남음(예: {pending[0].get('description','')}). "
                      "한 기능을 완료·검증·커밋한 뒤 종료하라.",
        }))
    sys.exit(0)


if __name__ == "__main__":
    main()
