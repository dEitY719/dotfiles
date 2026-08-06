# crt

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/security_ssh_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic crt --force`

## 호출

- Help 진입점: `crt-help [section|--list|--all]`
- 통합 라우팅: `my-help crt [section]`
- Alias: `crt-help`

## 요약 (crt-help)

- Usage: crt-help [section|--list|--all]
- sections
    - overview: npm/Node/Python CA | custom & system | security.local.sh
    - options: External (custom crt) | Internal (system CA)
    - setup: crtsetup
    - env: NODE_EXTRA_CA_CERTS | REQUESTS_CA_BUNDLE
    - config: shell-common/env/security.local.sh
    - related: npm-help | security.sh | setup.sh
    - details: crt-help <section>  (example: crt-help options)

## 섹션

### overview

- Manages CA certificates for npm, Node.js, and Python
- Supports custom certificates (company proxy) and system CA bundles
- Configuration stored in: shell-common/env/security.local.sh

### options

- Option 1: Custom Certificate (External Company PC - VPN)
-  • Certificate path: /usr/local/share/ca-certificates/samsungsemi-prx.com.crt
-  • Install with: crtsetup
- Option 2: System CA Bundle (Internal Company PC)
-  • Certificate path: /etc/ssl/certs/ca-certificates.crt
-  • Already system default, no setup needed

### setup

- **crtsetup** — Interactive CA certificate setup script

### env

- **NODE_EXTRA_CA_CERTS** — Used by Node.js/npm for certificate validation
- **REQUESTS_CA_BUNDLE** — Used by Python for certificate validation

### config

- Location: shell-common/env/security.local.sh

### related

- **npm-help** — NPM package manager commands and setup
- **security.sh** — Security environment variable configuration
- **setup.sh** — Initial environment-specific setup

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/crt.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/security_ssh_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
