#!/usr/bin/env bash
# 오프라인 검증 — Claude Code 없이 훅/게이트 스크립트에 샘플 JSON을 주입해 단언한다.
# (이 플러그인의 "테스트". pytest/Python 패키지 없음.)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
pass=0

ok()   { echo "  ok: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=1; }

# --- PreToolUse 권한 정책 ---
echo "== policy.py (PreToolUse 강제) =="
decision() {  # $1 desc  $2 expected(deny|ask|allow)  $3 json
  out="$(printf '%s' "$3" | python3 "$ROOT/scripts/policy.py")"
  if [ -z "$out" ]; then
    got="allow"
  else
    got="$(printf '%s' "$out" | python3 -c "import sys,json; print(json.load(sys.stdin)['hookSpecificOutput']['permissionDecision'])" 2>/dev/null || echo '?')"
  fi
  [ "$got" = "$2" ] && ok "$1" || bad "$1 (기대 $2, 받음: $got)"
}
decision "rm -rf 차단"      deny  '{"tool_name":"Bash","tool_input":{"command":"rm -rf / now"}}'
decision "sudo 차단"        deny  '{"tool_name":"Bash","tool_input":{"command":"sudo apt update"}}'
decision "dd if= 차단"      deny  '{"tool_name":"Bash","tool_input":{"command":"dd if=/dev/zero of=/tmp/x"}}'
decision "git push ask"     ask   '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
decision "정상 명령 allow"  allow '{"tool_name":"Bash","tool_input":{"command":"pytest -q"}}'
decision ".env 읽기 차단"   deny  '{"tool_name":"Read","tool_input":{"file_path":"/proj/.env"}}'
decision ".ssh 차단"        deny  '{"tool_name":"Read","tool_input":{"file_path":"/home/u/.ssh/id_rsa"}}'
decision "정상 읽기 allow"  allow '{"tool_name":"Read","tool_input":{"file_path":"/proj/src/main.py"}}'

# --- PostToolUse 감사 ---
echo "== audit.py (PostToolUse 관측) =="
tmp="$(mktemp -d)"
printf '%s' '{"tool_name":"Write","session_id":"s1"}' | CLAUDE_PROJECT_DIR="$tmp" python3 "$ROOT/scripts/audit.py"
if [ -f "$tmp/.omniharness/audit.jsonl" ] && grep -q '"tool": "Write"' "$tmp/.omniharness/audit.jsonl"; then ok "감사 JSONL 기록"; else bad "감사 JSONL 미기록"; fi
rm -rf "$tmp"

# --- 스킬 게이트 (있으면) ---
if [ -f "$ROOT/scripts/skill_gate.py" ]; then
  echo "== skill_gate.py =="
  bash "$ROOT/tests/gate.sh" || fail=1
fi

# --- Stop 가드 + 스캐폴드 ---
echo "== stop_guard.py (Stop 가드) =="
t="$(mktemp -d)"
printf '[{"description":"A","passes":false}]' > "$t/feature_list.json"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$t" python3 "$ROOT/scripts/stop_guard.py")"
printf '%s' "$out" | grep -q '"decision"' && ok "미통과 → 종료 차단" || bad "stop block (out=$out)"
printf '[{"description":"A","passes":true}]' > "$t/feature_list.json"
out2="$(printf '{}' | CLAUDE_PROJECT_DIR="$t" python3 "$ROOT/scripts/stop_guard.py")"
[ -z "$out2" ] && ok "전부 통과 → 종료 허용" || bad "stop allow (out=$out2)"
rm -rf "$t"

echo "== verify_gate.py (완료 게이트) =="
t3="$(mktemp -d)"
printf '[{"description":"f1","passes":true}]' > "$t3/feature_list.json"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py")"
printf '%s' "$out" | grep -q '"decision"' && ok "미검증 완료 → 종료 차단" || bad "verify_gate block (out=$out)"
CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py" --record "f1" PASS "근거" >/dev/null
out2="$(printf '{}' | CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py")"
[ -z "$out2" ] && ok "PASS 기록 후 → 종료 허용" || bad "verify_gate allow (out=$out2)"
CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py" --record "f1" FAIL "이유" >/dev/null
out3="$(printf '{}' | CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py")"
printf '%s' "$out3" | grep -q '"decision"' && ok "FAIL 기록 → 여전히 차단" || bad "verify_gate fail (out=$out3)"
rm -rf "$t3"

echo "== skill_nudge.py (트리거형 캡처 유도) =="
t4="$(mktemp -d)"
printf '[{"description":"f1","passes":true}]' > "$t4/feature_list.json"
# 검증 기록 없으면 유도 안 함
out0="$(printf '{}' | CLAUDE_PROJECT_DIR="$t4" python3 "$ROOT/scripts/skill_nudge.py")"
[ -z "$out0" ] && ok "미검증이면 유도 안 함" || bad "nudge premature (out=$out0)"
CLAUDE_PROJECT_DIR="$t4" python3 "$ROOT/scripts/verify_gate.py" --record "f1" PASS "근거" >/dev/null
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$t4" python3 "$ROOT/scripts/skill_nudge.py")"
printf '%s' "$out" | grep -q 'skillify' && ok "검증완료 → skillify 유도" || bad "nudge (out=$out)"
out2="$(printf '{}' | CLAUDE_PROJECT_DIR="$t4" python3 "$ROOT/scripts/skill_nudge.py")"
[ -z "$out2" ] && ok "중복 유도 안 함" || bad "nudge dedup (out=$out2)"
rm -rf "$t4"

echo "== session_context.py (인계 자동 주입) =="
t5="$(mktemp -d)"
printf '세션1: 기반 구축 완료\n' > "$t5/claude-progress.txt"
printf '[{"description":"f1","passes":false}]' > "$t5/feature_list.json"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$t5" python3 "$ROOT/scripts/session_context.py")"
printf '%s' "$out" | python3 -c "import sys,json;d=json.load(sys.stdin);assert d['hookSpecificOutput']['hookEventName']=='SessionStart' and d['hookSpecificOutput']['additionalContext']" 2>/dev/null \
  && ok "진행상황 additionalContext 주입" || bad "session_context (out=$out)"
# 관련 파일 전무하면 무개입
t5b="$(mktemp -d)"
out2="$(printf '{}' | CLAUDE_PROJECT_DIR="$t5b" python3 "$ROOT/scripts/session_context.py")"
[ -z "$out2" ] && ok "인계자료 없으면 무개입" || bad "session_context empty (out=$out2)"
rm -rf "$t5" "$t5b"

echo "== scaffold.sh (init) =="
t2="$(mktemp -d)"
CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/scripts/scaffold.sh" "$t2" >/dev/null
{ [ -f "$t2/AGENTS.md" ] && [ -f "$t2/.claude/settings.json" ] && [ -f "$t2/feature_list.json" ] && [ -f "$t2/wiki/index.md" ]; } \
  && ok "프로젝트 스캐폴드" || bad "scaffold"
# 위키 lint (스캐폴드 직후 깨끗)
CLAUDE_PROJECT_DIR="$t2" python3 "$ROOT/scripts/wiki_lint.py" | grep -q "이슈 없음" && ok "wiki_lint clean" || bad "wiki_lint"
rm -rf "$t2"

# --- JSON 유효성 ---
echo "== JSON 유효성 =="
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  python3 -c "import json;json.load(open('$ROOT/$f'))" 2>/dev/null && ok "json $f" || bad "json $f"
done

echo "----"
echo "통과 $pass / 실패 $([ $fail -eq 0 ] && echo 0 || echo '있음')"
exit $fail
