# setup-mode

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/setup_mode_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic setup_mode --force`

## 호출

- Help 진입점: `setup-mode-help [section|--list|--all]`
- 통합 라우팅: `my-help setup_mode [section]`
- Alias: `setup-mode-help`

## 요약 (setup-mode-help)

- Usage: setup-mode-help [section|--list|--all]
- sections
    - overview: tracks PC environment, auto-applies settings
    - modes: 1=Public | 2=Internal | 3=External(VPN)
    - usage: show-setup-mode | setup-mode-help | setup.sh
    - details: setup-mode-help <section>  (example: setup-mode-help modes)

## 섹션

### overview

- Tracks which environment your PC is configured for
- Automatically applies environment-specific settings
- Stored in: ~/.dotfiles-setup-mode

### modes

- **Mode 1** — Public PC (Home environment) — No proxy, no company configs
- **Mode 2** — Internal company PC (Direct) — Company proxy, internal repos, CA certs
- **Mode 3** — External company PC (VPN) — No proxy, VPN certificate

### usage

- **show-setup-mode** — Show current mode
- **setup-mode-help** — View this help
- Reconfigure: cd ~/dotfiles && ./setup.sh
- Check proxy: check-proxy

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/setup-mode.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/setup_mode_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
