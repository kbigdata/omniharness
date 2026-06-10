#!/usr/bin/env python3
"""스킬 게이트 — 자기생성 스킬 후보를 활성화 전에 거른다 (GAP: 자기생성=untrusted source).

정리(펜스/머리말) → 파싱(name·description) → 안전 deny-list → dedup(이름·어휘 Jaccard)
→ $CLAUDE_PROJECT_DIR/.claude/skills-proposed/<name>/SKILL.md 격리. 통과해도 *격리*일 뿐.

사용: python3 skill_gate.py <candidate.md>   (없으면 stdin)
종료코드: 0=PROPOSED, 1=REJECTED. 단일 게이트 스크립트(프레임워크 아님).
"""
import os
import re
import sys

UNSAFE = (
    "api_key", "apikey", "anthropic_api_key", "password", "secret", "exfiltrat",
    "rm -rf", "/etc/passwd", "base64 -d", "curl http", "wget http", "force-push",
)
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
WORD = re.compile(r"\w+", re.UNICODE)
CJK = re.compile(r"[가-힣一-鿿]+")
FM_LINE = re.compile(r"(?m)^---[ \t]*$")
FENCE = re.compile(r"```[a-zA-Z0-9]*\s*\n(.*?)```", re.DOTALL)


def tokens(text):
    low = text.lower()
    t = set(WORD.findall(low))
    for run in CJK.findall(low):
        if len(run) == 1:
            t.add(run)
        t.update(run[i:i + 2] for i in range(len(run) - 1))
    return t


def jaccard(a, b):
    if not a or not b:
        return 0.0
    u = len(a | b)
    return len(a & b) / u if u else 0.0


def clean(md):
    md = md.strip()
    f = FENCE.search(md)
    if f and "---" in f.group(1):
        md = f.group(1).strip()
    if not md.startswith("---"):
        m = FM_LINE.search(md)
        if m:
            md = md[m.start():]
    return md.strip()


def parse(md):
    if not md.startswith("---"):
        raise ValueError("frontmatter('---')로 시작해야 함")
    parts = md.split("---", 2)
    if len(parts) < 3:
        raise ValueError("frontmatter 종료 구분자 없음")
    meta = {}
    for ln in parts[1].splitlines():
        if ":" in ln:
            k, v = ln.split(":", 1)
            meta[k.strip()] = v.strip().strip('"').strip("'")
    name, desc = meta.get("name", ""), meta.get("description", "")
    if not name or not desc:
        raise ValueError("name·description 필수")
    return name, desc


def active_skills(root):
    base = os.path.join(root, ".claude", "skills")
    out = []
    if os.path.isdir(base):
        for n in sorted(os.listdir(base)):
            p = os.path.join(base, n, "SKILL.md")
            if os.path.exists(p):
                out.append((n, open(p, encoding="utf-8").read()))
    return out


def reject(msg):
    print(msg)
    sys.exit(1)


def main():
    root = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    md = open(sys.argv[1], encoding="utf-8").read() if len(sys.argv) > 1 else sys.stdin.read()
    md = clean(md)
    try:
        name, _desc = parse(md)
    except ValueError as e:
        reject(f"REJECTED_INVALID: {e}")
    if not NAME_RE.match(name):
        reject(f"REJECTED_INVALID: 허용되지 않는 name {name!r}")
    low = md.lower()
    for t in UNSAFE:
        if t in low:
            reject(f"REJECTED_UNSAFE: unsafe token {t!r}")
    actives = active_skills(root)
    if any(n == name for n, _ in actives):
        reject(f"REJECTED_DUPLICATE: 이미 활성 스킬에 존재: {name}")
    ct = tokens(md)
    for n, text in actives:
        if jaccard(ct, tokens(text)) >= 0.6:
            reject(f"REJECTED_DUPLICATE: 의미 중복: {n}")
    dest = os.path.join(root, ".claude", "skills-proposed", name)
    os.makedirs(dest, exist_ok=True)
    open(os.path.join(dest, "SKILL.md"), "w", encoding="utf-8").write(md)
    print(f"PROPOSED: {name} -> {dest}/SKILL.md")
    sys.exit(0)


if __name__ == "__main__":
    main()
