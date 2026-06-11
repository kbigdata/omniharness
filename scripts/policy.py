#!/usr/bin/env python3
"""PreToolUse 강제 훅 — 파괴 명령·시크릿 접근을 deny (GAP §6/§7).

**최선노력(best-effort) 백스톱이지 샌드박스가 아니다.** deny-list/패턴은 본질적으로 불완전하며
난독화·base64·대체 도구로 우회할 수 있다. 진짜 경계는 Claude Code 권한 + `.claude/settings.json`
+ 신뢰 못 할 코드를 애초에 실행하지 않는 것이다. 여기서는 *흔한 사고와 직접적 시크릿 접근*을 잡는다.
권한 설정과 *독립*으로 작동하는 프로그램적 백스톱. 단일 훅 스크립트이며 프레임워크가 아니다.
보완 가정(GAP §4.3): 모델이 위험 명령을 제안할 수 있다 → 모델 발전과 무관하게 유지.
"""
import json
import re
import sys

# rm 외 파괴 명령(공백 정규화된 소문자 cmd에 substring)
DESTRUCTIVE = (
    "sudo ", "mkfs", "dd if=", ":(){", "> /dev/sd", "chmod -r 000",
    "git push --force", "force-push",
)
ASKABLE = ("git push", "git reset --hard", "git clean")

# rm -rf 가 향하면 위험한 대상
RM_TARGETS = {"/", "~", "*", "/*", "$home", "${home}", '"$home"', "'$home'"}

# --- Windows / PowerShell 보강 ---
# PowerShell 파괴 명령 — 공백 정규화·소문자 cmd에 substring (cmd.exe rd/rmdir 패스스루 포함)
PS_DESTRUCTIVE = (
    "format-volume", "clear-disk", "stop-computer", "restart-computer",
    "set-executionpolicy", "rd /s", "rmdir /s", "del /s", "del /q",
)
# PowerShell 삭제 명령 토큰(별칭 포함) — Remove-Item 및 그 alias
PS_DELETE_VERBS = {"remove-item", "ri", "rm", "del", "erase", "rd", "rmdir", "rmi"}
PS_RECURSE = {"-recurse", "-rec", "-r"}
PS_FORCE = {"-force", "-fo", "-f"}
# Remove-Item 등이 향하면 위험한 대상(소문자·따옴표 제거 후 비교)
PS_RM_TARGETS = {
    "c:", "c:\\", "d:", "d:\\", "e:", "e:\\", "/", "~", "*",
    "$home", "${home}", "$env:userprofile", "$env:homepath",
    "$env:systemroot", "$env:windir", "c:\\windows", "c:\\users",
}

# 시크릿 파일을 명령줄에서 직접 참조 (cat .env, Get-Content .env, scp id_rsa 등) — 도구 우회 차단.
# .env.example/.sample/.template/.dist 등 안전 템플릿은 허용(과차단 방지). 슬래시·백슬래시 모두 인식.
SECRET_IN_CMD = re.compile(
    r"(^|[\s=:/'\"\\])\.env(?!\.(?:example|sample|template|dist|defaults)\b)(?:\.[^\s'\"/\\]+)?\b"
    r"|[/\\]\.ssh[/\\]|\bid_rsa\b|\bid_ed25519\b|\.pem\b"
    r"|[/\\]\.aws[/\\](?:credentials|config)\b|[/\\]\.netrc\b",
    re.I,
)
# Read/Edit/Write file_path 용 시크릿 경로 — 슬래시·백슬래시 모두 인식(Windows 경로 대응).
SECRET_PATH = re.compile(
    r"(^|[/\\])\.(env|env\.[^/\\]+)$|[/\\]\.ssh[/\\]|[/\\]\.aws[/\\]credentials"
    r"|id_rsa|id_ed25519|\.pem$|[/\\]\.netrc$",
    re.I,
)


