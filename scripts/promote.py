#!/usr/bin/env python3
"""격리 스킬을 활성으로 승격 + content-hash 버전 기록.

사용: python3 promote.py <name>   (CLAUDE_PROJECT_DIR=프로젝트루트)
skills-proposed/<name> → .claude/skills/<name> 이동, skill-versions.json에 기록.
"""
import datetime
import hashlib
import json
import os
import shutil
import sys


def main():
    if len(sys.argv) < 2:
        print("ERROR: 사용법 promote.py <name>")
        sys.exit(1)
    root = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    name = sys.argv[1]
    src = os.path.join(root, ".claude", "skills-proposed", name, "SKILL.md")
    if not os.path.exists(src):
        print(f"ERROR: 격리된 스킬 없음: {name}")
        sys.exit(1)
    content = open(src, encoding="utf-8").read()
    dest = os.path.join(root, ".claude", "skills", name)
    os.makedirs(dest, exist_ok=True)
    open(os.path.join(dest, "SKILL.md"), "w", encoding="utf-8").write(content)
    shutil.rmtree(os.path.join(root, ".claude", "skills-proposed", name))
    vpath = os.path.join(root, ".claude", "skill-versions.json")
    idx = json.load(open(vpath, encoding="utf-8")) if os.path.exists(vpath) else {}
    entries = idx.setdefault(name, [])
    entries.append({
        "version": len(entries) + 1,
        "op": "promoted",
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(),
    })
    json.dump(idx, open(vpath, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"PROMOTED: {name} -> {dest}/SKILL.md (v{len(entries)})")


if __name__ == "__main__":
    main()
