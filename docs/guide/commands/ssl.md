# ssl

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/security_ssh_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic ssl --force`

## 호출

- Help 진입점: `ssl-help [section|--list|--all]`
- 통합 라우팅: `my-help ssl [section]`
- Alias: `ssl-help`

## 요약 (ssl-help)

- Usage: ssl-help [section|--list|--all]
- sections
    - status: SSL_CERT_FILE | REQUESTS_CA_BUNDLE | NODE_EXTRA_CA_CERTS
    - commands: echo $SSL_CERT_FILE | env grep cert
    - files: security.local.sh status
    - paths: Internal | External | System CA
    - tools: curl | wget | git | python | npm
    - notes: SSL_CERT_FILE | REQUESTS_CA_BUNDLE | NODE_EXTRA_CA_CERTS
    - details: ssl-help <section>  (example: ssl-help status)

## 섹션

### status

- SSL_CERT_FILE: /usr/local/share/ca-certificates/samsungsemi-prx.com.crt
-   ✓ File exists and is readable
- REQUESTS_CA_BUNDLE: /usr/local/share/ca-certificates/samsungsemi-prx.com.crt (Python requests)
- NODE_EXTRA_CA_CERTS: /usr/local/share/ca-certificates/samsungsemi-prx.com.crt (Node.js)

### commands

- echo $SSL_CERT_FILE                  Show SSL certificate file
- echo $REQUESTS_CA_BUNDLE             Show Python requests CA bundle
- env | grep -i cert                   Show all certificate vars

### files

- security.local.sh: not configured (public environment)

### paths

- Internal PC:  /usr/share/ca-certificates/extra/McAfee_Certificate.crt
- External PC:  /usr/local/share/ca-certificates/samsungsemi-prx.com.crt
- System CA:    /etc/ssl/certs/ca-certificates.crt

### tools

- curl                 - Web requests and downloads
- wget                 - File downloads
- git                  - Git operations (HTTPS)
- python (requests)    - HTTP library
- npm                  - Node.js package manager

### notes

- Different variables for different tools:
-   - SSL_CERT_FILE:        curl, wget, git
-   - REQUESTS_CA_BUNDLE:   Python requests
-   - NODE_EXTRA_CA_CERTS:  Node.js

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/ssl.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/security_ssh_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
