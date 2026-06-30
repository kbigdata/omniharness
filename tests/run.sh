#!/usr/bin/env bash
# 오프라인 검증 — Claude Code 없이 훅/게이트 스크립트에 샘플 JSON을 주입해 단언한다.
# (이 플러그인의 "테스트". pytest/Python 패키지 없음.)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
pass=0

ok()   { echo "  ok: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=1; }
# 출력이 {"decision":"block"} 구조인지 (substring 아님)
is_block() { printf '%s' "$1" | python3 -c "import sys,json;sys.exit(0 if json.load(sys.stdin).get('decision')=='block' else 1)" 2>/dev/null; }

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

echo "== policy.py (우회/과차단 케이스) =="
decision "cat .env 차단"        deny  '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
decision "id_rsa 읽기 차단"     deny  '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}'
decision ".aws creds 차단"      deny  '{"tool_name":"Bash","tool_input":{"command":"cp /home/u/.aws/credentials /tmp/x"}}'
decision "rm 공백변형 차단"     deny  '{"tool_name":"Bash","tool_input":{"command":"rm  -rf  /"}}'
decision "rm -fr 차단"          deny  '{"tool_name":"Bash","tool_input":{"command":"rm -fr /"}}'
decision 'rm $HOME 차단'        deny  '{"tool_name":"Bash","tool_input":{"command":"rm -rf \"$HOME\""}}'
decision "rm --long 차단"       deny  '{"tool_name":"Bash","tool_input":{"command":"rm --recursive --force /"}}'
decision "rm 하위폴더 allow"    allow '{"tool_name":"Bash","tool_input":{"command":"rm -rf ./build"}}'
decision "rm 절대경로 allow"    allow '{"tool_name":"Bash","tool_input":{"command":"rm -rf /home/u/proj/dist"}}'
decision ".env.example allow"   allow '{"tool_name":"Bash","tool_input":{"command":"grep KEY .env.example"}}'
decision "npm run env allow"    allow '{"tool_name":"Bash","tool_input":{"command":"npm run env"}}'

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
is_block "$out" && ok "미통과 → 종료 차단" || bad "stop block (out=$out)"
printf '[{"description":"A","passes":true}]' > "$t/feature_list.json"
out2="$(printf '{}' | CLAUDE_PROJECT_DIR="$t" python3 "$ROOT/scripts/stop_guard.py")"
[ -z "$out2" ] && ok "전부 통과 → 종료 허용" || bad "stop allow (out=$out2)"
rm -rf "$t"

echo "== verify_gate.py (완료 게이트) =="
t3="$(mktemp -d)"
printf '[{"description":"f1","passes":true}]' > "$t3/feature_list.json"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py")"
is_block "$out" && ok "미검증 완료 → 종료 차단" || bad "verify_gate block (out=$out)"
CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py" --record "f1" PASS "근거" >/dev/null
out2="$(printf '{}' | CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py")"
[ -z "$out2" ] && ok "PASS 기록 후 → 종료 허용" || bad "verify_gate allow (out=$out2)"
CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py" --record "f1" FAIL "이유" >/dev/null
out3="$(printf '{}' | CLAUDE_PROJECT_DIR="$t3" python3 "$ROOT/scripts/verify_gate.py")"
is_block "$out3" && ok "FAIL 기록 → 여전히 차단" || bad "verify_gate fail (out=$out3)"
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
mkdir -p "$t5/wiki"
printf -- '---\ntitle: idx\n---\nWIKI_IDX_MARK 개념·엔티티 카탈로그\n' > "$t5/wiki/index.md"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$t5" python3 "$ROOT/scripts/session_context.py")"
printf '%s' "$out" | python3 -c "import sys,json;d=json.load(sys.stdin);c=d['hookSpecificOutput']['additionalContext'];assert d['hookSpecificOutput']['hookEventName']=='SessionStart' and '세션1' in c" 2>/dev/null \
  && ok "진행상황 additionalContext 주입" || bad "session_context (out=$out)"
# 위키 자동 노출(결정적): wiki/index.md 가 additionalContext 에 주입돼야 한다.
#   라이브(-p)는 SessionStart 도달이 불안정해 best-effort WARN — 강제 단언은 여기 훅-출력 레벨에서.
printf '%s' "$out" | python3 -c "import sys,json;c=json.load(sys.stdin)['hookSpecificOutput']['additionalContext'];assert 'WIKI_IDX_MARK' in c" 2>/dev/null \
  && ok "위키 인덱스 additionalContext 주입" || bad "session_context wiki (out=$out)"
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

