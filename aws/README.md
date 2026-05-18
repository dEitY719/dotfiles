# AWS Bedrock 사내 PC 부트스트랩

사내 PC 에서 Claude Code 를 AWS Bedrock 경로로 돌리기 위한 5단계 가이드. 외부/공용 PC 사용자는 이 문서를 읽을 필요가 없습니다 — `~/.dotfiles-setup-mode` 가 자동으로 차단합니다.

## TL;DR

```
./setup.sh                                 # Step 1
aws sso login                              # Step 3
./aws/install-otel-managed-settings.sh     # Step 4
claude                                     # Step 5
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
| `~/.claude/settings.local.json` | Claude Code 모델 매핑 (sonnet/haiku/opus → Bedrock IDs) |

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

## 어느 파일에 무엇을 붙이나

| 파일 | 누가 생성 | 사용자 편집? |
|---|---|---|
| `aws/aws.local.example` | (커밋됨) | **절대 X** — 템플릿입니다. `aws.local.sh` 만 편집. |
| `aws/aws.local.sh` | `./setup.sh` 자동 | 호스트별 VPC/CA 가 다를 때만 |
| `aws/aws-config.example` | (커밋됨) | **절대 X** — 다른 SSO 가 필요하면 `aws-config.local` 작성 |
| `aws/aws-config.local` | (사용자) | 다른 SSO account/role 쓸 때만 (옵션) |
| `~/.aws/config` | `./setup.sh` 자동 | 직접 편집보다 `aws-config.local` 권장 |
| `claude/settings.local.bedrock.example` | (커밋됨) | **절대 X** — 템플릿입니다. |
| `~/.claude/settings.local.json` | `./setup.sh` jq 머지 | 추가 키만 직접 추가 (기존 키 보존됨) |
| `/etc/claude-code/managed-settings.json` | OTel installer 자동 | **절대 직접 편집 X** — installer 재실행 |

## 역인덱스 — "X 를 하고 싶다"

- **Bedrock region 변경** → `aws/aws.local.sh` 의 `AWS_REGION` (그리고 endpoint 도 같이 바꿔야 함)
- **다른 SSO account 사용** → `aws/aws-config.local` 작성 (gitignored)
- **모델 추가 등록** → `~/.claude/settings.local.json` 의 `availableModels` + `modelOverrides`
- **OTel collector 주소 변경** → `aws/install-otel-managed-settings.sh` 의 `OTEL_ENDPOINT_HOST` 수정 후 재실행
- **사내 게이트웨이(a2g) 와 병행** → 불가. 둘 중 하나만 활성 (#677 O-1)

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| Claude Code 가 401 / "credentials" 에러 | `aws sso login` 미수행 또는 토큰 만료 | `aws sso login` 재실행 |
| `./aws/install-otel-managed-settings.sh: aws sts get-caller-identity failed` | 위와 동일 | `aws sso login` 먼저 |
| 외부 PC 에서 `./aws/setup.sh` 가 아무 것도 안 함 | 의도된 동작 — `_dotfiles_setup_mode != internal` | 정상 |
| `cat ~/.dotfiles-setup-mode` 가 `internal` 인데도 skip | 파일에 공백/개행 섞임 | `echo internal > ~/.dotfiles-setup-mode` |
| `availableModels` 에 opus 가 안 보임 | settings.local.json 머지 실패 | `~/.claude/settings.local.json` 확인, 필요시 백업 (`*.bedrock-merge-backup.*`) 복원 후 재실행 |
| OTel collector 도달 실패 | `10.172.25.203:80` 비도달 (VPN/방화벽) | 사내망 연결 확인. installer 자체는 성공 — 런타임 별 문제. |
| Samsung a2g 경고 후 머지 skip | settings.local.json 에 a2g 게이트웨이 env 잔존 | 하나만 남기고 정리 — 양립 불가 |

## 참고

- 설계 이슈: [#677](https://github.com/dEitY719/dotfiles/issues/677)
- AGENTS.md (자동화·리뷰어용 SSOT): `aws/AGENTS.md`
- 메모리: `samsung-internal-llm-gateway`, `user-dual-pc-workflow`
