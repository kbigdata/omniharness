#!/usr/bin/env bash
# init.sh — 개발 환경 기동 + 스모크 테스트 (GAP §9.1). 세션 시작 시 에이전트가 읽고 실행한다.
# 이 템플릿은 플레이스홀더다. 프로젝트에 맞게 채워라.
set -euo pipefail

echo "[init] 의존성 설치 / 개발 서버 기동 절차를 여기에..."
# 예: uv pip install -e ".[dev]"
# 예: npm install && npm run dev &

echo "[smoke] 기본 동작 스모크 테스트를 여기에..."
# 예: uv run pytest -q  ||  echo "스모크 실패 — 새 기능 전에 수리 필요"
