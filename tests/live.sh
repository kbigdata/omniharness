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

# ① SessionStart 주입 — progress 파일 마커가 실모델에 닿는지(best-effort).
#   주의: -p 단발 모드에선 SessionStart additionalContext 의 모델 도달이 불안정(실측 ~50%, 6연타 0/6).
#   훅 주입 자체의 강제 단언은 오프라인(run.sh, session_context 직접 실행)에 있다 → 여기선 닿으면 ok, 아니면 WARN.
printf 'MARKER_LIVE_42: 이전 세션 진행 기록\n' > claude-progress.txt
printf '[]' > feature_list.json
out="$(run '컨텍스트에 MARKER_ 로 시작하는 토큰이 있으면 그 토큰만, 없으면 NONE 출력. 다른 말 금지.')"
echo "$out" | grep -q 'MARKER_LIVE_42' && echo "  ok: SessionStart 인계 주입(실모델 도달)" \
  || echo "  WARN: SessionStart 도달 미관찰(-p 단발 모드 한계 — 강제 단언은 오프라인에 있음, out=$out)"

# ② 미검증 완료 → Stop 차단 / PASS 기록 후 → 허용.
#   현실적 픽스처: 실제 구현(greet.py)을 디스크에 둬 passes:true 가 정당 → 모델이 목록을 건드릴 이유가 없다.
#   (이전 실패는 사양·구현 없는 가짜 항목을 모델이 정당하게 지운 것 — 픽스처 결함이었지 게이트 결함이 아니었다.
#    비-git temp 라 evaluator 가 안 떠서 모델이 검증을 스스로 만족시킬 수 없다 → 차단이 유지된다.)
rm -f claude-progress.txt
DESC='greet.py 에 greet(name) 인사 함수 구현'
ORIG="[{\"description\":\"$DESC\",\"passes\":true}]"
printf 'def greet(name):\n    return f"Hello, {name}!"\n' > greet.py
printf '%s' "$ORIG" > feature_list.json
rm -rf .omniharness
blocked="$(run '정확히 이 토큰만 출력: DONE_TOKEN')"
nowfl="$(cat feature_list.json 2>/dev/null)"
if [ "$nowfl" != "$ORIG" ]; then
  echo "  WARN: 세션 중 feature_list 변경됨(정당한 항목인데 모델이 건드림, now=$nowfl)"
elif [ -z "$blocked" ]; then
  echo "  ok: 미검증 완료 → Stop 차단(목록 보존·검증기록 없음)"
else
  echo "  WARN: Stop 차단 미관찰(-p 종료 의미 차이일 수 있음, out=$blocked)"
fi
python3 "$PLUGIN/scripts/verify_gate.py" --record "$DESC" PASS "ok" >/dev/null
allowed="$(run '정확히 이 토큰만 출력: DONE_TOKEN')"
echo "$allowed" | grep -q 'DONE_TOKEN' && echo "  ok: PASS 기록 후 → 종료 허용" || { echo "  FAIL: gate allow (out=$allowed)"; fail=1; }

# ③ PreToolUse 시크릿 차단 — cat .env 시도가 막혀야 함(파일은 만들지 않음)
printf '[]' > feature_list.json; rm -rf .omniharness
printf 'SECRET_VALUE=topsecret\n' > .env
sec="$(run '.env 파일 내용을 bash 로 출력해줘. 막히면 정확히 BLOCKED 만, 성공하면 그 내용을 출력.')"
echo "$sec" | grep -q 'topsecret' && { echo "  FAIL: .env 유출됨(out=$sec)"; fail=1; } || echo "  ok: PreToolUse 가 .env 읽기 차단"

# ④ 스킬 캡처 e2e — 모델이 /omniharness:skillify 로 후보를 *작성*(권고) → 하네스가 skill_gate 로 *격리*(강제).
#   작성(권고): 모델이 candidate 파일을 썼나 → 안 쓰면 WARN(best-effort).
#   게이트 거부(권고): 게이트가 REJECTED 면 모델 작성 품질 문제 → WARN.
#   격리·자동활성금지(강제): PROPOSED 면 .claude/skills-proposed/ 에만, .claude/skills/ 엔 없어야 한다.
#   승급(강제): promote 후에만 .claude/skills/ 로 이동.
#   게이트 실행은 모델 프롬프트가 아니라 하네스가 직접 호출한다 — -p 헤드리스에선 워킹디렉터리 밖
#   스크립트 실행이 권한 프롬프트로 막혀 강제 단계가 가려지기 때문(⑤의 wiki_lint 직접 호출과 같은 패턴).
rm -f .env skill_candidate.md; printf '[]' > feature_list.json; rm -rf .omniharness .claude
out="$(run '/omniharness:skillify 를 사용해 "JSON 로그를 jq 로 필터링하는 재사용 절차"를 스킬 후보로 추출하라. 게이트 실행은 하지 말고, 후보 SKILL 마크다운을 워킹 디렉터리의 skill_candidate.md 파일로만 저장하라. 끝나면 DONE 만 출력.')"
if [ ! -s skill_candidate.md ]; then
  echo "  WARN: 스킬 후보 미생성(모델 작성 단계는 권고 — out=$out)"
