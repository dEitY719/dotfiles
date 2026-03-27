# Connect SSOT Skills

**초안** | Shell, Linux Configuration | 2026-03-27

| Field | Value |
|-------|-------|
| **Document ID** | connect-ssot-skills |
| **Title** | Multi-Tool Skill Integration with Single Source of Truth |
| **Type** | Feature Requirement Scratch |
| **Status** | Implemented ✅ |
| **Author** | Claude |

---

## Executive Summary

이 기능은 `claude/skills/`에 정의된 Skill들을 Claude뿐만 아니라 OpenCode, Codex, Gemini 등 다양한 도구에서 공통으로 사용할 수 있도록 연결하는 것을 목표로 합니다. 현재 분산되어 있거나 특정 도구에 종속된 Skill 관리 방식을 탈피하여, `claude/skills/`를 **Single Source of Truth (SSOT)**로 설정하고 이를 각 도구의 설정 경로에 효율적으로 노출하는 메커니즘을 설계합니다.

## 배경 (Background)

현재 `claude/skills/`의 내용이 `~/.claude/skills`에 mount 되어 사용되고 있는 환경에서, 동일한 내용을 `~/.config/opencode/skills/` 등 다른 도구의 경로에도 mount 하는 방식에 대한 기술적 우려가 있습니다. 중복 mount의 안정성 문제와 관리의 복잡성을 해결하기 위해 더 나은 연결 전략(예: Symlink)이 필요합니다.

## 목표 (Goals)

- `claude/skills/`를 모든 도구의 Skill 관리를 위한 유일한 원천(SSOT)으로 확립
- Claude, OpenCode, Codex, Gemini 등 다양한 도구에서 동일한 Skill 세트를 즉시 사용 가능하도록 연결
- 시스템 자원을 효율적으로 사용하며 유지보수가 용이한 연결 전략(Mount vs Symlink) 확정 및 구현

## 제안 설계 (Proposed Design)

### 핵심 구조

- **Source**: `~/dotfiles/claude/skills/` (SSOT)
- **Targets** (확정):

| 도구 | 경로 | 경로 형식 |
|------|------|-----------|
| Claude | `~/.claude/skills` | 전용 홈 디렉토리 |
| OpenCode | `~/.config/opencode/skills/` | XDG Base Dir 표준 |
| Codex | `~/.codex/skills/` | 전용 홈 디렉토리 |
| Gemini | `~/.gemini/skills/` | 전용 홈 디렉토리 |

### 주요 동작

1. **전략 선택**:
    - **Mount 전략**: `bind mount` 등을 사용하여 실시간 동기화. 권한 설정이 복잡할 수 있으며, 여러 지점 mount 시 커널 수준의 오버헤드나 충돌 가능성 검토 필요.
    - **Symlink 전략**: 각 도구의 설정 디렉토리에서 SSOT 디렉토리로 심볼릭 링크 생성. 가장 가볍고 일반적인 방식이나, 도구가 심볼릭 링크를 제대로 추적하는지 확인 필요.
2. **연결 자동화**: `setup.sh` 또는 별도의 관리 스크립트를 통해 도구별 경로에 연결 생성.
3. **SSOT 관리**: 모든 Skill 수정은 `claude/skills/`에서만 수행하며, 연결된 도구들은 이를 즉시 반영.

## 기술 요구사항 (Technical Requirements)

- Linux 환경(Ubuntu 등)에서의 동작 보장
- 각 도구(Claude CLI, OpenCode 등)의 Skill 로딩 메커니즘 분석 (심볼릭 링크 지원 여부 등)
- 기존 mount 설정과의 충돌 방지 및 안전한 전환 프로세스

## 에러 처리 및 엣지 케이스

- 타겟 디렉토리가 이미 존재하고 파일이 들어있는 경우의 처리 (백업 또는 병합 정책)
- 심볼릭 링크 연결이 끊어진 경우(Broken link)에 대한 감지 및 복구
- 도구별로 요구하는 Skill 파일 구조나 메타데이터 형식이 다를 경우의 대응

## 범위 및 제약 (Scope & Constraints)

### In Scope
- `claude/skills/`를 SSOT로 설정하는 아키텍처 설계
- Claude, OpenCode 등 주요 도구에 대한 연결 스크립트 작성
- Symlink vs Mount 전략 비교 분석 결과 포함

### Out of Scope
- 개별 Skill의 로직 수정
- Windows 등 타 OS 지원 (필요 시 추후 확장)

## 성공 지표 (Success Criteria)

| 지표 | 목표값 |
|------|--------|
| 지원 도구 수 | Claude, OpenCode, Codex, Gemini 4개 |
| 동기화 지연 시간 | 실시간 (파일 시스템 수준 연결) |
| 설정 복잡도 | 스크립트 실행 1회로 완료 |

## 미결 사항 (Open Questions)

- [x] opencode Skills 경로: `~/.config/opencode/skills/` ✅
- [x] Codex Skills 경로: `~/.codex/skills/` ✅
- [x] Gemini Skills 경로: `~/.gemini/skills/` ✅
- [x] Claude Skills 경로: `~/.claude/skills` ✅
- [x] symlink 생성 검증: opencode/gemini 전체 dir symlink, codex 36개 개별 symlink 모두 성공 ✅
- [x] idempotency 검증: 재실행 시 "이미 연결됨" skip 동작 확인 ✅
- [x] Codex `.system` 내장 스킬 보존 확인 ✅
- [x] Codex symlink를 통한 Skills 로드 동작 확인 ✅
- [x] Gemini symlink를 통한 Skills 로드 동작 확인 ✅
- [x] OpenCode symlink를 통한 Skills 로드 동작 확인 ✅
- [ ] `~/.claude/skills` bind mount → symlink 전환 가능 여부 검토 (현재 bind mount 유지 중)
- [ ] 동시 읽기/쓰기 Lock 문제 발생 여부 (실사용 중 모니터링)
