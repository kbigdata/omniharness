---
name: wiki-ingest
description: 검증된 선언적 학습(사실·제약·교정)을 프로젝트 wiki/에 ingest한다. 실행 절차가 아닌 재사용 지식을 위키 페이지로 남길 때 사용.
---

# wiki-ingest

검증된 **선언적 지식**을 `wiki/`에 반영한다(실행 가능 절차면 대신 `/omniharness:skillify`로 스킬화).

## 절차
1. 한 문장 요약 + 소속 페이지 결정(`wiki/concepts/` 또는 `wiki/entities/`).
2. 페이지 작성/갱신 — frontmatter 필수: `title/created/updated/source/produced_by/confidence/status`.
3. `wiki/index.md` 표에 행 추가/갱신(링크·1줄요약·갱신일·출처수).
4. 교차링크 + `wiki/log.md`에 `## [YYYY-MM-DD] ingest | <제목>` append.
5. 한 줄 교정이면 `AGENTS.md` §10 Learnings에 `- [날짜] <교정>`.

## 금지
- `sources/`는 읽기 전용. 추측 ingest 금지(검증된 것만).
- 마치면 `/omniharness:wiki-lint`로 drift를 점검한다.
