#!/usr/bin/env bash
# 야간 무인 러너 — 컨테이너 격리 autoloop 을 스케줄(launchd/cron)에서 실행한다.
# 설계·운영 교훈: docs/자동루프-설계.md (컨테이너 무인 운영 절)
#
# 설정(환경변수, 모두 기본값 있음):
#   OMNI_TARGET   대상 프로젝트(호스트 경로, $HOME 아래여야 colima 마운트 가능)
#   OMNI_LOG_DIR  로그 디렉터리
#   OMNI_PLUGIN   omniharness 플러그인 경로
#   OMNI_PROFILE  colima 프로필(네이티브 arch 필수 — x86_64 에뮬레이션은 claude SIGILL)
# 대상 프로젝트에 regress.cmd 파일이 있으면 그 내용을 회귀 명령으로 사용한다.
set -u
# launchd 는 최소 PATH 로 실행 — 명시 고정(무인 환경 PATH 비결정성 교훈)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

PLUGIN="${OMNI_PLUGIN:-$(cd "$(dirname "$0")/.." && pwd)}"
TARGET="${OMNI_TARGET:-$HOME/omniharness-nightly/workspace}"
LOG_DIR="${OMNI_LOG_DIR:-$HOME/omniharness-nightly/logs}"
PROFILE="${OMNI_PROFILE:-omniharness}"
CTX="colima-$PROFILE"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y-%m-%d_%H%M).log"
exec >>"$LOG" 2>&1
echo "==== nightly $(date '+%F %T') target=$TARGET ===="

[ -f "$TARGET/feature_list.json" ] || { echo "SKIP: $TARGET/feature_list.json 없음"; exit 0; }
case "$TARGET" in "$HOME"/*) ;; *) echo "FATAL: 대상이 \$HOME 밖 — colima 마운트 불가"; exit 3;; esac

# 1) 콜리마/도커 기동 확인 (야간엔 내려가 있을 수 있음)
colima status --profile "$PROFILE" >/dev/null 2>&1 || colima start --profile "$PROFILE" --arch aarch64 --cpu 2 --memory 4
docker --context "$CTX" info >/dev/null 2>&1 || { echo "FATAL: docker($CTX) 미가동"; exit 3; }
docker --context "$CTX" image inspect omniharness-autoloop >/dev/null 2>&1 \
  || docker --context "$CTX" build -t omniharness-autoloop "$PLUGIN/docker"

# 2) 자격증명: Keychain → 0600 임시파일(홈 아래 — colima 는 홈만 마운트) → 종료 시 삭제
CRED_DIR="$HOME/.omniharness-nightly-creds.$$"
cleanup() { rm -rf "$CRED_DIR"; }
trap cleanup EXIT
mkdir -p "$CRED_DIR" && chmod 700 "$CRED_DIR"
security find-generic-password -s "Claude Code-credentials" -w > "$CRED_DIR/.credentials.json" 2>/dev/null
[ -s "$CRED_DIR/.credentials.json" ] || { echo "FATAL: Keychain 자격증명 추출 실패(잠금/로그아웃?)"; exit 3; }
chmod 600 "$CRED_DIR/.credentials.json"

# 3) 회귀 명령(프로젝트별): regress.cmd 파일이 있으면 사용
REGRESS="true"
[ -f "$TARGET/regress.cmd" ] && REGRESS="$(cat "$TARGET/regress.cmd")"
echo "regress: $REGRESS"

# 4) 격리 무인 실행 — 워크스페이스는 rw(결과 보존), 플러그인·자격증명은 ro
docker --context "$CTX" run --rm \
  -v "$PLUGIN":/plugin:ro \
  -v "$CRED_DIR":/creds:ro \
  -v "$TARGET":/work/proj \
  -e OMNI_REGRESS="$REGRESS" \
  omniharness-autoloop bash -c '
set -u
mkdir -p /root/.claude && cp /creds/.credentials.json /root/.claude/ && chmod 600 /root/.claude/.credentials.json
git config --global --add safe.directory /work/proj
cd /work/proj
python3 /plugin/scripts/autoloop.py --project /work/proj --plugin-dir /plugin \
  --regress "$OMNI_REGRESS" --retries 1 --max-turns 30 --timeout 600'
rc=$?
echo "==== 종료 rc=$rc $(date '+%F %T') ===="
exit $rc
