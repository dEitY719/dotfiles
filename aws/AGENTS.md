# aws/ — AGENTS.md

내부 (사내) PC 전용 AWS SSO/CLI 부트스트랩 디렉토리. 외부 PC에서는 본 디렉토리의 어떤 스크립트도 효과가 없다 (`_dotfiles_setup_mode` 게이트로 차단).

> **DEPRECATED (2026-08-18)** — `setup.sh` 의 `~/.claude/settings.json` 머지 책임은 종료됐다. 사내 PC 의 live settings.json 은 조직 LLM Gateway 전환 도구 **`gateway-cli setup`** 이 소유한다 (`apiKeyHelper`/`awsCredentialExport`/`awsAuthRefresh`/`cleanupPeriodDays`/`env.*`). `claude/settings.bedrock-overlay.example` 도 함께 deprecated (삭제하지 않고 롤백 참조용 보존). dotfiles 가 그 파일에 남긴 지분은 두 개뿐이다: (1) SessionStart 훅 `claude/hooks/session-start-settings-drift.sh` 의 `.hooks`/`.statusLine` 자동 복구, (2) 그 훅 **자신의 등록** 1건을 `setup.sh` 가 되살리는 F-7b (#1364).

운영자(사람) 워크스루는 **`aws/README.md`** 에 있다. 이 파일은 AI 에이전트·자동화·리뷰어용 SSOT 안내다.

## 책임 (SRP)

| 파일 | 책임 |
|---|---|
| `aws.local.example` | 쉘 env 템플릿 (`AWS_CA_BUNDLE`, `AWS_REGION`, `CLAUDE_CODE_USE_BEDROCK`, `ANTHROPIC_BEDROCK_BASE_URL`) |
| `aws-config.example` | `~/.aws/config` 템플릿 (dspublic SSO + role + region) |
| `setup.sh` | internal 모드일 때만: `aws.local.sh` / `~/.aws/config` 시드 + live `.hooks.SessionStart` 의 drift-heal 훅 등록 1건 복구 (F-7b, #1364). settings.json **머지**는 deprecated (2026-08-18) — 실행 시 deprecation notice 출력 후 그 부분 skip |
| `install-otel-managed-settings.sh` | `aws sso login` 선행 후 사용자가 명시 실행. `/etc/claude-code/managed-settings.json` 생성 (sudo) |
| `diagnose.sh` | Read-only 진단. 5 단계 부트스트랩이 빠짐없이 적용됐는지 PASS/FAIL/WARN 으로 보고. 파일 수정 없음 |
| `README.md` | 사람-운영자용 5단계 워크스루 (≤150 줄) |
| `AGENTS.md` | 이 파일 — AI/리뷰어용 SSOT (≤100 줄) |

## SSOT 원칙

- AWS Bedrock 쉘 env 의 **유일한 source**: `aws/aws.local.sh` (gitignored, `*.local.sh` 글로벌 패턴).
- AWS SSO config 의 **유일한 source**: `~/.aws/config`. 호스트별 오버라이드가 필요하면 `aws/aws-config.local` (gitignored).
- Claude Code 사내-모드 live settings (`~/.claude/settings.json`, 실파일) 의 **주 writer 는 dotfiles 가 아니다** (2026-08-18~): `gateway-cli setup` 이 소유. dotfiles 측 SSOT `claude/settings.json` 은 `.hooks`/`.statusLine` 두 키에 대해서만 진실이고, 그 전파는 `claude/hooks/session-start-settings-drift.sh` 자동 복구가 담당한다. 단 그 훅의 **등록 자체**가 live 에서 사라지면 훅은 호출되지 않아 스스로를 못 살리므로, 그 1건만 `setup.sh` F-7b 가 되돌린다 (#1364). `claude/settings.bedrock-overlay.example` 는 **unused/deprecated** — 어떤 스크립트도 읽지 않는다.
- OTel managed-settings 의 **유일한 source**: `/etc/claude-code/managed-settings.json` (시스템 경로). 동적 값(`user.id`) 은 STS 콜러에서 채움.

`bash/main.bash` / `zsh/main.zsh` 는 **수정하지 않는다**. 두 로더는 이미 `shell-common/env/*.sh` 를 자동 source 하므로 `shell-common/env/aws.sh` 가 자동 픽업된다.

## 실행 흐름

```
./setup.sh                       (루트 오케스트레이터)
  ├─ ./claude/setup.sh           (모든 모드 — internal 분기는 settings.json 자체를 건드리지 않음)
  └─ ./aws/setup.sh              (internal 모드일 때만 동작 / DEPRECATED 알림 출력)
        ├─ aws.local.sh          시드 (없을 때만)
        ├─ ~/.aws/config         시드 (없을 때만)
        └─ F-7b (#1364)          live .hooks.SessionStart 에 drift-heal 훅
                                 등록 1건이 없을 때만 append (파일 생성 안 함,
                                 symlink 면 skip, 그 외 키는 무손상)
           (#687 식 settings.json deep-merge 는 제거됨 — gateway-cli 소유)

사용자 수동 실행:
  aws sso login                  (브라우저 OAuth)
  ./aws/install-otel-managed-settings.sh   (sudo 1회, OTel)
  ./aws/diagnose.sh              (선택, read-only 점검)
```

## settings.json — dotfiles 는 더 이상 머지하지 않는다 (2026-08-18, #1364 예외 1건)

`_merge_claude_settings_json` (base * overlay * existing deep-merge, #687/#1088/#1130) 와 `_archive_legacy_settings_local` 은 **삭제**됐다. 사내 PC live `~/.claude/settings.json` 의 writer 는 `gateway-cli setup` 하나뿐이며, dotfiles 가 같은 파일을 다시 덮어쓰면 두 소유자가 서로의 키를 지우는 왕복이 된다 (2026-08-18 실측: gateway-cli 가 `.statusLine.command` 를 자기 바이너리로 덮어써 statusline 이 `-- / -- (--)` 플레이스홀더만 출력).

| 하고 싶은 일 | 지금의 경로 |
|---|---|
| 사내 PC auth/env/모델 재설정 | `gateway-cli setup` → `gateway-cli verify` |
| SSOT `.hooks` / `.statusLine` 을 live 에 반영 | 자동 — `claude/hooks/session-start-settings-drift.sh` (사내 모드 self-heal, 백업 `~/.claude-backups/settings.json.pre-drift-heal.backup`) |
| live 에서 **drift-heal 훅 등록 자체**가 사라짐 (훅이 아예 안 돌 때) | `./aws/setup.sh` 재실행 → F-7b 가 그 1건만 append (백업 `~/.claude/settings.json.pre-sessionstart-hook-reg.backup`), 이후 Claude Code 재시작 (#1364) |
| 개인 override (모델 등) | `~/.claude/settings.local.json` (#924). live `settings.json` 직접 편집 금지 |
| 레거시 Bedrock 오버레이 값 확인 | `claude/settings.bedrock-overlay.example` (읽기 전용 히스토리) |

`_seed_file` 기반 `aws.local.sh` / `~/.aws/config` 시드는 그대로 유지된다 — gateway-cli 는 AWS SSO 프로필과 CA bundle 을 만들지 않으므로 이 둘은 계속 dotfiles 소유다.

**F-7b (#1364) 스코프 경계** — `_reregister_session_start_drift_hook` 은 삭제된 `_merge_claude_settings_json` 의 부활이 아니다. 리뷰 시 이 선을 지킬 것: 훅 커맨드 문자열은 SSOT 에서 jq 로 읽고(하드코딩 금지), 대입하는 곳은 `.hooks` 뿐이며 그 안에서도 `.SessionStart` 뿐이다. gateway-cli 소유 키(`apiKeyHelper`/`awsCredentialExport`/`awsAuthRefresh`/`cleanupPeriodDays`/`env.*`)는 읽지도 쓰지도 않는다. 여기에 키를 하나라도 더 얹으면 #687 왕복이 재발한다. 회귀 가드: `tests/bats/setup/aws_merge_claude_settings.bats`.

## 외부 PC 안전망

- `setup.sh` 흐름은 `_dotfiles_setup_mode != internal` 일 때 즉시 no-op.
- `shell-common/env/aws.sh` 자체는 export 안 함 — `aws/aws.local.sh` 존재 시에만 source. 외부 PC 에 우연히 파일이 존재하게 되면 사고 (O-2). 런타임 이중 가드는 본 PR 에서는 미적용 (별 이슈 후속).

## 관련

- 이슈: #677
- SSOT 모드 헬퍼: `_dotfiles_setup_mode` (정의 위치: `shell-common/tools/integrations/claude.sh`)
- 유사 패턴: `shell-common/env/proxy.local.example` → `proxy.local.sh`
- CLAUDE.md 정책: POSIX 호환, 인터랙티브 가드, `bash/main.bash` 직접 수정 금지
