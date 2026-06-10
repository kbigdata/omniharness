#!/usr/bin/env python3
"""PostToolUse 훅 — 검증 통과한 기능을 보고 스킬 캡처를 '유도'(컨텍스트 주입)한다.

자동 생성이 아니다. 트리거형 제안: passes:true + PASS 검증기록 + 아직 미제안이면
additionalContext로 /omniharness:skillify 를 안내. 한 번 제안하면 .omniharness/nudged.json에
기록해 중복 제안을 막는다. 추출·게이트·승인은 그대로 사람/모델의 일.
보완 가정: 성공 경험을 재사용 자산으로 굳히는 걸 모델이 잊는다 → 훅이 적시에 상기시킨다.
"""
import hashlib
import json
import os
import sys


def fid(desc):
    return hashlib.sha256(desc.strip().encode("utf-8")).hexdigest()[:12]


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
    npath = os.path.join(root, ".omniharness", "nudged.json")
    try:
        nudged = set(json.load(open(npath, encoding="utf-8")))
    except Exception:
        nudged = set()
    vdir = os.path.join(root, ".omniharness", "verify")
    for f in feats:
        if not (isinstance(f, dict) and f.get("passes")):
            continue
        desc = f.get("description", "")
        i = fid(desc)
        if i in nudged:
            continue
        vp = os.path.join(vdir, i + ".json")
        if not os.path.exists(vp):
            continue
        try:
            if json.load(open(vp, encoding="utf-8")).get("verdict") != "PASS":
                continue
        except Exception:
            continue
        nudged.add(i)
        os.makedirs(os.path.dirname(npath), exist_ok=True)
        json.dump(sorted(nudged), open(npath, "w", encoding="utf-8"))
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": f"'{desc}'가 검증을 통과해 완료됐습니다. 다시 쓸 만한 *재사용* "
            "절차였다면 /omniharness:skillify 로 스킬 후보를 만들어 두세요"
            "(결정론 게이트 통과 + 사람 승인 후에만 활성화). 일회성이면 그냥 넘어가세요.",
        }}))
        sys.exit(0)
    sys.exit(0)


if __name__ == "__main__":
    main()
