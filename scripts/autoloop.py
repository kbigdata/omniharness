#!/usr/bin/env python3
"""완전 자율 루프 드라이버 (세션 *밖*) — Python + subprocess, 표준 라이브러리만.

Claude Code 플러그인(세션 안)이 못 하는 "세션 밖" 오케스트레이션만 얇게 채운다:
반복·인계 본문주입·모델밖 검증·회귀·기록·커밋·막힘감지. 네이티브(에이전트 루프·도구·
스킬·hooks·서브에이전트)는 재구현하지 않는다. 설계·근거: docs/자동루프-설계.md

5개 규율(안 지키면 자기평가 연극으로 퇴화):
  1) 검증·기록은 드라이버 단독 — 모델 세션에 record 권한을 주지 않는다.
  2) 인계는 `-p` 프롬프트 *본문*에 직접 주입 — SessionStart 훅에 의존하지 않는다(-p 도달 불안정).
  3) 검증은 `claude --agent evaluator` fresh 세션 — 생성 컨텍스트가 자기채점 못 하게.
  4) 회귀 패스 — evaluator 단일기능 한계 보완(A 통과 후 B가 A를 깨는 것).
  5) 타임아웃 + `--max-turns` — Stop 게이트 block 시에도 제어를 반드시 회복.

크로스플랫폼: claude/git 호출은 subprocess, 경로는 pathlib, 타임아웃은 subprocess(timeout=).
OS 분기 없음 — Linux/WSL/Windows에서 단일 코드로 동작.

사용:
  python3 autoloop.py [--project DIR] [--max-turns N] [--timeout S]
                      [--retries K] [--max-iters I] [--regress "명령"]
                      [--permission-mode MODE] [--dry-run]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent          # scripts/
VERIFY_GATE = HERE / "verify_gate.py"


def log(msg):
    print(f"[autoloop] {msg}", flush=True)


# ---- feature_list 상태 (드라이버가 단독으로 읽고 쓴다, 규율1·#C) ----

def load_features(root):
    fl = root / "feature_list.json"
    if not fl.exists():
        return None
    try:
        return json.loads(fl.read_text(encoding="utf-8"))
    except Exception:
        return None


def next_pending(features):
    for f in features:
        if isinstance(f, dict) and not f.get("passes"):
            return f
    return None


def set_passes(root, desc, value):
    """이 기능의 passes 를 드라이버가 강제 설정한다(#C). PASS면 True, FAIL/보류면 False —
    모델이 세션 중 디스크 passes 를 조작했더라도 드라이버 판정으로 덮어쓴다(규율1)."""
    fl = root / "feature_list.json"
    feats = json.loads(fl.read_text(encoding="utf-8"))
    for f in feats:
        if isinstance(f, dict) and f.get("description") == desc:
            f["passes"] = value
    fl.write_text(json.dumps(feats, ensure_ascii=False, indent=2), encoding="utf-8")


# ---- 인계 본문 주입 (규율2) ----

def build_handoff(root, desc):
    parts = ["omniharness 자율 루프 — 이전 작업을 이어갑니다."]
    prog = root / "claude-progress.txt"
    if prog.exists():
        tail = "\n".join(prog.read_text(encoding="utf-8").splitlines()[-15:]).strip()
        if tail:
            parts.append("## 최근 진행\n" + tail)
    idx = root / "wiki" / "index.md"
    if idx.exists():
        tail = "\n".join(idx.read_text(encoding="utf-8").splitlines()[-20:]).strip()
        if tail:
            parts.append("## 위키 인덱스 (행동 전 스캔)\n" + tail)
    parts.append(
        "## 이번 세션의 단일 작업\n다음 기능 **하나만** 구현하라. 완료 판정·검증기록은 "
        "드라이버가 세션 밖에서 한다 — 너는 구현에 집중하라(feature_list 를 직접 고치지 말 것).\n\n"
        f"기능: {desc}"
    )
    return "\n\n".join(parts)


# ---- claude 구동 (subprocess, 크로스플랫폼) ----

def claude_bin():
    b = shutil.which("claude")
    if not b:
        log("ERROR: claude CLI 를 PATH 에서 찾지 못함")
        sys.exit(2)
    return b


def run_claude(prompt, cwd, max_turns, timeout, permission_mode, agent=None, plugin_dir=None):
    """claude -p 단발 구동. agent 지정 시 --agent 로 그 서브에이전트를 fresh 세션으로.
    plugin_dir 지정 시 --plugin-dir 로 플러그인을 로드(evaluator 등 서브에이전트 인식에 필요)."""
    cmd = [claude_bin(), "-p", prompt, "--output-format", "text",
           "--permission-mode", permission_mode, "--max-turns", str(max_turns)]
    if plugin_dir:
        cmd += ["--plugin-dir", plugin_dir]
    if agent:
        cmd += ["--agent", agent]
    try:
        r = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, timeout=timeout)
        return r.stdout or ""
    except subprocess.TimeoutExpired:
        log(f"  (타임아웃 {timeout}s — 제어 회복, 규율5)")
        return ""


def parse_verdict(text):
    """evaluator 규약(evaluator.md): 최종 판정은 'PASS ...' 또는 'FAIL: <이유>'.
    뒤에서부터 첫 판정 라인을 신뢰한다 — 본문 중간의 'FAIL'/'PASS' 단어 오탐 방지.
    판정 라인이 없으면 보수적으로 FAIL."""
    for ln in reversed(text.splitlines()):
        s = ln.strip().lstrip("*#> ").strip()
        if s.startswith("FAIL") or "FAIL:" in s:
            return "FAIL"
        if s.startswith("PASS") or "PASS:" in s:
            return "PASS"
    return "FAIL"


# ---- 회귀 (규율4) ----

def run_regression(cmd, cwd, timeout):
    if not cmd:
        return True  # 회귀 명령 미지정 → 통과로 간주(로그로 알림)
    try:
        r = subprocess.run(cmd, cwd=str(cwd), shell=True, capture_output=True,
                           text=True, timeout=timeout)
        return r.returncode == 0
    except subprocess.TimeoutExpired:
        return False


# ---- 기록·커밋 (드라이버 단독, 규율1) ----

def record_pass(root, desc, evidence):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(root))
    subprocess.run([sys.executable, str(VERIFY_GATE), "--record", desc, "PASS", evidence[:300]],
                   env=env, capture_output=True, text=True)


def git_commit(root, desc):
    subprocess.run(["git", "-C", str(root), "add", "-A"], capture_output=True, text=True)
    subprocess.run(["git", "-C", str(root), "commit", "-m", f"feat: {desc} (autoloop 검증 통과)"],
                   capture_output=True, text=True)


def update_progress(root, desc):
    p = root / "claude-progress.txt"
    line = f"[autoloop] 완료·검증: {desc}\n"
    with p.open("a", encoding="utf-8") as f:
        f.write(line)


# ---- 메인 루프 ----

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=os.environ.get("CLAUDE_PROJECT_DIR", "."))
    ap.add_argument("--max-turns", type=int, default=30)
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--retries", type=int, default=2)
    ap.add_argument("--max-iters", type=int, default=100)
    ap.add_argument("--regress", default=os.environ.get("AUTOLOOP_REGRESS", ""))
    # 무인 자율은 격리 환경(컨테이너) 전제 — evaluator 가 Bash 로 테스트를 실제 실행하려면
    # bypass 가 필요하다(acceptEdits 는 편집만 자동수락, Bash 는 헤드리스에서 승인 차단됨).
    ap.add_argument("--permission-mode", default="bypassPermissions")
    ap.add_argument("--plugin-dir", default=os.environ.get("CLAUDE_PLUGIN_ROOT", ""),
                    help="플러그인 로드 경로(evaluator 서브에이전트 인식에 필요)")
    ap.add_argument("--dry-run", action="store_true",
                    help="claude/회귀/커밋 없이 제어흐름만 — 검증은 PASS 가정(오프라인 테스트용)")
    args = ap.parse_args()

    root = Path(args.project).resolve()
    feats = load_features(root)
    if feats is None:
        log("ERROR: feature_list.json 없음/파싱불가 — /omniharness:init 후 채우세요")
        sys.exit(1)

    # verified = 드라이버가 실제로 검증한 desc 집합. 이것이 통과의 *유일한 원천*이다 —
    # 디스크 feature_list 의 passes 는 모델이 조작할 수 있으므로 신뢰하지 않는다(규율1).
    retries, iters, skipped, verified = {}, 0, [], set()
    while iters < args.max_iters:
        feats = load_features(root)
        feat = next((f for f in feats if isinstance(f, dict)
                     and f.get("description") not in verified
                     and f.get("description") not in skipped), None)
        if feat is None:
            break
        iters += 1
        desc = feat.get("description", "")
        log(f"[{iters}] 작업: {desc}")

        if args.dry_run:
            # 구현·검증은 건너뛰고 PASS 가정하되, 회귀 명령은 실제 평가 → 실패/재시도/보류 경로 검증 가능.
            verdict, evidence = "PASS", "(dry-run)"
            regress_ok = run_regression(args.regress, root, args.timeout)
        else:
            pd = args.plugin_dir or None
            # 1) 구현 세션 — 인계 본문주입(규율2), --max-turns+timeout 로 제어회복(규율5)
            run_claude(build_handoff(root, desc), root, args.max_turns,
                       args.timeout, args.permission_mode, plugin_dir=pd)
            # 2) 검증 — fresh 격리 evaluator(규율3), 모델 밖(규율1)
            # evaluator 는 Read/Bash 로 테스트를 *직접 실행*해 검증한다(plan 모드면 도구 실행 불가 →
            # 검증 못 함). Write/Edit 은 evaluator 정의의 disallowedTools 가 막으므로 편집은 불가능.
            vout = run_claude(f"이 작업이 충족됐는지 작업트리만 보고 PASS/FAIL 로 판정하라.\n목표: {desc}",
                              root, args.max_turns, args.timeout, args.permission_mode,
                              agent="evaluator", plugin_dir=pd)
            verdict, evidence = parse_verdict(vout), vout.strip()
            # 3) 회귀(규율4)
            regress_ok = run_regression(args.regress, root, args.timeout)

        if verdict == "PASS" and regress_ok:
            verified.add(desc)                          # 드라이버 검증 원천(규율1)
            record_pass(root, desc, evidence)           # 드라이버 단독 기록(규율1)
            set_passes(root, desc, True)                # 드라이버 단독 갱신(#C)
            if not args.dry_run:
                git_commit(root, desc)
                update_progress(root, desc)
            log(f"    ✓ 통과·기록·커밋: {desc}")
            retries.pop(desc, None)
        else:
            set_passes(root, desc, False)               # 모델이 조작했을 passes 를 false 로 강제(규율1)
            retries[desc] = retries.get(desc, 0) + 1
            why = "회귀 실패" if verdict == "PASS" else f"검증 {verdict}"
            log(f"    ✗ {why} (재시도 {retries[desc]}/{args.retries})")
            if retries[desc] > args.retries:
                skipped.append(desc)
                log(f"    ⚠ 재시도 한도 초과 → 보류(escalate): {desc}")

    # 완료 판정도 verified 기준(디스크 passes 무시) — 모델 조작에 흔들리지 않는다.
    remaining = [f.get("description") for f in (load_features(root) or [])
                 if isinstance(f, dict) and f.get("description") not in verified]
    log("----")
    if not remaining:
        log("완료: 모든 기능 통과·검증·커밋")
        sys.exit(0)
    log(f"미완 {len(remaining)}개(보류/한도): {remaining}")
    sys.exit(1)


if __name__ == "__main__":
    main()
