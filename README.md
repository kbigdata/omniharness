# omniharness — Claude Code 하네스 플러그인

[![Release](https://img.shields.io/github/v/release/kbigdata/omniharness?sort=semver)](https://github.com/kbigdata/omniharness/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![No Python framework](https://img.shields.io/badge/python-framework--free-blue)

> 어떤 프로젝트든 **강제(권한 훅) · 신선검증(서브에이전트) · 장기실행 인계 · 자기개선(스킬/위키)**을
> 갖춘 하네스로 바꾸는 **Claude Code 플러그인**.
> **Python 패키지·프레임워크 없음** — 하네스 부품을 *재구현*하지 않고 Claude Code 네이티브
> (hooks · skills · subagents · settings)로 *구성*한다. (셸/훅 스크립트 몇 개뿐.)

설계 기준은 [`docs/하네스-엔지니어링-갭분석.md`](docs/하네스-엔지니어링-갭분석.md)(Anthropic 하네스 프레임워크 종합).

## 왜 플러그인인가
이전 Python 라이브러리(superharness/omni-harness)는 자기개선 코드가 superharness와 구조가 닮았다.
플러그인으로 가면 **Python backend/loop 자체가 사라져** 그 닮음이 없어지고, 강제·도구·스킬·루프를
**Claude Code가 네이티브로** 한다.

## 하네스 부품 → Claude Code 메커니즘

| 부품 (GAP) | 메커니즘 |
|---|---|
| **강제 계층**(§6/§7) | `hooks/` PreToolUse → `scripts/policy.py`(파괴/시크릿 deny) **+** init이 프로젝트 `.claude/settings.json`에 deny/ask (2겹) |
| **관측**(§3) | PostToolUse → `scripts/audit.py` (`.omniharness/audit.jsonl`) |
| **지속/조기완료 방지**(§4) | Stop 훅 → `scripts/stop_guard.py` (feature_list 미완료면 종료 차단) |
| **신선검증**(§10) | `agents/evaluator.md` 서브에이전트 (`isolation: worktree` = 생성 못 본 별도 컨텍스트) |
| **실행 루프**(§4) | Claude Code 네이티브 루프 + `AGENTS.md` 세션 의례 |
| **장기실행 인계**(§9) | `templates/`(feature_list.json·init.sh·claude-progress.txt) + `/omniharness:init` |
| **자기개선 Hermes** | `skills/skillify` → `scripts/skill_gate.py`(격리) → `/omniharness:promote` |
| **카파시 위키** | `skills/wiki-ingest` + `templates/wiki/` + `/omniharness:wiki-lint` |
| **헌법** | init이 `AGENTS.md`(카파시 4원칙+verify-first) 스캐폴드 (네이티브 로드) |

## 설치 / 로컬 테스트
```bash
# 설치
/plugin marketplace add https://github.com/<owner>/omniharness
/plugin install omniharness

# 로컬(미발행) 테스트
claude --plugin-dir /path/to/omniharness
```

## 사용
```
/omniharness:init               # 프로젝트를 하네스로 스캐폴드(헌법·권한·위키·인계)
# (작업) 파괴 명령은 자동 차단, 검증은 evaluator 서브에이전트로 독립 수행
/omniharness:skillify           # 성공 경험 → 재사용 스킬 후보(격리)
/omniharness:promote <name>     # 사람 승인 → 활성화
/omniharness:wiki-ingest        # 검증된 학습 → 위키
/omniharness:wiki-lint          # 위키 drift 점검
```

## 검증
- **오프라인(키 불필요)**: `bash tests/run.sh` — 훅/게이트 스크립트에 샘플 JSON 주입해 단언
  (파괴/시크릿 deny, 정상 allow, 감사 기록, 스킬 격리·dedup·promote, Stop 가드, 스캐폴드).
- **실제 Claude Code**: `claude --plugin-dir .` → 파괴 명령이 PreToolUse 훅에 **실제 차단**되는지 확인.

## 구조
```
.claude-plugin/{plugin.json, marketplace.json}   # 매니페스트
hooks/hooks.json                                 # PreToolUse·PostToolUse·Stop
scripts/*.py, scaffold.sh                         # 훅/게이트/유틸(단일 스크립트, 프레임워크 아님)
agents/evaluator.md                               # 신선 평가자
skills/{init,skillify,wiki-ingest,promote,wiki-lint}/SKILL.md
templates/                                        # init이 프로젝트로 복사
docs/                                             # 갭분석·환경계층·하네스가정
tests/run.sh                                      # 오프라인 검증
```
화석화 방지(GAP §4.3): 각 스크립트가 "보완하는 모델 약점"을 docstring에 명시 → [`docs/하네스-가정.md`](docs/하네스-가정.md).
