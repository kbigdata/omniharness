# omniharness — Claude Code 하네스 플러그인

[![CI](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml/badge.svg)](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/kbigdata/omniharness?sort=semver)](https://github.com/kbigdata/omniharness/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![No Python framework](https://img.shields.io/badge/python-framework--free-blue)

*[English README](README.en.md)*

**omniharness**는 Claude Code를 **스스로 통제하고, 배운 것을 쌓고, 잘한 일을 자동화하는**
작업 환경으로 바꾸는 플러그인입니다. `/omniharness:init` 한 번이면 어떤 프로젝트든 아래 세 축을 갖춥니다.

| | 축 | 한 줄 설명 |
|---|---|---|
| 🛡️ | **하네스 (Harness)** | 위험한 명령을 막고, 결과를 독립적으로 검증하고, 긴 작업을 끊겨도 이어감 |
| 📚 | **위키 (Wiki)** | 검증된 학습을 문서로 쌓아 다음 작업에 재사용 |
| 🤖 | **Hermes 스킬 자동화** | 성공한 작업을 재사용 스킬로 자동 추출 (사람 승인 후 활성) |

`init`은 세 축의 **골격**을 설치합니다 — 하네스(위험 명령 차단·작업 규칙)는 **즉시 작동**하고, 위키·스킬은 작업하며 채워 가는 빈 그릇으로 시작합니다.

> 설치물은 마크다운·JSON·셸 스크립트 몇 개뿐입니다. (Python 패키지 없음)

---

## 🛡️ 하네스 — 통제와 검증

**하네스란?** LLM에게 일을 맡길 때 *규칙·차단·검증*을 거는 통제 장치입니다.
모델은 똑똑하지만 가끔 위험한 명령을 실행하고, 자기 결과를 스스로 "잘했다"고 착각하며,
긴 작업을 중간에 끝내버립니다. 하네스가 이를 **강제로** 잡아줍니다.

> *훅(hook) = Claude Code가 도구를 쓰기 직전/직후, 또는 끝내려 할 때 자동 실행하는 스크립트.*

| 기능 | 왜 필요한가 | 어떻게 동작하나 |
|---|---|---|
| **위험 명령 차단** | 모델이 `rm -rf /`·`sudo`·비밀키(`.env`·`id_rsa`) 읽기를 실수로 실행할 수 있음 | 도구 실행 **직전** 훅이 검사해 거부 + 프로젝트 권한 설정, 2중 방어 |
| **독립 검증** | 작업한 본인은 자기 결과를 객관적으로 못 봄(자기평가 편향) | 과정을 **못 본** 별도 에이전트가 결과만 보고 합격/불합격 판정 |
| **긴 작업 이어가기** | 세션 종료·컨텍스트 한계로 긴 작업이 중간에 끊김 | 진행 상황·남은 할 일 파일로 재개. 할 일이 남으면 **종료도 막음** |
| **작업 규칙** | "생각 먼저 · 단순하게 · 최소 변경 · 검증 먼저"를 매번 지시하기 번거로움 | `AGENTS.md`에 적어 **매 세션 자동 로드** |
| **작업 기록** | 무엇을 했는지 추적·감사가 필요함 | 모든 도구 호출을 `.omniharness/audit.jsonl`에 기록 |

## 📚 위키 — 배운 것을 쌓는다

**무엇인가?** 프로젝트에서 검증된 학습("이 모듈은 이렇게 동작한다", "이 함정을 조심하라")을
구조화된 위키 문서로 축적합니다.

**왜 필요한가?** Claude는 세션이 끝나면 배운 것을 잊습니다. 위키가 없으면 다음 세션이 같은 코드를
다시 탐색하고 같은 실수를 반복합니다. 위키에 쌓아두면 다음 작업이 바로 참조해 **더 빠르고 정확**해집니다.
(Andrej Karpathy가 제안한 "에이전트가 스스로 관리하는 지식 위키" 개념에서 따왔습니다.)

```
/omniharness:wiki-ingest        # 검증된 학습을 위키에 기록
/omniharness:wiki-lint          # 위키 내용이 현재 코드와 어긋났는지 점검
```

## 🤖 Hermes — 스킬 자동 생성

**무엇인가?** 한 번 성공한 작업 절차를 재사용 가능한 "스킬"로 자동 추출합니다.

**왜 필요한가?** 같은 종류의 작업을 매번 처음부터 다시 설명하고 수행하는 건 낭비입니다.
성공 경험을 스킬로 저장하면 다음에는 **한 번의 호출로 재사용**할 수 있습니다.

**안전장치** — 추출한 스킬을 *자동으로 켜지 않습니다.* 후보로 격리해 두고 **사람이 검토·승인**해야
활성화됩니다. 검증되지 않은 스킬이 그대로 적용되는 것을 막기 위함입니다.

```
/omniharness:skillify           # 성공한 작업 → 재사용 스킬 후보로 저장
/omniharness:promote <name>     # 검토 후 승인 → 활성화
```

---

## 설치

```bash
# 설치
/plugin marketplace add https://github.com/kbigdata/omniharness
/plugin install omniharness

# 아직 발행 안 한 로컬 버전으로 테스트
claude --plugin-dir /path/to/omniharness
```

## 사용

먼저 프로젝트에서 한 번 초기화합니다.

```
/omniharness:init
```

현재 프로젝트에 **하네스·위키·스킬 초기 파일**(작업 규칙·권한 설정·진행 파일·위키 폴더)을 만듭니다.
이후 작업부터 위험 명령 차단·독립 검증이 자동 적용됩니다. 나머지 명령:

| 명령 | 하는 일 |
|---|---|
| `/omniharness:skillify` | 성공한 작업 → 재사용 스킬 후보로 저장 |
| `/omniharness:promote <name>` | 검토 후 스킬 활성화 |
| `/omniharness:wiki-ingest` | 검증된 학습을 위키에 기록 |
| `/omniharness:wiki-lint` | 위키가 현재 코드와 어긋났는지 점검 |

## 동작 확인

- **오프라인(API 키 불필요)**: `bash tests/run.sh`
  — 훅 스크립트에 샘플 입력을 넣어 정상 동작을 확인합니다
  (위험/비밀키 **차단**, 정상 명령 **허용**, 작업 기록, 스킬 저장·중복 제거·활성화, 종료 방지, 초기 파일 생성).
- **실제 Claude Code**: `claude --plugin-dir .` 로 실행해 위험 명령이 **실제로 차단**되는지 확인.

## 폴더 구조

```
.claude-plugin/{plugin.json, marketplace.json}   # 플러그인 정보
hooks/hooks.json                                 # 어떤 훅을 언제 실행할지
scripts/*.py, scaffold.sh                         # 훅·검사·초기화 스크립트
agents/evaluator.md                               # 독립 검증 에이전트
skills/{init,skillify,wiki-ingest,promote,wiki-lint}/SKILL.md
templates/                                        # init이 프로젝트로 복사하는 초기 파일들
docs/                                             # 설계 근거 문서
tests/run.sh                                      # 오프라인 동작 확인
```
