#!/usr/bin/env bash
# 얇은 런처 — Linux/WSL/macOS. 로직은 전부 autoloop.py 단일 코어에 있다(이중화 금지).
exec python3 "$(dirname "$0")/autoloop.py" "$@"
