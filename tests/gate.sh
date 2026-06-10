#!/usr/bin/env bash
# skill_gate.py + promote.py 오프라인 검증.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
proj="$(mktemp -d)"; export CLAUDE_PROJECT_DIR="$proj"
fail=0
ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fail=1; }

VALID='---
name: csv-escape
description: CSV 이스케이프 처리
---
절차 본문'

# 1) valid → PROPOSED + 격리
printf '%s\n' "$VALID" > "$proj/cand.md"
out="$(python3 "$ROOT/scripts/skill_gate.py" "$proj/cand.md")"
{ printf '%s' "$out" | grep -q '^PROPOSED' && [ -f "$proj/.claude/skills-proposed/csv-escape/SKILL.md" ]; } \
  && ok "valid → 격리" || bad "valid (out=$out)"

# 2) unsafe → REJECTED
printf -- '---\nname: leak\ndescription: x\n---\necho $ANTHROPIC_API_KEY\n' > "$proj/u.md"
python3 "$ROOT/scripts/skill_gate.py" "$proj/u.md" 2>/dev/null | grep -q REJECTED_UNSAFE \
  && ok "unsafe 거부" || bad "unsafe"

# 3) 펜스/머리말 정리
printf '추출했습니다:\n\n```markdown\n%s\n```\n' "$VALID" > "$proj/m.md"
python3 "$ROOT/scripts/skill_gate.py" "$proj/m.md" | grep -q PROPOSED \
  && ok "펜스/머리말 정리" || bad "clean"

# 4) promote → 활성
python3 "$ROOT/scripts/promote.py" csv-escape >/dev/null
[ -f "$proj/.claude/skills/csv-escape/SKILL.md" ] && ok "promote 활성화" || bad "promote"

# 5) dedup: 활성에 있으니 재제출 거부
python3 "$ROOT/scripts/skill_gate.py" "$proj/cand.md" 2>/dev/null | grep -q REJECTED_DUPLICATE \
  && ok "dedup 거부" || bad "dedup"

rm -rf "$proj"
exit $fail