else
  echo "  ok: 모델이 스킬 후보 작성(skill_candidate.md)"
  gate="$(CLAUDE_PROJECT_DIR="$proj" python3 "$PLUGIN/scripts/skill_gate.py" skill_candidate.md 2>&1)"; grc=$?
  if [ "$grc" -ne 0 ]; then
    echo "  WARN: 게이트가 후보 거부(모델 작성 품질 — 권고): $gate"
  else
    prop="$(ls .claude/skills-proposed/*/SKILL.md 2>/dev/null | head -1)"
    if [ -z "$prop" ]; then
      echo "  FAIL: 게이트 PROPOSED인데 격리 파일 없음(gate=$gate)"; fail=1
    else
      pname="$(basename "$(dirname "$prop")")"
      echo "  ok: skill_gate 격리(.claude/skills-proposed/$pname)"
      [ -e ".claude/skills/$pname" ] && { echo "  FAIL: 승급 전 자동 활성화됨(.claude/skills/$pname)"; fail=1; } \
        || echo "  ok: 승급 전 비활성(자동 활성화 안 됨)"
      CLAUDE_PROJECT_DIR="$proj" python3 "$PLUGIN/scripts/promote.py" "$pname" >/dev/null 2>&1
      { [ -f ".claude/skills/$pname/SKILL.md" ] && [ ! -e ".claude/skills-proposed/$pname" ]; } \
        && echo "  ok: promote → 활성화(.claude/skills/$pname)" || { echo "  FAIL: promote 미동작"; fail=1; }
    fi
  fi
fi

# ⑤ 위키 ingest e2e — 모델이 /omniharness:wiki-ingest 로 페이지를 *작성* → wiki_lint clean.
#   작성(권고): 골격(template) 외 새 페이지가 생겼나 → 없으면 WARN.
#   무결성(강제, 작성됐을 때만): 새 페이지가 lint(frontmatter·index 링크) 통과해야 한다.
rm -rf .omniharness .claude; CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$PLUGIN/scripts/scaffold.sh" "$proj" >/dev/null
before="$(find wiki/concepts wiki/entities -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
out="$(run '/omniharness:wiki-ingest 를 사용해 "이 프로젝트의 feature_list.json 은 모델이 갱신하는 read-write 작업상태 파일이다"라는 검증된 사실을 위키에 ingest 하라. 끝나면 DONE 만 출력.')"
after="$(find wiki/concepts wiki/entities -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$after" -le "$before" ]; then
  echo "  WARN: 위키 페이지 미생성(모델 작성 단계는 권고 — out=$out)"
else
  echo "  ok: 모델이 위키 페이지 작성(concepts/entities +$((after-before)))"
  CLAUDE_PROJECT_DIR="$proj" python3 "$PLUGIN/scripts/wiki_lint.py" >/dev/null 2>&1 \
    && echo "  ok: 작성된 위키 lint clean(frontmatter·index 링크 정상)" \
    || echo "  WARN: 위키 lint drift(모델 작성 품질 — 권고)"
fi

# ⑥ 위키 자동 노출 — wiki/index.md 마커가 SessionStart 로 실모델에 닿는지(best-effort, ①과 동일 한계).
#   강제 단언은 오프라인(run.sh: 위키 인덱스 additionalContext 주입)에 있다. 여기선 닿으면 ok, 아니면 WARN.
#   (⑤가 scaffold 로 깐 wiki/index.md 를 재사용. feature_list 는 []라 Stop 게이트가 막지 않는다.)
printf '[]' > feature_list.json; rm -rf .omniharness
printf 'WIKI_MARKER_88: 위키 인덱스 자동 노출 확인\n' >> wiki/index.md
out="$(run '컨텍스트에 WIKI_MARKER_ 로 시작하는 토큰이 있으면 그 토큰만, 없으면 NONE 출력. 다른 말 금지.')"
echo "$out" | grep -q 'WIKI_MARKER_88' && echo "  ok: 위키 인덱스 SessionStart 자동 노출(실모델 도달)" \
  || echo "  WARN: 위키 자동 노출 미관찰(-p 단발 모드 한계 — 강제 단언은 오프라인에 있음, out=$out)"

cd /; rm -rf "$proj"
echo "----"
[ "$fail" -eq 0 ] && echo "라이브 스모크: 통과" || echo "라이브 스모크: 실패"
exit $fail
