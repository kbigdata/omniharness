#!/usr/bin/env python3
"""PreToolUse 강제 훅 — 파괴 명령·시크릿 접근을 deny (GAP §6/§7).

권한(settings.json)과 *독립*으로 작동하는 프로그램적 백스톱. 단일 훅 스크립트이며 프레임워크가 아니다.
보완 가정(GAP §4.3): 모델이 위험 명령을 제안할 수 있다 → 모델 발전과 무관하게 유지. deny-list만 점검.
"""
import json
import re
import sys

DESTRUCTIVE = (
    "rm -rf /", "rm -rf ~", "rm -rf *", "sudo ", "mkfs", "dd if=", ":(){",
    "> /dev/sd", "chmod -r 000", "git push --force", "force-push",
)
ASKABLE = ("git push", "git reset --hard", "git clean")
SECRET = re.compile(
    r"(^|/)\.(env|env\.[^/]+)$|/\.ssh/|/\.aws/credentials|id_rsa|\.pem$|/\.netrc$", re.I
)


def out(decision: str, reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}))
    sys.exit(0)


def main() -> None:
    try:
        d = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # 파싱 실패 시 개입하지 않음
    tool = d.get("tool_name", "")
    ti = d.get("tool_input", {}) or {}
    if tool == "Bash":
        cmd = str(ti.get("command", "")).lower()
        for p in DESTRUCTIVE:
            if p in cmd:
                out("deny", f"파괴적 명령 차단: {p!r}")
        for p in ASKABLE:
            if p in cmd:
                out("ask", f"승인 권장: {p!r}")
    if tool in ("Read", "Edit", "Write"):
        path = str(ti.get("file_path") or ti.get("path") or "")
        if SECRET.search(path):
            out("deny", f"시크릿 접근 차단: {path}")
    sys.exit(0)  # allow (무출력)


if __name__ == "__main__":
    main()
