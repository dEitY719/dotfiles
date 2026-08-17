# proxy

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/devops_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic proxy --force`

## 호출

- Help 진입점: `proxy-help [section|--list|--all]`
- 통합 라우팅: `my-help proxy [section]`
- Alias: `proxy-help`

## 요약 (proxy-help)

- Usage: proxy-help [section|--list|--all]
- sections
    - diagnostics: check-proxy | env | file | shell | conn | git
    - commands: $http_proxy | $https_proxy | $no_proxy | env | grep proxy
    - set: export http_proxy | https_proxy | no_proxy
    - unset: unset HTTP_PROXY HTTPS_PROXY NO_PROXY
    - git: connectTimeout | lowSpeedLimit | lowSpeedTime | view config
    - related: check-network quick | check-network
    - notes: NO_PROXY commas | uppercase env | proxy-only check
    - details: proxy-help <section>  (example: proxy-help set)

## 섹션

### diagnostics

- check-proxy          Run full diagnostic
- check-proxy env      Environment variables only
- check-proxy file     proxy.local.sh file check
- check-proxy shell    Shell loading test
- check-proxy conn     Configured proxy connectivity test
- check-proxy git      Git configuration

### commands

- echo $http_proxy          Current proxy setting
- echo $https_proxy         Current HTTPS proxy
- echo $no_proxy            NO_PROXY exceptions
- env | grep -i proxy        Show all proxy vars

### set

- export http_proxy="http://proxy.example.com:8080"
- export https_proxy="http://proxy.example.com:8080"
- export no_proxy="localhost,127.0.0.1,.internal.domain.com"

### unset

- unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY

### git

- git config --global http.connectTimeout 60    Increase timeout
- git config --global http.lowSpeedLimit 0      Disable low speed limit
- git config --global http.lowSpeedTime 999999   Disable low speed time
- git config --global -l | grep proxy           View git proxy config

### related

- check-network quick       General internet access check
- check-network             DNS, HTTPS, git, apt, pip, curl checks

### notes

- NO_PROXY with spaces is not recognized - use commas only
- Some tools only recognize uppercase (HTTP_PROXY, HTTPS_PROXY)
- check-proxy focuses on proxy configuration only

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/proxy.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/devops_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
