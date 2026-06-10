---
name: wiki-lint
description: 위키의 drift(오래된·깨진 지식, 고아 페이지)를 결정론적으로 점검한다.
---

# wiki-lint

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/wiki_lint.py"
```

frontmatter 누락·잘못된 status·index에 없는 고아 페이지를 보고한다(GAP §4.3: 오래된 지식이 가장 위험).
보고된 항목을 `/omniharness:wiki-ingest` 절차로 갱신하거나 `status: stale|deprecated`로 표시한다.
