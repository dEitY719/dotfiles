# AWS Bedrock 사내 PC 부트스트랩

사내 PC 에서 Claude Code 를 AWS Bedrock 경로로 돌리기 위한 가이드. 외부/공용 PC 사용자는 이 문서를 읽을 필요가 없습니다 — `~/.dotfiles-setup-mode` 가 자동으로 차단합니다.

> **2026-08-18 — `~/.claude/settings.json` 소유자가 `gateway-cli` 로 바뀌었습니다.**
> 조직 LLM Gateway 전환 도구 **`gateway-cli setup`** 이 사내 PC 의 live settings.json 을 직접 씁니다. 따라서 `./aws/setup.sh` 의 settings.json 머지(#687) 와 `claude/settings.bedrock-overlay.example` 는 **deprecated** — 그 스크립트는 이제 `aws/aws.local.sh` + `~/.aws/config` 시드, 그리고 아래 예외 1건만 합니다. 모델/인증/env 문제는 `gateway-cli setup` → `gateway-cli verify` 로, 개인 설정은 `~/.claude/settings.local.json` 으로 갑니다. dotfiles 의 `.hooks`/`.statusLine` 은 세션 시작 훅 `claude/hooks/session-start-settings-drift.sh` 가 자동 복구하므로 보통은 사람이 할 일이 없습니다.
>
> **예외 (#1364)** — Claude Code 는 live 파일의 `.hooks.SessionStart` 에 등록된 훅만 호출합니다. 그래서 무언가가 live `.hooks` 를 통째로 날리면 그 자동 복구 훅의 등록도 같이 사라지고, 훅은 호출조차 되지 않아 스스로를 되살릴 수 없습니다. 그때만 **`./aws/setup.sh` 재실행** → 훅 등록 1건이 복구됩니다 (다른 키는 건드리지 않음). 이후 Claude Code 재시작.

## TL;DR

```
./setup.sh                                 # Step 1 (aws.local.sh + ~/.aws/config)
aws sso login                              # Step 3
gateway-cli setup && gateway-cli verify    # Step 3.5 (settings.json 소유자, 2026-08-18~)
./aws/install-otel-managed-settings.sh     # Step 4
claude                                     # Step 5
./aws/diagnose.sh                          # (선택) read-only 점검
```

Step 2 (`aws/aws.local.sh` 편집) 는 보통 건너뜁니다.

## 사전 준비 체크리스트

- [ ] `cat ~/.dotfiles-setup-mode` 결과가 `internal`
- [ ] `aws --version` 이 AWS CLI v2 를 반환 (v1 은 SSO 미지원)
- [ ] 현재 사용자에게 `sudo` 권한 있음
- [ ] `/usr/local/share/ca-certificates/samsungsemi-prx.com.crt` 존재

미충족 항목이 있으면 사내 위키로 가서 채운 다음 돌아오세요.

## Step 1 — `./setup.sh` 실행

```sh
./setup.sh
```

내부적으로 `./aws/setup.sh` 가 호출되어 아래 2 개 파일이 **자동 생성**됩니다 (이미 있으면 보존):

| 생성 파일 | 역할 |
|---|---|
| `aws/aws.local.sh` | 쉘 env (`AWS_CA_BUNDLE`, `AWS_REGION`, `CLAUDE_CODE_USE_BEDROCK`, `ANTHROPIC_BEDROCK_BASE_URL`) |
| `~/.aws/config` | AWS SSO 진입점 (account 518692946118, role AWSPS-AICoding-SLSI) |

`~/.claude/settings.json` 은 **여기서 만들어지지 않습니다** (2026-08-18~) — Step 3.5 의 `gateway-cli` 몫이고, `./aws/setup.sh` 가 실행 시 deprecation notice 로 알립니다. (파일이 **이미 있을 때** 그 안의 SessionStart 훅 등록 1건만 점검/복구합니다 — #1364. 파일을 새로 만들지는 않습니다.) 이 단계에서 사용자가 직접 copy-paste 할 내용은 **없습니다**.

## Step 2 — `aws/aws.local.sh` 편집 (보통 불필요)

기본값으로 모든 사내 PC 에서 동작합니다. 다음 경우에만 편집:

- 다른 VPC endpoint 를 쓰는 호스트 → `ANTHROPIC_BEDROCK_BASE_URL` 한 줄만 교체
- 사내 CA bundle 경로가 다른 배포 → `AWS_CA_BUNDLE` 한 줄만 교체

```sh
vi aws/aws.local.sh
```

## Step 3 — `aws sso login`

```sh
aws sso login
```

브라우저가 열려 dspublic AWS SSO 화면이 뜹니다. 사번 로그인 1회 → 토큰 발급. 이후 일정 시간 (보통 8시간) 동안 재로그인 불필요.

## Step 3.5 — `gateway-cli setup` (2026-08-18~)

```sh
gateway-cli setup && gateway-cli verify
```

`~/.claude/settings.json` 에 `apiKeyHelper` / `awsCredentialExport` / `awsAuthRefresh` / `cleanupPeriodDays` / `env.*` 를 씁니다. dotfiles 는 이 키들을 쓰지 않으므로 모델 목록이 비거나 인증이 깨지면 먼저 이 두 명령을 의심하세요. `setup` 은 `.statusLine.command` 도 덮어쓰지만 조치는 불필요 — 다음 세션 시작 시 drift 훅이 dotfiles statusline 으로 되돌리고 "auto-corrected" 로 알립니다.

설치 아티팩트 위치와 `gateway-cli env --persist` 의 tracked `zsh/zshrc` 오염 주의사항은 `docs/guide/internal-pc.md` → "Claude Code 인증 (gateway-cli)" 참고.

## Step 4 — OTel 텔레메트리 설치

```sh
./aws/install-otel-managed-settings.sh
```

`sudo` 비밀번호 1회 입력. `/etc/claude-code/managed-settings.json` 이 생성되며 `user.id` 가 자동으로 STS 콜러로 채워집니다. `jq` 미설치 시 자동 설치 시도.

## Step 5 — Claude Code 재시작

```sh
claude
```

`/model` 로 모델 목록이 노출되면 성공 (목록 내용은 `gateway-cli` 가 결정합니다).

## (선택) 진단 — `./aws/diagnose.sh`

Read-only. 위 단계가 빠짐없이 적용됐는지 PASS/FAIL/WARN 으로 보고하며 어떤 파일도 수정하지 않습니다. FAIL 이면 보고서 하단의 `Next:` 가이드를 따르되, settings.json 관련 FAIL 은 `gateway-cli verify` 로 교차 확인하세요.

## 어느 파일에 무엇을 붙이나

| 파일 | 누가 생성 | 사용자 편집? |
|---|---|---|
| `aws/aws.local.example` | (커밋됨) | **절대 X** — 템플릿입니다. `aws.local.sh` 만 편집. |
| `aws/aws.local.sh` | `./setup.sh` 자동 | 호스트별 VPC/CA 가 다를 때만 |
| `aws/aws-config.example` | (커밋됨) | **절대 X** — 다른 SSO 가 필요하면 `aws-config.local` 작성 |
| `aws/aws-config.local` | (사용자) | 다른 SSO account/role 쓸 때만 (옵션) |
| `~/.aws/config` | `./setup.sh` 자동 | 직접 편집보다 `aws-config.local` 권장 |
| `claude/settings.json` | (커밋됨, 모든 PC 공유 SSOT) | **절대 X** — `.hooks`/`.statusLine` 의 SSOT. 사내 PC 에는 drift 훅이 그 두 키만 전파 |
| `claude/settings.bedrock-overlay.example` | (커밋됨) | **deprecated 2026-08-18, unused** — 아무도 읽지 않습니다. 롤백 참조용 보존 |
| `~/.claude/settings.json` | 외부 PC: `./setup.sh` 실파일 복사 (#940) / 사내 PC: **`gateway-cli setup`** (2026-08-18~) | **직접 편집 X** — 사내 PC 는 `gateway-cli` 재실행에 지워집니다. 개인 키는 `settings.local.json` 에 |
| `~/.claude/settings.local.json` | (사용자) | 개인 override 의 정식 슬롯 (#924). Claude Code 가 native merge, local 이 이김 |
| `/etc/claude-code/managed-settings.json` | OTel installer 자동 | **절대 직접 편집 X** — installer 재실행 |

## 역인덱스 — "X 를 하고 싶다"

- **Bedrock region 변경** → `aws/aws.local.sh` 의 `AWS_REGION` (그리고 endpoint 도 같이 바꿔야 함)
- **다른 SSO account 사용** → `aws/aws-config.local` 작성 (gitignored)
- **모델 추가 등록** → `gateway-cli setup` (dotfiles 경로 아님). 개인 한정이면 `~/.claude/settings.local.json` 에 작성 (~~overlay + `./aws/setup.sh` 재실행~~ 은 2026-08-18 부터 무효)
- **OTel collector 주소 변경** → `aws/install-otel-managed-settings.sh` 의 `OTEL_ENDPOINT_HOST` 수정 후 재실행
- **사내 게이트웨이(a2g) 와 병행** → 불가. 둘 중 하나만 활성 (#677 O-1)

## 사내 공식 진단(`diagnose_linux.sh`) 결과 해석

`curl ... diagnose_linux.sh | bash` 로 실행하는 **사내 공식** 진단은 dotfiles 의 파일 배치를 모르기 때문에 다음 항목들이 항상 FAIL/WARN 으로 보고된다. **모두 정상이고 무시해도 된다**.

| 항목 | 사내 진단 메시지 | 실제 상태 | 이유 |
|---|---|---|---|
| 1-1) NODE_EXTRA_CA_CERTS bashrc 미등록 | `[FAIL] ~/.bashrc에 NODE_EXTRA_CA_CERTS 미등록` | OK — 환경변수 자체는 PASS | dotfiles 는 `shell-common/env/security.local.sh` 가 export. bashrc 자체에는 export 라인이 없다. |
| 2-3) AWS_CA_BUNDLE / CLAUDE_CODE_USE_BEDROCK / ANTHROPIC_BEDROCK_BASE_URL bashrc 미등록 | `[FAIL] ~/.bashrc에 ... 미등록 → 영구 설정 안 됨` | OK — 모두 런타임 PASS | dotfiles 는 `aws/aws.local.sh` (`*.local.sh` 글로벌 패턴으로 gitignored) 가 export. bashrc 가 dotfiles 로더를 source 하므로 새 쉘에서도 그대로 살아난다. |
| 2-6) settings.json model / env / availableModels / modelOverrides / awsAuthRefresh | (구버전) 다수 FAIL/WARN | 2026-08-18~ 사내 진단이 정답 — 이 키들은 `gateway-cli setup` 이 쓴다 | 과거 dotfiles 가 머지로 채우던 구간(#677/#687)이 종료됐다. FAIL 이면 실제 문제이므로 `gateway-cli setup` → `gateway-cli verify` 로 해결한다. |

정확한 진단은 dotfiles-aware 인 `./aws/diagnose.sh` (`aws/aws.local.sh`, `shell-common/env/security.local.sh`, `~/.claude/settings.json` 인지). 단 settings.json 항목은 2026-08-18 부터 `gateway-cli` 소유 영역이라 `gateway-cli verify` 로 교차 확인한다 — `settings.local.json` 자동 archive 는 폐지됐다.

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| Claude Code 가 401 / "credentials" 에러 | `aws sso login` 미수행 또는 토큰 만료 | `aws sso login` 재실행 |
| `./aws/install-otel-managed-settings.sh: aws sts get-caller-identity failed` | 위와 동일 | `aws sso login` 먼저 |
| 외부 PC 에서 `./aws/setup.sh` 가 아무 것도 안 함 | 의도된 동작 — `_dotfiles_setup_mode != internal` | 정상 |
| 사내 PC 에서 `./aws/setup.sh` 가 "DEPRECATED" 를 출력하고 settings.json 을 (거의) 안 건드림 | 의도된 동작 (2026-08-18~) — `gateway-cli` 가 소유자 | 정상. settings.json 재시드는 `gateway-cli setup`. 단 SessionStart 훅 등록 1건이 빠져 있으면 그것만 복구합니다 (#1364) |
| statusline 이 `-- / -- (--)` 만 나옴 · 새로 추가한 훅이 발화 안 함 | `gateway-cli setup` 이 `.statusLine` 을 덮어씀 / live `.hooks` 가 stale | **조치 불필요** — 세션 시작 시 `claude/hooks/session-start-settings-drift.sh` 가 자동 복구("auto-corrected"). 즉시 반영은 Claude Code 재시작 |
| 위 "auto-corrected" 메시지가 **아예 안 뜸** · live `.hooks` 가 통째로 비어 있음 | 자동 복구 훅 **자신의 등록**이 지워짐 → 훅이 호출조차 안 되는 부트스트랩 데드락 (#1364) | `./aws/setup.sh` 재실행 → 훅 등록 1건 복구 후 Claude Code 재시작. 확인: `jq '.hooks.SessionStart' ~/.claude/settings.json` |
| `cat ~/.dotfiles-setup-mode` 가 `internal` 인데도 skip | 파일에 공백/개행 섞임 | `echo internal > ~/.dotfiles-setup-mode` |
| `availableModels` 에 opus 가 안 보임 | `gateway-cli` 가 쓴 모델 목록 문제 (2026-08-18~). ~~settings.json 머지 실패 (#687)~~ 는 더 이상 원인이 아님 | `gateway-cli setup` → `gateway-cli verify`. 개인적으로만 추가하려면 `~/.claude/settings.local.json` |
| `400 The provided model identifier is invalid` | live settings.json 의 `env.ANTHROPIC_DEFAULT_*_MODEL` 이 잘못됐거나 비어 있음 | `gateway-cli setup` → `gateway-cli verify`. (~~`./aws/setup.sh` 재실행~~ 은 2026-08-18 부터 이 증상엔 무효 — 그 스크립트는 모델/env 키를 쓰지 않는다. #1364 의 훅 등록 복구는 별개 증상) |
| OTel collector 도달 실패 | `10.172.25.203:80` 비도달 (VPN/방화벽) | 사내망 연결 확인. installer 자체는 성공 — 런타임 별 문제. |
| Claude Code 가 "not login" 으로 떨어짐 | live settings.json 의 auth 키(`apiKeyHelper` / `awsCredentialExport` / `env.ANTHROPIC_*`) 가 깨졌거나 SSO 토큰 만료. **주의**: 2026-08-18 부터 `env.ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN` 은 gateway 정상 구성의 일부이므로 더 이상 "제거 대상 레거시 키"가 아니다 (~~#677 O-1 의 strip 정책 폐기~~) | `aws sso login` → `gateway-cli setup` → `gateway-cli verify` |
| `[FAIL] AWS_CA_BUNDLE 파일 없음: /usr/local/share/ca-certificates/samsungsemi-prx.com.crt` | 옛 템플릿이 가리키던 경로에 cert 가 없음 (Ubuntu 가 `update-ca-certificates` 로 `/etc/ssl/certs/ca-certificates.crt` 에만 머지한 경우) | 한 줄로 교체: `sed -i 's\|^export AWS_CA_BUNDLE=.*\|export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt\|' aws/aws.local.sh` 후 새 쉘. `./aws/setup.sh` 가 재실행 시 동일 경고를 띄운다 (이 경고는 계속 유효 — CA bundle 은 여전히 dotfiles 소유). |

## 참고

- 설계 이슈: [#677](https://github.com/dEitY719/dotfiles/issues/677) (settings.json 머지 부분은 2026-08-18 종료)
- settings.json 소유권 이관 (2026-08-18): `claude/AGENTS.md` → Configuration Files, `docs/public/changelog.d/2026-08-18-806.md`
- AGENTS.md (자동화·리뷰어용 SSOT): `aws/AGENTS.md`
- 메모리: `samsung-internal-llm-gateway`, `user-dual-pc-workflow`
