# opencode

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/opencode_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic opencode --force`

## 호출

- Help 진입점: `opencode-help [section|--list|--all]`
- 통합 라우팅: `my-help opencode [section]`
- Alias: `opencode-help`

## 요약 (opencode-help)

- Usage: opencode-help [section|--list|--all]
- sections
    - setup: opencode-status | opencode-install | opencode-update | opencode-uninstall | opencode-verify
    - utils: bunx oh-my-opencode install | install-bun | bun-help
    - env: home/public | external | internal
    - config: $OPENCODE_CONFIG_FILE | opencode-edit
    - models: Home | External | Internal
    - usage: opencode | opencode --help | opencode --version
    - trouble: opencode-status | opencode-verify | opencode-install
    - details: opencode-help <section>  (example: opencode-help models)

## 섹션

### setup

- opencode-status: show installation status
- opencode-install / opencode-update: use official installer (--dry-run, -y)
- opencode-uninstall: remove CLI and preserve user data (--dry-run, -y)
- opencode-uninstall --purge-config: also remove configuration
- Legacy names: install-opencode, update-opencode, uninstall-opencode
- opencode-verify: verify installation and configuration

### utils

- bunx oh-my-opencode install   : Oh My OpenCode (OMO) 인터페이스 설치
- bunx 없을 때             : install-bun 또는 bun-help 참고

### env

- home/public             : OpenCode defaults (no symlink)
- external                : localhost:4444 LiteLLM proxy
- internal                : internal LLM gateway (URL: DOTFILES_OPENCODE_BASE_URL)

### config

- Config file             : 
- Edit configuration      : opencode-edit

### models

- Home       : OpenCode defaults
- External   : gpt-oss-20b
- Internal   : Qwen3.6-27B

### usage

- opencode                     : Launch OpenCode interactive CLI
- opencode --help              : Show OpenCode help
- opencode --version           : Show OpenCode version

### trouble

- Not installed?          : Run install-opencode
- Outdated?               : Run update-opencode
- LLM not working?        : Run opencode-verify
- Want to remove?         : Run uninstall-opencode

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/opencode.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/opencode_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
