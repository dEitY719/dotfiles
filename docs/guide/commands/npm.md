# npm

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/package_managers_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic npm --force`

## 호출

- Help 진입점: `npm-help [section|--list|--all]`
- 통합 라우팅: `my-help npm [section]`
- Alias: `npm-help`

## 요약 (npm-help)

- Usage: npm-help [section|--list|--all]
- sections
    - info: npm-v | npm-list | npm-info | npm-search | npm-outdated
    - install: npm-i | npm-is | npm-isd | npm-ig
    - uninstall: npm-un | npm-ung
    - maintenance: npm-update | npm-cache-clean
    - config: npm-config
    - setup: npminstall | npmuninstall
    - cert: crt-help | crtsetup
    - troubleshoot: EACCES | nvm conflict | certificate | config mismatch
    - details: npm-help <section>  (example: npm-help install)

## 섹션

### info

- **npm-v** — npm --version — Check version
- **npm-list** — list -g --depth=0 — Global packages
- **npm-info** — info <pkg> — Package details
- **npm-search** — search <keyword> — Search packages
- **npm-outdated** — outdated -g — Check updates

### install

- **npm-i** — npm install — Install deps
- **npm-is** — install --save — Save prod dep
- **npm-isd** — install --save-dev — Save dev dep
- **npm-ig** — install -g — Global install

### uninstall

- **npm-un** — npm uninstall — Remove dep
- **npm-ung** — uninstall -g — Remove global

### maintenance

- **npm-update** — update -g — Update global
- **npm-cache-clean** — cache clean --force — Clear cache

### config

- **npm-config** — Show current config — Registry, CA, SSL

### setup

- **npminstall** — Install Script — Install Node/NPM
- **npmuninstall** — Uninstall Script — Remove Node/NPM

### cert

- For CA certificate setup (company proxy/internal network):
- Run: crt-help for detailed guide
- Setup: crtsetup to install certificate

### troubleshoot

- EACCES permission error (npm WARN): npm config set prefix ~/.npm-global
- nvm과 npm prefix 충돌: .npmrc 파일의 prefix 라인 제거
- Certificate error: Run crt-help for CA setup guide
- Config mismatch: Run ./shell-common/setup.sh to reconfigure symlink
- Global Path: ~/.npm-global

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/npm.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/package_managers_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
