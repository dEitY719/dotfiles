# AWS Bedrock 사내 PC 부트스트랩

사내 PC 에서 Claude Code 를 AWS Bedrock 경로로 돌리기 위한 5단계 가이드. 외부/공용 PC 사용자는 이 문서를 읽을 필요가 없습니다 — `~/.dotfiles-setup-mode` 가 자동으로 차단합니다.

## TL;DR

```
./setup.sh                                 # Step 1
aws sso login                              # Step 3
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

내부적으로 `./aws/setup.sh` 가 호출되어 아래 3 개 파일이 **자동 생성**됩니다 (이미 있으면 보존):

| 생성 파일 | 역할 |
|---|---|
| `aws/aws.local.sh` | 쉘 env (`AWS_CA_BUNDLE`, `AWS_REGION`, `CLAUDE_CODE_USE_BEDROCK`, `ANTHROPIC_BEDROCK_BASE_URL`) |
| `~/.aws/config` | AWS SSO 진입점 (account 518692946118, role AWSPS-AICoding-SLSI) |
| `~/.claude/settings.json` (실파일, #687) | Claude Code 모델 매핑 (sonnet/haiku/opus → Bedrock IDs) — dotfiles SSOT + Bedrock 오버레이의 jq deep-merge 결과 |

이 단계에서 사용자가 직접 copy-paste 할 내용은 **없습니다**.

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

## Step 4 — OTel 텔레메트리 설치

```sh
./aws/install-otel-managed-settings.sh
```

`sudo` 비밀번호 1회 입력. `/etc/claude-code/managed-settings.json` 이 생성되며 `user.id` 가 자동으로 STS 콜러로 채워집니다. `jq` 미설치 시 자동 설치 시도.

## Step 5 — Claude Code 재시작

```sh
claude
```

`/model` 명령으로 `sonnet`, `haiku`, `claude-opus-4-7`, `claude-opus-4-6` 가 노출되면 성공.

## (선택) 진단 — `./aws/diagnose.sh`

```sh
./aws/diagnose.sh
```

Read-only. 위 1~5 단계가 빠짐없이 적용됐는지 PASS/FAIL/WARN 으로 보고합니다. 어떤 파일도 수정하지 않습니다. FAIL 이 있으면 보고서 하단의 `Next:` 가이드를 따라 재시도하세요.

## 어느 파일에 무엇을 붙이나

| 파일 | 누가 생성 | 사용자 편집? |
|---|---|---|
| `aws/aws.local.example` | (커밋됨) | **절대 X** — 템플릿입니다. `aws.local.sh` 만 편집. |
| `aws/aws.local.sh` | `./setup.sh` 자동 | 호스트별 VPC/CA 가 다를 때만 |
| `aws/aws-config.example` | (커밋됨) | **절대 X** — 다른 SSO 가 필요하면 `aws-config.local` 작성 |
| `aws/aws-config.local` | (사용자) | 다른 SSO account/role 쓸 때만 (옵션) |
| `~/.aws/config` | `./setup.sh` 자동 | 직접 편집보다 `aws-config.local` 권장 |
| `claude/settings.json` | (커밋됨, 모든 PC 공유 SSOT) | **절대 X** — 외부 PC 는 symlink, 사내 PC 는 머지 base |
| `claude/settings.bedrock-overlay.example` | (커밋됨, 사내 모드 한정) | **절대 X** — 템플릿입니다 (#687) |
| `~/.claude/settings.json` (#687) | 외부 PC: dotfiles symlink / 사내 PC: `./setup.sh` jq 머지 결과 실파일 | 사내 PC: 추가 키만 직접 추가 (기존 키 보존, gateway 키는 strip) |
| `/etc/claude-code/managed-settings.json` | OTel installer 자동 | **절대 직접 편집 X** — installer 재실행 |

## 역인덱스 — "X 를 하고 싶다"

- **Bedrock region 변경** → `aws/aws.local.sh` 의 `AWS_REGION` (그리고 endpoint 도 같이 바꿔야 함)
- **다른 SSO account 사용** → `aws/aws-config.local` 작성 (gitignored)
- **모델 추가 등록** → `claude/settings.bedrock-overlay.example` 의 `availableModels` + `modelOverrides` 수정 후 사내 PC 에서 `./aws/setup.sh` 재실행. 단발성 사용자 변경이면 `~/.claude/settings.json` 직접 편집해도 머지에서 보존됨 (existing 우선)
- **OTel collector 주소 변경** → `aws/install-otel-managed-settings.sh` 의 `OTEL_ENDPOINT_HOST` 수정 후 재실행
- **사내 게이트웨이(a2g) 와 병행** → 불가. 둘 중 하나만 활성 (#677 O-1)

## 사내 공식 진단(`diagnose_linux.sh`) 결과 해석

`curl ... diagnose_linux.sh | bash` 로 실행하는 **사내 공식** 진단은 dotfiles 의 파일 배치를 모르기 때문에 다음 항목들이 항상 FAIL/WARN 으로 보고된다. **모두 정상이고 무시해도 된다**.

| 항목 | 사내 진단 메시지 | 실제 상태 | 이유 |
|---|---|---|---|
| 1-1) NODE_EXTRA_CA_CERTS bashrc 미등록 | `[FAIL] ~/.bashrc에 NODE_EXTRA_CA_CERTS 미등록` | OK — 환경변수 자체는 PASS | dotfiles 는 `shell-common/env/security.local.sh` 가 export. bashrc 자체에는 export 라인이 없다. |
| 2-3) AWS_CA_BUNDLE / CLAUDE_CODE_USE_BEDROCK / ANTHROPIC_BEDROCK_BASE_URL bashrc 미등록 | `[FAIL] ~/.bashrc에 ... 미등록 → 영구 설정 안 됨` | OK — 모두 런타임 PASS | dotfiles 는 `aws/aws.local.sh` (`*.local.sh` 글로벌 패턴으로 gitignored) 가 export. bashrc 가 dotfiles 로더를 source 하므로 새 쉘에서도 그대로 살아난다. |
| 2-6) settings.json model / env / availableModels / modelOverrides / awsAuthRefresh — 사내 진단이 #687 이전 분리 디자인을 가정해 (`settings.local.json` 우선) 보고했음 | (구버전) 다수 FAIL/WARN | OK — #687 이후 모두 `~/.claude/settings.json` (실파일) 한 곳에 있음 | Bedrock 모델 매핑이 settings.local.json 의 deep-merge 에 의존하던 시절(#677) 의 미스매치는 해소됨. 이제 사내 진단의 settings.json 검사 자체가 통과한다. |

정확한 진단을 원하면 dotfiles-aware 인 로컬 진단을 쓰면 된다:

```sh
./aws/diagnose.sh
```

(`aws/aws.local.sh`, `shell-common/env/security.local.sh`, `~/.claude/settings.json` 까지 모두 인지한다. settings.local.json 잔존 시 deprecation 안내, #687.)

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| Claude Code 가 401 / "credentials" 에러 | `aws sso login` 미수행 또는 토큰 만료 | `aws sso login` 재실행 |
| `./aws/install-otel-managed-settings.sh: aws sts get-caller-identity failed` | 위와 동일 | `aws sso login` 먼저 |
| 외부 PC 에서 `./aws/setup.sh` 가 아무 것도 안 함 | 의도된 동작 — `_dotfiles_setup_mode != internal` | 정상 |
| `cat ~/.dotfiles-setup-mode` 가 `internal` 인데도 skip | 파일에 공백/개행 섞임 | `echo internal > ~/.dotfiles-setup-mode` |
| `availableModels` 에 opus 가 안 보임 | settings.json 머지 실패 (#687) | `~/.claude/settings.json` 확인, 필요시 백업 (`*.bedrock-merge-backup.*`) 복원 후 `./aws/setup.sh` 재실행 |
| `400 The provided model identifier is invalid` (`apac.anthropic.claude-sonnet-4-5-*`) | settings.json 의 `env.ANTHROPIC_DEFAULT_SONNET_MODEL` 미적용 — 옛 settings.local.json 분리 디자인의 deep-merge 가 사용자 환경에서 안 통한 사례 (#687) | `./aws/setup.sh` 재실행. ~/.claude/settings.json 이 dotfiles base + Bedrock 오버레이 머지 결과 실파일로 작성된다 (symlink 자동 해제). `./aws/diagnose.sh` 의 `2-6) env.ANTHROPIC_DEFAULT_SONNET_MODEL` PASS 확인. |
| OTel collector 도달 실패 | `10.172.25.203:80` 비도달 (VPN/방화벽) | 사내망 연결 확인. installer 자체는 성공 — 런타임 별 문제. |
| Claude Code 가 "not login" 으로 떨어짐 | settings.json 에 레거시 사내 게이트웨이 env (`ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_MODEL`/`ANTHROPIC_CUSTOM_HEADERS`/`NODE_TLS_REJECT_UNAUTHORIZED`) 잔존 — Bedrock 와 양립 불가 (#677 O-1) | `./aws/setup.sh` 재실행. 위 5 개 키는 머지 중 자동 제거되고 원본은 `*.bedrock-merge-backup.<timestamp>` 로 보존됨. 사전 점검은 `./aws/diagnose.sh` 의 `2-6)` 항목 |
| `[FAIL] AWS_CA_BUNDLE 파일 없음: /usr/local/share/ca-certificates/samsungsemi-prx.com.crt` | 옛 템플릿이 가리키던 경로에 cert 가 없음 (Ubuntu 가 `update-ca-certificates` 로 `/etc/ssl/certs/ca-certificates.crt` 에만 머지한 경우) | 한 줄로 교체: `sed -i 's\|^export AWS_CA_BUNDLE=.*\|export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt\|' aws/aws.local.sh` 후 새 쉘. `./aws/setup.sh` 가 재실행 시 동일 경고를 띄운다. |

## 참고

- 설계 이슈: [#677](https://github.com/dEitY719/dotfiles/issues/677)
- AGENTS.md (자동화·리뷰어용 SSOT): `aws/AGENTS.md`
- 메모리: `samsung-internal-llm-gateway`, `user-dual-pc-workflow`
