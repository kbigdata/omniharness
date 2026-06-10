#!/usr/bin/env python3
"""완료 게이트 — 독립 검증 없이 'passes:true'면 종료를 차단한다 (생성자=평가자 분리 강제).

두 모드:
  (Stop 훅) stdin 소비 → feature_list.json 스캔 → passes:true인데
            .omniharness/verify/<id>.json(verdict=PASS)이 없으면 {"decision":"block"}.
  --record "<feature desc>" PASS|FAIL ["근거"] → 검증기록 작성.

id = sha256(description.strip())[:12]. /omniharness:verify 가 evaluator 서브에이전트로
판정을 받아 이 스크립트로 기록한다. 게이트는 '기록 존재'를 완료의 전제로 만든다(위조 불가는 아님 — 정직히 표기).
보완 가정(GAP §10): 모델이 자기 결과를 검증 없이 '완료'로 선언(자기평가 편향).
"""
import datetime
import hashlib
import json
import os
import sys


def fid(desc):
    return hashlib.sha256(desc.strip().encode("utf-8")).hexdigest()[:12]


def vdir(root):
    return os.path.join(root, ".omniharness", "verify")


def is_pass(root, desc):
    p = os.path.join(vdir(root), fid(desc) + ".json")
    if not os.path.exists(p):
        return False
    try:
        return json.load(open(p, encoding="utf-8")).get("verdict") == "PASS"
    except Exception:
        return False


def record(root, desc, verdict, evidence):
    d = vdir(root)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, fid(desc) + ".json")
    json.dump(
        {
            "feature": desc.strip(),
            "verdict": verdict,
            "evidence": evidence,
            "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        },
        open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2,
    )
    print(f"RECORDED: {verdict} {fid(desc)} — {desc.strip()[:60]}")


def main():
    root = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    if sys.argv[1:2] == ["--record"]:
        if len(sys.argv) < 3:
            print("ERROR: 사용법 verify_gate.py --record \"<desc>\" PASS|FAIL [근거]")
            sys.exit(1)
        desc = sys.argv[2]
        verdict = (sys.argv[3] if len(sys.argv) > 3 else "PASS").upper()
        evidence = sys.argv[4] if len(sys.argv) > 4 else ""
        if verdict not in ("PASS", "FAIL"):
            print("ERROR: verdict는 PASS 또는 FAIL")
            sys.exit(1)
        record(root, desc, verdict, evidence)
        sys.exit(0)

    try:
        json.load(sys.stdin)  # Stop 훅 입력 소비
    except Exception:
        pass
    fl = os.path.join(root, "feature_list.json")
    if not os.path.exists(fl):
        sys.exit(0)
    try:
        feats = json.load(open(fl, encoding="utf-8"))
    except Exception:
        sys.exit(0)
    unverified = [
        f.get("description", "")
        for f in feats
        if isinstance(f, dict) and f.get("passes") and not is_pass(root, f.get("description", ""))
    ]
    if unverified:
        print(json.dumps({
            "decision": "block",
            "reason": f"검증 안 된 완료 {len(unverified)}개(예: {unverified[0]!r}). "
                      "각 기능을 /omniharness:verify 로 독립 검증(PASS 기록)한 뒤 종료하라.",
        }))
    sys.exit(0)


if __name__ == "__main__":
    main()
