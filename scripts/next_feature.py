#!/usr/bin/env python3
"""feature_list.json에서 미통과 최우선 기능 1개를 출력 (one-feature-per-session, GAP §9).

사용: python3 next_feature.py   (CLAUDE_PROJECT_DIR=프로젝트루트)
"""
import json
import os
import sys


def main():
    root = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    fl = os.path.join(root, "feature_list.json")
    if not os.path.exists(fl):
        print("(feature_list.json 없음 — /omniharness:init 후 채우세요)")
        sys.exit(0)
    feats = json.load(open(fl, encoding="utf-8"))
    passed = sum(1 for f in feats if isinstance(f, dict) and f.get("passes"))
    nxt = next((f for f in feats if isinstance(f, dict) and not f.get("passes")), None)
    print(f"진행: {passed}/{len(feats)} 통과")
    print(f"다음 기능: {nxt.get('description') if nxt else '(없음 — 전부 통과)'}")


if __name__ == "__main__":
    main()
