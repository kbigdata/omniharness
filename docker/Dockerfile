# omniharness autoloop — 무인 자율 루프용 격리 실행 환경.
# bypassPermissions 는 이 컨테이너처럼 실제 격리된 환경에서만 쓴다(README 주의사항).
FROM node:22-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# 컨테이너 = 진짜 샌드박스. root 실행 가드 해제와 claude 경로 고정.
ENV IS_SANDBOX=1 \
    CLAUDE_BIN=/usr/local/bin/claude

RUN git config --global user.email "autoloop@container" \
    && git config --global user.name "autoloop" \
    && git config --global init.defaultBranch main

WORKDIR /work
