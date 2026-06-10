#!/usr/bin/env bash
# templates/ → 프로젝트 스캐폴드. 기존 파일은 보존(덮어쓰지 않음). $2=--force 면 덮어쓰기.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${CLAUDE_PLUGIN_ROOT:-$HERE}/templates"
DEST="${1:-${CLAUDE_PROJECT_DIR:-.}}"
FORCE="${2:-}"
[ -d "$SRC" ] || { echo "templates 없음: $SRC"; exit 1; }
copied=0; skipped=0
while IFS= read -r -d '' f; do
  rel="${f#"$SRC"/}"
  target="$DEST/$rel"
  if [ -e "$target" ] && [ "$FORCE" != "--force" ]; then
    skipped=$((skipped+1))
  else
    mkdir -p "$(dirname "$target")"
    cp "$f" "$target"
    copied=$((copied+1))
  fi
done < <(find "$SRC" -type f -print0)
echo "스캐폴드: $copied 복사, $skipped 보존 → $DEST"
echo "  AGENTS.md(헌법) · .claude/settings.json(권한) · wiki/ · feature_list.json · init.sh"
