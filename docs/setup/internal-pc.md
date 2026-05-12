# Internal-PC Setup Guide (Samsung 사내 PC)

`setup.sh` 옵션 `2) Internal company PC (direct connection)` 선택 시 적용되는 단일-계정 흐름. 사외 PC의 멀티-계정(`personal` + `work`) 구조와 의도적으로 다르다. 도입 배경: issue #571.

## 왜 단일 계정인가

사내 PC는 한 명의 사번 (`x-user-id: <EMPLOYEE_ID>`) 으로만 식별되므로 `~/.claude-personal` / `~/.claude-work` 같은 분리가 의미 없다. 분리를 시도하면 두 계정이 같은 `settings.local.json`을 가리켜 사내 게이트웨이 설정이 personal 계정으로 새는 부작용이 생긴다.

## 무엇이 다른가

| 영역 | 사내 PC (옵션 2) | 사외 PC (옵션 1, 3) |
|---|---|---|
| Config dir | `~/.claude/` 직접 사용 | `~/.claude-personal/`, `~/.claude-work/` |
| `claude-accounts` 호출 | **스킵** | `setup` + `migrate` 사용 |
| `claude-yolo` 동작 | `~/.dotfiles-setup-mode == internal` 감지 시 `~/.claude/` 강제 | `_claude_resolve_account` 로 분기 |
| `settings.local.json` 위치 | `claude/settings.local.json` (gitignored) | 동일, 두 계정이 SSOT 공유 |

## 사내 게이트웨이 env 블록 추가

`./setup.sh` 실행 후 다음 파일을 편집한다 (gitignored, 푸시되지 않음):

```bash
$EDITOR claude/settings.local.json
```

블록 형식:

```json
{
  "env": {
    "GH_PR_REPLY_AUTO_APPROVE_REPOS": "dEitY719/dotfiles",
    "ANTHROPIC_BASE_URL": "http://a2g.samsungds.net:8090",
    "ANTHROPIC_AUTH_TOKEN": "",
    "ANTHROPIC_MODEL": "Qwen3.6-27B",
    "NODE_TLS_REJECT_UNAUTHORIZED": 0,
    "ANTHROPIC_CUSTOM_HEADERS": "x-user-id: <EMPLOYEE_ID>\nx-service-id: coding-agent-model-service"
  }
}
```

`<EMPLOYEE_ID>` 자리에 본인 사번을 채운다.

## env 블록은 어떻게 claude 프로세스에 도달하는가

두 경로가 동시에 활성화돼 있다 — defense-in-depth:

1. **Claude Code 본체**가 `~/.claude/settings.local.json` 의 `env` 블록을 읽어 자기
   서브프로세스에 주입. 정상 동작 시 이 경로만으로 충분.
2. **`claude_yolo`** (shell-common/tools/integrations/claude.sh) 가 같은 파일을
   `jq` 로 파싱하여 셸 레벨에서 `export` 한 뒤 `command claude` 실행. Claude Code
   특정 버전이 (1) 경로를 무시하더라도 `claude-yolo` 는 게이트웨이로 정상 연결된다.

(2) 경로는 `_claude_yolo_export_settings_env` 헬퍼가 담당하며, jq 미설치 / 파일
부재 / env 블록 부재 / JSON 파싱 실패 모두 silent no-op (회귀 0). 단위
테스트는 `tests/bats/integrations/claude_accounts.bats` 의 "settings.local.json
env block exports to shell process" 등.

## 보안 경고

1. **`claude/settings.local.json`은 절대 커밋되지 않는다** — `.gitignore`로 untracked. 의심되면:
   ```bash
   git check-ignore -v claude/settings.local.json
   # 출력 예: .gitignore:36:claude/settings.local.json    claude/settings.local.json
   ```
2. **`NODE_TLS_REJECT_UNAUTHORIZED=0`은 사내 자체 서명 인증서 통과용** — 외부 PC에는 절대 활성화 금지 (MITM 노출).
3. **사번 헤더는 PII** — `x-user-id` 가 외부로 새지 않도록 `claude/settings.local.example.json`에는 빈 placeholder만 둔다.

## 잘못 migrate된 사내 PC 복구

이미 `claude-accounts migrate` 를 실행해 `~/.claude-personal` / `~/.claude-work` 가 생성된 경우:

```bash
claude-accounts rollback        # 자동: 로그인된 계정 우선
# 또는
claude-accounts rollback work   # 명시
```

rollback 동작:
- 활성 계정의 `~/.claude-<active>` → `~/.claude` 로 이동
- 나머지 `~/.claude-<other>` → `~/.claude-<other>-rollback-<TS>-original` 로 백업 (자동 삭제 없음)
- 기존 `~/.claude/` 가 비어있지 않으면 `~/.claude-pre-rollback-<TS>-original` 로 백업

이후 `./setup.sh` 재실행 (옵션 2) 하면 단일-계정 심볼릭이 다시 설정된다.

## 검증

```bash
# Setup mode 확인
cat ~/.dotfiles-setup-mode    # internal

# 심볼릭 확인
ls -la ~/.claude/settings.local.json
# → ~/.claude/settings.local.json -> /home/<user>/dotfiles/claude/settings.local.json

# env 적용 확인 — 정상이면 사내 게이트웨이로 바로 연결됨.
# 만약 `Failed to connect to api.anthropic.com` 가 뜬다면:
#   1) `jq .env ~/.claude/settings.local.json` 으로 env 블록 유효성 확인
#   2) 새 셸 (`exec zsh`) 에서 `env | grep ANTHROPIC_` 출력 확인 —
#      claude_yolo 가 셸 레벨로 export 했으면 6 줄이 보여야 함
#   3) 둘 다 정상인데도 실패면 사내 게이트웨이/방화벽 이슈
claude-yolo
```

## 관련 코드

- `shell-common/setup.sh` — 환경 분기 SSOT, `~/.dotfiles-setup-mode` 작성
- `claude/setup.sh` — internal 모드일 때 single-account 분기 (`_single_account_ensure_link`)
- `shell-common/tools/integrations/claude.sh` — `_dotfiles_setup_mode`, `claude_yolo` F-2 분기, `claude_accounts_rollback`
- `.gitignore` — `claude/settings.local.json` untracked 강제

Issue/PR: #571 (분기 + 롤백 도입), #568 (멀티-계정 dispatcher 도입)