def rm_is_dangerous(cmd_norm):
    """rm 이 recursive+force 로 위험 대상(/, ~, $HOME, *)을 지우는가. 플래그 순서·공백 무관."""
    toks = cmd_norm.split()
    for i, t in enumerate(toks):
        if t.rsplit("/", 1)[-1] != "rm":
            continue
        flags, args = "", []
        for t2 in toks[i + 1:]:
            if t2 in (";", "&&", "||", "|"):
                break
            if t2 == "--recursive":
                flags += "r"
            elif t2 == "--force":
                flags += "f"
            elif t2.startswith("-"):
                flags += t2
            else:
                args.append(t2)
        if "r" in flags and "f" in flags and any(a in RM_TARGETS for a in args):
            return True
    return False


def ps_remove_is_dangerous(cmd_norm):
    """PowerShell 삭제 명령이 recurse+force 로 위험 대상(드라이브 루트·$HOME·* 등)을 지우는가.

    파라미터 순서·약식 표기(-rec, -fo)·-Confirm:$false·배시 습관 -rf 까지 대응.
    """
    toks = cmd_norm.split()
    for i, t in enumerate(toks):
        if t not in PS_DELETE_VERBS:
            continue
        recurse = force = False
        args = []
        for t2 in toks[i + 1:]:
            if t2 in (";", "|", "&&", "||", "&"):
                break
            if t2 in PS_RECURSE or t2.startswith("-recurse"):
                recurse = True
            elif t2 in PS_FORCE:
                force = True
            elif t2.startswith("-confirm") and "false" in t2:
                force = True
            elif t2.startswith("-") and t2 != "-" and set(t2[1:]) <= {"r", "f"}:
                # -rf / -fr 같은 묶음 플래그(배시 습관)만 해석 — -filter 등 오탐 방지
                recurse = recurse or "r" in t2
                force = force or "f" in t2
            elif t2.startswith("-"):
                pass  # 기타 PowerShell 파라미터는 무시
            else:
                a = t2.strip("'\"")
                args.append(a)
                args.append(a.rstrip("\\"))  # 후행 백슬래시 변형(c:\ ↔ c:)
        if recurse and force and any(a in PS_RM_TARGETS for a in args):
            return True
    return False


def out(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}))
    sys.exit(0)


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # 파싱 실패 시 개입하지 않음
    tool = d.get("tool_name", "")
    ti = d.get("tool_input", {}) or {}
    if tool == "Bash":
        raw = str(ti.get("command", ""))
        cmd = " ".join(raw.lower().split())  # 공백 정규화 → `rm  -rf /` 같은 변형 차단
        if rm_is_dangerous(cmd):
            out("deny", "파괴적 rm 차단: recursive+force 가 위험 대상(/, ~, $HOME, *) 삭제")
        for p in DESTRUCTIVE:
            if p in cmd:
                out("deny", f"파괴적 명령 차단: {p!r}")
        if SECRET_IN_CMD.search(raw):
            out("deny", "시크릿 파일 접근 차단(명령줄에서 직접 참조)")
        for p in ASKABLE:
            if p in cmd:
                out("ask", f"승인 권장: {p!r}")
    if tool == "PowerShell":
        raw = str(ti.get("command", ""))
        cmd = " ".join(raw.lower().split())  # 공백 정규화 → 변형 차단
        if ps_remove_is_dangerous(cmd):
            out("deny", "파괴적 삭제 차단: PowerShell이 위험 대상(드라이브 루트, $HOME, *)을 recursive+force 삭제")
        for p in PS_DESTRUCTIVE:
            if p in cmd:
                out("deny", f"파괴적 명령 차단: {p!r}")
        if SECRET_IN_CMD.search(raw):
            out("deny", "시크릿 파일 접근 차단(명령줄에서 직접 참조)")
        for p in ASKABLE:
            if p in cmd:
                out("ask", f"승인 권장: {p!r}")
    if tool in ("Read", "Edit", "Write"):
        path = str(ti.get("file_path") or ti.get("path") or "")
        if SECRET_PATH.search(path):
            out("deny", f"시크릿 접근 차단: {path}")
    sys.exit(0)  # allow (무출력)


if __name__ == "__main__":
    main()
