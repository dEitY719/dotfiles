# bun

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/package_managers_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic bun --force`

## 호출

- Help 진입점: `bun-help [section|--list|--all]`
- 통합 라우팅: `my-help bun [section]`
- Alias: `bun-help`

## 요약 (bun-help)

- Usage: bun-help [section|--list|--all]
- sections
    - install: install-bun | uninstall-bun | bun-v
    - packages: bun-i | bun-id | bun-ig | bun-un | bun-update | bun-outdated
    - run: bun-run | bunx
    - examples: bunx oh-my-opencode | bunx create-next-app
    - config: ~/.bunfig.toml | internal vs external
    - troubleshoot: not found | registry | SSL
    - details: bun-help <section>  (example: bun-help packages)

## 섹션

### install

- **install-bun** — curl .../bun.sh/install — Install Bun
- **uninstall-bun** — Remove ~/.bun — Uninstall Bun
- **bun-v** — bun --version — Check version

### packages

- **bun-i** — bun install — Install deps
- **bun-id** — install --dev — Dev dependency
- **bun-ig** — install --global — Global install
- **bun-un** — bun remove — Remove package
- **bun-update** — bun update — Update deps
- **bun-outdated** — bun outdated — Check outdated

### run

- **bun-run** — bun run <script> — Run package.json script
- **bunx** — bun x <pkg> — Run package without install

### examples

- bunx oh-my-opencode install  : OMO 설치
- bunx create-next-app         : Next.js 프로젝트 생성

### config

- Config file  : ~/.bunfig.toml (dotfiles symlink)
- Environments : internal (Samsung registry), external (default)

### troubleshoot

- bun not found?   : Run install-bun
- Registry error?  : Check ~/.bunfig.toml registry setting
- SSL error?       : Verify cafile path in bunfig.toml
- Binary path: ~/.bun/bin

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/bun.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/package_managers_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