echo "== next_feature.py =="
tn="$(mktemp -d)"
printf '[{"description":"A","passes":true},{"description":"B기능","passes":false}]' > "$tn/feature_list.json"
out="$(CLAUDE_PROJECT_DIR="$tn" python3 "$ROOT/scripts/next_feature.py")"
{ printf '%s' "$out" | grep -q '1/2' && printf '%s' "$out" | grep -q 'B기능'; } \
  && ok "진행 1/2·다음 B기능 보고" || bad "next_feature (out=$out)"
rm -rf "$tn"

echo "== scaffold 보존/force =="
tp="$(mktemp -d)"
printf 'MINE\n' > "$tp/AGENTS.md"
CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/scripts/scaffold.sh" "$tp" >/dev/null
grep -q '^MINE' "$tp/AGENTS.md" && ok "기존 파일 보존(덮어쓰지 않음)" || bad "scaffold preserve"
CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/scripts/scaffold.sh" "$tp" --force >/dev/null
grep -q '에이전트 헌법' "$tp/AGENTS.md" && ok "--force 덮어쓰기" || bad "scaffold force"
rm -rf "$tp"

echo "== wiki_lint 양성탐지 =="
tw="$(mktemp -d)"; mkdir -p "$tw/wiki/concepts"
printf '# 위키 인덱스\n' > "$tw/wiki/index.md"
printf 'frontmatter 없는 본문\n' > "$tw/wiki/concepts/bad.md"   # missing_frontmatter + orphan
out="$(CLAUDE_PROJECT_DIR="$tw" python3 "$ROOT/scripts/wiki_lint.py")"; rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'missing_frontmatter' && printf '%s' "$out" | grep -q 'orphan'; } \
  && ok "drift(미frontmatter·고아) 탐지·exit1" || bad "wiki_lint detect (rc=$rc out=$out)"
rm -rf "$tw"

echo "== fid 계약(record↔gate↔nudge, 유니코드) =="
tf="$(mktemp -d)"
DESC='한글 기능 €'
printf '[{"description":"%s","passes":true}]' "$DESC" > "$tf/feature_list.json"
CLAUDE_PROJECT_DIR="$tf" python3 "$ROOT/scripts/verify_gate.py" --record "$DESC" PASS "ok" >/dev/null
g="$(printf '{}' | CLAUDE_PROJECT_DIR="$tf" python3 "$ROOT/scripts/verify_gate.py")"
n="$(printf '{}' | CLAUDE_PROJECT_DIR="$tf" python3 "$ROOT/scripts/skill_nudge.py")"
{ [ -z "$g" ] && printf '%s' "$n" | grep -q 'skillify'; } \
  && ok "유니코드 desc 계약 일치(기록→게이트 허용→유도)" || bad "fid contract (g=$g n=$n)"
rm -rf "$tf"

echo "== 두 Stop 훅 동시 동작 =="
ts="$(mktemp -d)"
printf '[{"description":"z","passes":true}]' > "$ts/feature_list.json"   # 검증전: done 주장
sg="$(printf '{}' | CLAUDE_PROJECT_DIR="$ts" python3 "$ROOT/scripts/stop_guard.py")"
vg="$(printf '{}' | CLAUDE_PROJECT_DIR="$ts" python3 "$ROOT/scripts/verify_gate.py")"
{ [ -z "$sg" ] && is_block "$vg"; } && ok "검증전: stop_guard 통과·verify_gate 차단" || bad "two-stop A (sg=$sg vg=$vg)"
CLAUDE_PROJECT_DIR="$ts" python3 "$ROOT/scripts/verify_gate.py" --record "z" PASS "ok" >/dev/null
sg2="$(printf '{}' | CLAUDE_PROJECT_DIR="$ts" python3 "$ROOT/scripts/stop_guard.py")"
vg2="$(printf '{}' | CLAUDE_PROJECT_DIR="$ts" python3 "$ROOT/scripts/verify_gate.py")"
{ [ -z "$sg2" ] && [ -z "$vg2" ]; } && ok "검증후: 두 훅 모두 종료 허용" || bad "two-stop B (sg2=$sg2 vg2=$vg2)"
rm -rf "$ts"

# --- JSON 유효성 ---
echo "== JSON 유효성 =="
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  python3 -c "import json;json.load(open('$ROOT/$f'))" 2>/dev/null && ok "json $f" || bad "json $f"
done

echo "----"
echo "통과 $pass / 실패 $([ $fail -eq 0 ] && echo 0 || echo '있음')"
exit $fail
