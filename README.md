# omniharness — Claude Code 안전장치 플러그인

[![CI](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml/badge.svg)](https://github.com/kbigdata/omniharness/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/kbigdata/omniharness?sort=semver)](https://github.com/kbigdata/omniharness/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![No Python framework](https://img.shields.io/badge/python-framework--free-blue)

*[English README](README.en.md)*

**omniharness**는 Claude Code에 **안전장치와 자동 점검**을 입히는 플러그인입니다.
설치하면 어떤 프로젝트에서든 Claude가:

- 💥 **위험한 명령을 자동으로 막습니다** — 예: `rm -rf /`, `sudo`, 비밀키(`.env`·`id_rsa`) 읽기
- 🔍 **자기 작업을 다른 에이전트가 따로 검사합니다** — 작업한 본인이 아니라, 과정을 못 본 별도 에이전트가 결과를 점검
- 🔄 **긴 작업이 중간에 끊겨도 이어서 합니다** — 진행 상황과 남은 할 일을 보고 재개
- 📚 **반복 작업은 재사용 스킬로, 배운 것은 위키로 쌓습니다**

> 설치물은 마크다운·JSON·셸 스크립트 몇 개뿐입니다. (Python 패키지 없음)

---

## 무엇을 해주나

> *훅(hook) = Claude Code가 도구를 쓰기 **직전/직후**, 또는 **끝내려 할 때** 자동 실행하는 사용자 스크립트.*

| 기능 | 하는 일 | 구현 방식 |
|---|---|---|
| **위험 명령 차단** | `rm -rf /`·`sudo`·비밀키 읽기 등을 실행 **전에** 자동 거부 | 도구 사용 직전 훅 + 프로젝트 권한 설정(`.claude/settings.json`), 2중 방어 |
| **작업 기록** | Claude가 쓴 모든 도구 호출을 로그 파일에 남김 | 도구 사용 직후 훅 → `.omniharness/audit.jsonl` |
| **중간 종료 방지** | 할 일이 남았는데 끝내려 하면 종료를 막음 | 종료 시점 훅 → 남은 할 일 목록(`feature_list.json`) 확인 |
| **독립 검증** | 작업 과정을 **못 본** 별도 에이전트가 결과만 보고 합격/불합격 판정 | 서브에이전트(`agents/evaluator.md`) — 별도 작업폴더에서 읽기 전용 실행 |
| **긴 작업 이어가기** | 세션이 끊겨도 진행 파일을 보고 다시 이어감 | `feature_list.json`·`claude-progress.txt` |
| **스킬 자동화** | 성공한 작업 방법을 재사용 스킬로 저장 (**사람이 승인해야** 활성화) | `/omniharness:skillify` → 검사 → `/omniharness:promote` |
| **지식 위키** | 검증된 학습을 위키 문서로 축적 | `/omniharness:wiki-ingest` |
| **작업 규칙** | 좋은 원칙(생각 먼저·단순하게·최소 변경·검증 먼저)을 매 세션 자동 로드 | `init`이 만드는 `AGENTS.md` |

## 설치 / 로컬 테스트

```bash
# 설치
/plugin marketplace add https://github.com/kbigdata/omniharness
/plugin install omniharness

# 아직 발행 안 한 로컬 버전으로 테스트
claude --plugin-dir /path/to/omniharness
```

## 사용

```
/omniharness:init               # 현재 프로젝트에 안전장치 초기 파일 생성(규칙·권한·위키·진행파일)
# (이후 작업) 위험 명령은 자동 차단, 결과는 검증 에이전트가 따로 점검
/omniharness:skillify           # 성공한 작업 → 재사용 스킬 후보로 저장
/omniharness:promote <name>     # 사람이 확인 후 스킬 활성화
/omniharness:wiki-ingest        # 검증된 학습 → 위키에 기록
/omniharness:wiki-lint          # 위키 내용이 현실과 어긋났는지 점검
```

## 동작 확인

- **오프라인(API 키 불필요)**: `bash tests/run.sh`
  — 훅 스크립트에 샘플 입력을 넣어 정상 동작을 확인합니다
  (위험/비밀키 **차단**, 정상 명령 **허용**, 작업 기록, 스킬 저장·중복 제거·활성화, 종료 방지, 초기 파일 생성).
- **실제 Claude Code**: `claude --plugin-dir .` 로 실행해 위험 명령이 **실제로 차단**되는지 확인.

## 폴더 구조

```
.claude-plugin/{plugin.json, marketplace.json}   # 플러그인 정보
hooks/hooks.json                                 # 어떤 훅을 언제 실행할지
scripts/*.py, scaffold.sh                         # 훅·검사·초기화 스크립트 (낱개 스크립트, 프레임워크 아님)
agents/evaluator.md                               # 독립 검증 에이전트
skills/{init,skillify,wiki-ingest,promote,wiki-lint}/SKILL.md
templates/                                        # init이 프로젝트로 복사하는 초기 파일들
docs/                                             # 설계 근거 문서
tests/run.sh                                      # 오프라인 동작 확인
```
