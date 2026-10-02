# One-click 멱등 setup 정책

## 목표

`./setup.sh` 한 번으로 5대 PC(internal / external / public) 어디서든 공통 환경에
수렴한다. 새 도구·설정 부트스트랩은 수동 절차나 README 안내가 아니라 기존
setup 체인에 편입한다.

## 규칙

- **멱등**: 재실행해도 수렴 후에는 아무것도 바꾸지 않는다. 먼저 상태를 확인한다
  (파일 존재, 링크 대상 일치 등).
- **soft-fail**: 네트워크·선택적 바이너리 의존 단계는 경고와 수동 재시도 명령만
  출력하고 상위 `set -e` 를 깨지 않는다.
- **양쪽 모드 반영**: `~/.dotfiles-setup-mode` 를 확인한다. internal PC 는 단일
  계정이며 `~/.claude/settings.json` 을 gateway-cli 가 소유한다
  (`claude/setup.sh` internal 분기는 `_claude_account_setup_one` 을 타지 않는다).
  한쪽 경로에 단계를 추가하면 다른 쪽에도 반영한다.
- **계정별 작업**: `_claude_account_setup_one` 에 둔다(`claude-accounts` /
  `claude/setup.sh` 가 순회). 계정 루프를 새로 만들지 않는다.
- **절대경로 금지**: 추적되는 SSOT(`claude/settings.json` 등)에 `/home/<user>` 를
  쓰지 않는다. `${HOME}` / `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` 를 쓰고 대상
  존재를 가드한다.
- **live 설정을 직접 고치는 도구**(예: `herdr integration install`)는 SSOT 와
  drift 를 만든다. SSOT 복사보다 먼저 실행해 복사가 이기게 하고, 스텁 바이너리로
  bats 테스트를 추가한다.

## 사례

- `_claude_install_herdr_hook` (`shell-common/tools/integrations/claude.sh`) — #1855.
