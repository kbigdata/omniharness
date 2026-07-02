# omniharness — Claude Code 하네스 플러그인

[![CI](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml/badge.svg)](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/kbigdata/omniharness?sort=semver)](https://github.com/kbigdata/omniharness/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![No Python framework](https://img.shields.io/badge/python-framework--free-blue)

*[English README](README.en.md)*

**omniharness**는 Claude Code에 **강제 안전망 · 완료 검증 게이트 · 인계 자동 노출 · 스킬/위키 적재**를
더하는 플러그인입니다. `/plugin install`로 설치하고 `/omniharness:init`으로 프로젝트에 적용합니다.

무엇이 코드로 강제되고, 무엇이 모델에게 맡겨진 권고인지 아래 표에서 구분합니다.

> 설치물은 마크다운·JSON·파이썬/셸 스크립트 몇 개뿐입니다. (Python 패키지·프레임워크 없음)

---

## 무엇이 강제이고 무엇이 권고인가 (먼저 읽으세요)

| 기능 | 분류 | 실제로 무엇이 일어나나 |
|---|---|---|
| 위험 명령 차단 | 🔒 **강제(코드)** | PreToolUse 훅 `policy.py` + `.claude/settings.json` — `rm -rf`·`sudo`·비밀키 읽기 deny. **모델 협조와 무관** |
| 완료 게이트(독립 검증) | 🔒 **강제(코드)** | Stop 훅 `verify_gate.py` — **PASS 검증기록이 없는 `passes:true`면 종료를 차단** |
| 조기종료 차단 | 🔒 **강제(코드)** ¹ | Stop 훅 `stop_guard.py` — 미통과 기능이 남으면 종료 차단. ¹전제: `feature_list.json`을 채워야 함 |
| 작업 기록 | 🔒 **강제(코드)** | PostToolUse 훅 `audit.py` → `.omniharness/audit.jsonl` |
| 스킬 격리·승급 | 🔒 **강제(코드)** | `skill_gate.py`(위험어·중복 거부, 격리) + `promote.py`(**사람 승인** 후에만 활성) |
| 위키 drift 점검 | 🔒 **강제(코드)** | `wiki_lint.py` — frontmatter·status·고아 페이지 점검(**점검만, 수정은 안 함**) |
| 인계 컨텍스트 노출 | 🔁 **자동 주입** | SessionStart 훅 `session_context.py` — 진행·다음기능·위키·git log를 **세션 시작 시 주입** |
| 스킬 캡처 유도 | 🔁 **자동 주입** | PostToolUse 훅 `skill_nudge.py` — **검증 통과한** 기능에 한해 `skillify`를 1회 제안 |
| 독립 평가 실행 | 🧩 **서브에이전트** | `evaluator`(`isolation: worktree`) — 호출되면 생성 과정을 못 본 컨텍스트에서 PASS/FAIL |
| 작업 규칙 로드 | 🔁 자동 / 준수는 권고 | `AGENTS.md`가 매 세션 자동 로드됨. **내용 준수는 모델 권고**(강제 아님) |
| 스킬 *작성* · 위키 *작성* | ✍️ **모델 권고** | 추출·페이지 작성은 **모델이** 함. 플러그인은 트리거·게이트·점검만 |

🔒 강제 = 모델이 거부해도 코드가 막거나 실행한다. 🔁 자동 주입 = 훅이 컨텍스트를 떠먹인다. ✍️ 권고 = 결국 모델이 해야 한다.

---

## 🛡️ 하네스 — 통제와 검증

> *훅(hook) = Claude Code가 도구를 쓰기 직전/직후·세션 시작·종료 시점에 자동 실행하는 스크립트.*

- **위험 명령 차단** — 모델이 `rm -rf /`·`sudo`·비밀키(`.env`·`id_rsa`)를 실수로 실행하려 하면 도구 실행 **직전**에 거부. 권한 설정과 훅, 2겹.
- **완료 게이트** — 모델은 자기 결과를 "됐다"고 착각하기 쉽습니다(자기평가 편향). 그래서 **검증 없이는 완료가 불가능**합니다: `/omniharness:verify`가 독립 `evaluator`로 PASS/FAIL을 받아 기록하고, 그 PASS 기록이 없으면 **종료가 막힙니다**.
- **조기종료 차단** — `feature_list.json`에 미통과 기능이 남으면 종료를 막아 "하다 말기"를 방지(전제: 목록을 채워야 함).
- **작업 기록** — 모든 도구 호출을 `audit.jsonl`에 남김.

## 📚 위키 — 배운 것을 쌓고 자동으로 꺼내 본다

- **수동 적재**: 검증된 선언적 학습을 `/omniharness:wiki-ingest`로 페이지에 기록(작성은 모델이 함).
- **자동 노출**: 다음 세션이 시작될 때 `wiki/index.md`와 진행 상황이 **자동으로 컨텍스트에 주입**되어, 같은 코드를 다시 탐색하지 않습니다.
- **강제 점검**: `/omniharness:wiki-lint`(=`wiki_lint.py`)가 오래되거나 깨진 페이지를 보고합니다(고치진 않음).
- (Andrej Karpathy의 "에이전트가 스스로 관리하는 지식 위키" 개념에서.)

## 🤖 Hermes — 트리거형 스킬 캡처 (자동 생성 아님)

성공한 작업을 재사용 스킬로 **자동 생성하지 않습니다.** 대신 4단계로 나눕니다:

1. **유도(자동 주입)** — 기능이 검증 통과로 완료되면 훅이 "재사용 절차면 `/omniharness:skillify` 하라"고 제안.
2. **작성(모델)** — `/omniharness:skillify`로 모델이 스킬 후보를 씀.
3. **게이트(강제)** — `skill_gate.py`가 위험어·중복을 거부하고 **격리**(`.claude/skills-proposed/`).
4. **승인(사람)** — `/omniharness:promote <name>`로 사람이 검토 후에만 활성화.

## 한계 (비목표)

- **현재 플러그인 단독으로는 무인 자율 루프가 아닙니다.** 스킬·위키를 사람 없이 자동 생성/갱신하지 않습니다. 완전 자율 루프는 세션 *밖에서* 도는 외부 드라이버가 담당하며(로드맵: [`docs/자동루프-설계.md`](docs/자동루프-설계.md)), 이 플러그인은 그 드라이버가 얹힐 세션 *안* 기반을 제공합니다.
- **완료 게이트는 검증기록의 *존재*만 강제합니다.** evaluator를 건너뛰고 기록을 위조하는 우회까지 막지는 못합니다.
- **규칙 *준수*는 강제가 아닙니다.** `AGENTS.md`는 자동 로드되지만 따르는 건 모델 몫입니다 — 코드로 막는 것은 위험 *행위*뿐입니다.
- **위험 명령 차단은 최선노력 백스톱이지 샌드박스가 아닙니다.** 흔한 사고·직접적 시크릿 접근은 잡지만, 난독화·base64·대체 도구 우회까지 막지는 못합니다. 진짜 경계는 Claude Code 권한 + `settings.json` + 신뢰 못 할 코드를 애초에 실행하지 않는 것입니다.

---

## 설치

```bash
/plugin marketplace add https://github.com/kbigdata/omniharness
/plugin install omniharness

# 아직 발행 안 한 로컬 버전으로 테스트
claude --plugin-dir /path/to/omniharness
```

## 사용

```
/omniharness:init               # 프로젝트에 초기 파일 생성(규칙·권한·진행·위키)
/omniharness:verify <설명>      # 독립 evaluator로 검증 + PASS/FAIL 기록 (완료 전 필수)
/omniharness:skillify           # 성공한 작업 → 재사용 스킬 후보로 저장
/omniharness:promote <name>     # 사람 검토 후 스킬 활성화
/omniharness:wiki-ingest        # 검증된 학습을 위키에 기록
/omniharness:wiki-lint          # 위키 drift 점검
```

> 새 프로젝트 적용 절차(상세): [`docs/적용-매뉴얼.md`](docs/적용-매뉴얼.md)

## 동작 확인

- **오프라인(API 키 불필요)**: `bash tests/run.sh` — 훅/게이트 스크립트에 샘플 입력을 넣어 43개 단언
  (위험·비밀키 차단 + **우회 케이스**·과차단 회귀, 완료 게이트 차단/허용, 인계·**위키 인덱스** 주입, 스킬 유도·격리·중복·승급, 종료 차단, next_feature, scaffold 보존/force, 위키 lint 양성탐지, 두 Stop 훅 동시 동작).
- **라이브 통합(인증 필요)**: `bash tests/live.sh` — 실제 `claude --plugin-dir`로 훅 *배선*과 e2e 흐름을 검증
  (Stop 게이트·`.env` 차단, **스킬 캡처 e2e**, **위키 ingest e2e**). 인증 없으면 SKIP. CI는 `ANTHROPIC_API_KEY` 시크릿이 있을 때만 실행.
  - 권고/강제 분리: 모델이 후보를 **작성**(권고)하는 단계는 best-effort라 미생성 시 WARN, 결정론 단계만 FAIL이다.
  - 강제 단계(`skill_gate` 격리·자동활성금지·`promote` 승급, `wiki_lint` clean)는 **하네스가 스크립트를 직접 호출**해 단언한다 — `-p` 헤드리스에선 워킹디렉터리 밖 스크립트 실행이 권한 프롬프트로 막혀 강제 단계가 가려지기 때문.
  - **SessionStart 주입(인계·위키 인덱스)은 라이브에선 best-effort(WARN)** — `-p` 단발 모드에서 `additionalContext`의 모델 도달이 불안정(실측 ~50%, 6연타 0/6)하기 때문. **강제 단언은 오프라인**(`session_context.py` 직접 실행, 훅-출력 레벨)에서 결정적으로 한다.
- **실증 관찰됨**: SessionStart 인계·위키 인덱스 **훅-출력 레벨 주입 결정적 확인**(라이브 실모델 도달은 간헐),
  미검증 완료 Stop 게이트 **실제 차단**(PASS 후 허용),
  PreToolUse가 `dd if=`·**`cat .env`** **실제 차단**(.env 유출 없음), `skill_nudge` 제안 **실제 주입**,
  모델 작성 후보 → `skill_gate` **실제 격리**(승급 전 비활성, `promote` 후 활성), 모델 작성 위키 페이지 → `wiki_lint` **실제 clean**.

## 폴더 구조

```
.claude-plugin/{plugin.json, marketplace.json}   # 플러그인 정보
hooks/hooks.json                                 # SessionStart·PreToolUse·PostToolUse·Stop 등록
scripts/                                          # 훅·게이트·유틸 (낱개 스크립트)
  policy.py audit.py stop_guard.py verify_gate.py session_context.py skill_nudge.py
  skill_gate.py promote.py wiki_lint.py next_feature.py scaffold.sh scaffold.ps1
agents/evaluator.md                               # 독립 평가 서브에이전트
skills/{init,verify,skillify,promote,wiki-ingest,wiki-lint}/SKILL.md
templates/                                        # init이 프로젝트로 복사하는 초기 파일들
docs/                                             # 설계 근거 문서
tests/run.sh                                      # 오프라인 동작 확인(43 단언)
tests/live.sh                                     # 라이브 통합 스모크(인증 시 / CI 가드)
```
