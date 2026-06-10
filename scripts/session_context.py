#!/usr/bin/env python3
"""SessionStart 훅 — 인계 컨텍스트를 세션 시작 시 자동 주입한다.

claude-progress.txt(최근) + feature_list 진행/다음 + wiki/index.md + git log를 모아
additionalContext로 내보낸다 → '긴 작업 이어가기'가 모델 권고가 아니라 세션 시작 시 자동 노출.
관련 파일이 하나도 없으면 조용히 무개입.
보완 가정(GAP §9): 세션이 바뀌면 모델은 이전 진행을 모른다 → 디스크에서 읽어 떠먹인다.
"""
import json
import os
import subprocess
import sys


def tail(path, n):
    try:
        return "\n".join(open(path, encoding="utf-8").read().splitlines()[-n:]).strip()
    except Exception:
        return ""


def main():
    try:
        json.load(sys.stdin)  # 입력 소비
    except Exception:
        pass
    root = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    parts = []

    prog = tail(os.path.join(root, "claude-progress.txt"), 15)
    if prog:
        parts.append("## 최근 진행 (claude-progress.txt)\n" + prog)

    fl = os.path.join(root, "feature_list.json")
    if os.path.exists(fl):
        try:
            feats = json.load(open(fl, encoding="utf-8"))
            passed = sum(1 for f in feats if isinstance(f, dict) and f.get("passes"))
            nxt = next((f.get("description", "") for f in feats
                        if isinstance(f, dict) and not f.get("passes")), None)
            parts.append(f"## 기능 진행\n{passed}/{len(feats)} 통과. "
                         f"다음 작업: {nxt or '(없음 — 전부 통과)'}")
        except Exception:
            pass

    idx = os.path.join(root, "wiki", "index.md")
    if os.path.exists(idx):
        parts.append("## 위키 인덱스 (행동 전 스캔)\n" + tail(idx, 20))

    try:
        log = subprocess.run(
            ["git", "-C", root, "log", "--oneline", "-5"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        if log:
            parts.append("## 최근 커밋\n" + log)
    except Exception:
        pass

    if not parts:
        sys.exit(0)
    ctx = "omniharness 인계 — 이전 작업을 이어갑니다.\n\n" + "\n\n".join(parts)
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ctx.strip(),
    }}))
    sys.exit(0)


if __name__ == "__main__":
    main()
