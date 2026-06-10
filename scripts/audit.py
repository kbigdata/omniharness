#!/usr/bin/env python3
"""PostToolUse 관측 훅 — 도구호출을 프로젝트 .omniharness/audit.jsonl에 append (GAP §3.6).

자율 운영의 감사 추적. 단일 훅 스크립트.
"""
import datetime
import json
import os
import sys


def main() -> None:
    try:
        d = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    root = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    path = os.path.join(root, ".omniharness", "audit.jsonl")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    ev = {
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "event": "post_tool_use",
        "tool": d.get("tool_name"),
        "session_id": d.get("session_id"),
    }
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(ev, ensure_ascii=False) + "\n")
    sys.exit(0)


if __name__ == "__main__":
    main()
