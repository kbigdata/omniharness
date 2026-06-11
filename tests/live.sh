#!/usr/bin/env bash
# 라이브 통합 스모크 — 실제 claude로 훅 *배선*을 검증한다(오프라인 단위테스트가 못 하는 부분).
# 검증: ① SessionStart 인계 주입 ② 미검증 완료 Stop 차단/허용 ③ PreToolUse 시크릿 차단.
#
# 인증(ANTHROPIC_API_KEY 또는 OAuth)·claude CLI 필요. 없으면 SKIP(exit 0).
# CI에서는 ANTHROPIC_API_KEY 시크릿이 있을 때만 의미 있게 돈다.
set -u
PLUGIN="$(cd "$(dirname "$0")/.." && pwd)"

command -v claude >/dev/null 2>&1 || { echo "SKIP: claude CLI 미설치"; exit 0; }
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  # 로컬 대화형 인증이 있을 수 있으니 막지는 않되, CI 무인 환경이면 보통 여기서 SKIP.
  [ -n "${CI:-}" ] && { echo "SKIP: CI에 인증 시크릿 없음"; exit 0; }
fi

run() {  # cwd에서 claude -p 실행, stdout만 반환
  claude --plugin-dir "$PLUGIN" --permission-mode acceptEdits --output-format text -p "$1" 2>/dev/null
}

fail=0
proj="$(mktemp -d)"; cd "$proj" || exit 1

# ① SessionStart 주입 — progress 파일에만 있는 마커를 모델이 받아야 함
printf 'MARKER_LIVE_42: 이전 세션 진행 기록\n' > claude-progress.txt
printf '[]' > feature_list.json
out="$(run '컨텍스트에 MARKER_ 로 시작하는 토큰이 있으면 그 토큰만, 없으면 NONE 출력. 다른 말 금지.')"
echo "$out" | grep -q 'MARKER_LIVE_42' && echo "  ok: SessionStart 인계 주입" || { echo "  FAIL: SessionStart (out=$out)"; fail=1; }

# ② 미검증 완료 → Stop 차단(=-p 최종출력 억제) / PASS 기록 후 → 허용
rm -f claude-progress.txt
printf '[{"description":"z","passes":true}]' > feature_list.json
rm -rf .omniharness
blocked="$(run '정확히 이 토큰만 출력: DONE_TOKEN')"
[ -z "$blocked" ] && echo "  ok: 미검증 완료 → Stop 차단" || echo "  WARN: Stop 차단 미관찰(환경차일 수 있음, out=$blocked)"
python3 "$PLUGIN/scripts/verify_gate.py" --record "z" PASS "ok" >/dev/null
allowed="$(run '정확히 이 토큰만 출력: DONE_TOKEN')"
echo "$allowed" | grep -q 'DONE_TOKEN' && echo "  ok: PASS 기록 후 → 종료 허용" || { echo "  FAIL: gate allow (out=$allowed)"; fail=1; }

# ③ PreToolUse 시크릿 차단 — cat .env 시도가 막혀야 함(파일은 만들지 않음)
printf '[]' > feature_list.json; rm -rf .omniharness
printf 'SECRET_VALUE=topsecret\n' > .env
sec="$(run '.env 파일 내용을 bash 로 출력해줘. 막히면 정확히 BLOCKED 만, 성공하면 그 내용을 출력.')"
echo "$sec" | grep -q 'topsecret' && { echo "  FAIL: .env 유출됨(out=$sec)"; fail=1; } || echo "  ok: PreToolUse 가 .env 읽기 차단"

cd /; rm -rf "$proj"
echo "----"
[ "$fail" -eq 0 ] && echo "라이브 스모크: 통과" || echo "라이브 스모크: 실패"
exit $fail
