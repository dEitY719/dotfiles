# aws/ — AGENTS.md

내부 (사내) PC 전용 AWS Bedrock 부트스트랩 디렉토리. 외부 PC에서는 본 디렉토리의 어떤 스크립트도 효과가 없다 (`_dotfiles_setup_mode` 게이트로 차단).

운영자(사람) 워크스루는 **`aws/README.md`** 에 있다. 이 파일은 AI 에이전트·자동화·리뷰어용 SSOT 안내다.

## 책임 (SRP)

| 파일 | 책임 |
|---|---|
| `aws.local.example` | 쉘 env 템플릿 (`AWS_CA_BUNDLE`, `AWS_REGION`, `CLAUDE_CODE_USE_BEDROCK`, `ANTHROPIC_BEDROCK_BASE_URL`) |
| `aws-config.example` | `~/.aws/config` 템플릿 (dspublic SSO + role + region) |
| `setup.sh` | internal 모드일 때만 위 두 파일에서 `aws.local.sh` / `~/.aws/config` / `~/.claude/settings.local.json` 시드 |
| `install-otel-managed-settings.sh` | `aws sso login` 선행 후 사용자가 명시 실행. `/etc/claude-code/managed-settings.json` 생성 (sudo) |
| `diagnose.sh` | Read-only 진단. 5 단계 부트스트랩이 빠짐없이 적용됐는지 PASS/FAIL/WARN 으로 보고. 파일 수정 없음 |
| `README.md` | 사람-운영자용 5단계 워크스루 (≤150 줄) |
| `AGENTS.md` | 이 파일 — AI/리뷰어용 SSOT (≤100 줄) |

## SSOT 원칙

- AWS Bedrock 쉘 env 의 **유일한 source**: `aws/aws.local.sh` (gitignored, `*.local.sh` 글로벌 패턴).
- AWS SSO config 의 **유일한 source**: `~/.aws/config`. 호스트별 오버라이드가 필요하면 `aws/aws-config.local` (gitignored).
- Claude Code 모델 매핑의 **유일한 source**: `~/.claude/settings.local.json`. Repo 내 SSOT 템플릿은 `claude/settings.local.bedrock.example`.
- OTel managed-settings 의 **유일한 source**: `/etc/claude-code/managed-settings.json` (시스템 경로). 동적 값(`user.id`) 은 STS 콜러에서 채움.

`bash/main.bash` / `zsh/main.zsh` 는 **수정하지 않는다**. 두 로더는 이미 `shell-common/env/*.sh` 를 자동 source 하므로 `shell-common/env/aws.sh` 가 자동 픽업된다.

## 실행 흐름

```
./setup.sh                       (루트 오케스트레이터)
  └─ ./aws/setup.sh              (internal 모드일 때만 동작)
        ├─ aws.local.sh          시드 (없을 때만)
        ├─ ~/.aws/config         시드 (없을 때만)
        └─ ~/.claude/settings.local.json  jq 머지 (모델 매핑만)

사용자 수동 실행:
  aws sso login                  (브라우저 OAuth)
  ./aws/install-otel-managed-settings.sh   (sudo 1회, OTel)
  ./aws/diagnose.sh              (선택, read-only 점검)
```

## settings.local.json 머지 정책 (#677 O-1 broadened)

`_merge_claude_settings_local` 는 Bedrock 와 양립 불가한 레거시 사내-게이트웨이 env 키를 머지 중 **자동 제거**한다. 대상 키:

- `env.ANTHROPIC_BASE_URL`
- `env.ANTHROPIC_AUTH_TOKEN`
- `env.ANTHROPIC_MODEL`
- `env.ANTHROPIC_CUSTOM_HEADERS`
- `env.NODE_TLS_REJECT_UNAUTHORIZED`

URL 패턴 (`a2g.samsungds.net`) 매칭은 호스트 리브랜드 (`cloud.dtgpt.samsungds.net`) 에 깨졌으므로 **키 이름**을 기준으로 한다. 사용자가 의도적으로 게이트웨이 모드를 쓰려면 `aws/setup.sh` 자체를 호출하지 말아야 한다 (= external 모드). 원본은 타임스탬프 백업 (`*.bedrock-merge-backup.*`) 에 보존된다.

## 외부 PC 안전망

- `setup.sh` 흐름은 `_dotfiles_setup_mode != internal` 일 때 즉시 no-op.
- `shell-common/env/aws.sh` 자체는 export 안 함 — `aws/aws.local.sh` 존재 시에만 source. 외부 PC 에 우연히 파일이 존재하게 되면 사고 (O-2). 런타임 이중 가드는 본 PR 에서는 미적용 (별 이슈 후속).

## 관련

- 이슈: #677
- SSOT 모드 헬퍼: `_dotfiles_setup_mode` (정의 위치: `shell-common/tools/integrations/claude.sh`)
- 유사 패턴: `shell-common/env/proxy.local.example` → `proxy.local.sh`
- CLAUDE.md 정책: POSIX 호환, 인터랙티브 가드, `bash/main.bash` 직접 수정 금지
