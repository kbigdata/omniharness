#!/usr/bin/env python3
"""위키 drift 점검 — frontmatter 누락·잘못된 status·고아(orphan) 페이지 (GAP §4.3).

사용: python3 wiki_lint.py [wiki_dir]   (기본 $CLAUDE_PROJECT_DIR/wiki)
종료코드: 0=이슈 없음, 1=이슈 있음.
"""
import os
import sys

REQUIRED = ("title", "updated", "source", "status")
VALID_STATUS = {"active", "stale", "deprecated"}
SKIP = {"index.md", "log.md"}


def frontmatter(text):
    if not text.startswith("---"):
        return None
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None
    meta = {}
    for ln in parts[1].splitlines():
        if ":" in ln:
            k, v = ln.split(":", 1)
            meta[k.strip()] = v.strip().strip('"').strip("'")
    return meta


def main():
    wiki = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.environ.get("CLAUDE_PROJECT_DIR", "."), "wiki"
    )
    if not os.path.isdir(wiki):
        print("(위키 없음)")
        sys.exit(0)
    index = ""
    idx_path = os.path.join(wiki, "index.md")
    if os.path.exists(idx_path):
        index = open(idx_path, encoding="utf-8").read()
    issues = []
    for dirpath, _dirs, files in os.walk(wiki):
        for fn in files:
            if not fn.endswith(".md") or fn in SKIP:
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, wiki)
            fm = frontmatter(open(full, encoding="utf-8").read())
            if fm is None:
                issues.append((rel, "missing_frontmatter", ""))
            else:
                for field in REQUIRED:
                    if field not in fm:
                        issues.append((rel, "missing_field", field))
                if fm.get("status") not in VALID_STATUS:
                    issues.append((rel, "bad_status", str(fm.get("status"))))
            stem = os.path.splitext(fn)[0]
            if stem not in index and rel not in index:
                issues.append((rel, "orphan", ""))
    if not issues:
        print("위키 lint: 이슈 없음 ✓")
        sys.exit(0)
    for page, kind, detail in issues:
        print(f"[{kind}] {page}" + (f" ({detail})" if detail else ""))
    sys.exit(1)


if __name__ == "__main__":
    main()
