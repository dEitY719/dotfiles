# pip

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/package_managers_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic pip --force`

## 호출

- Help 진입점: `pip-help [section|--list|--all]`
- 통합 라우팅: `my-help pip [section]`
- Alias: `pip-help`

## 요약 (pip-help)

- Usage: pip-help [section|--list|--all]
- sections
    - diagnostics: check-pip | config | file | repo | env
    - commands: pip config list | --verbose | view conf | --version
    - setup: ./setup.sh (Public | Internal | External)
    - repos: Proxy | Internal Repo | DataService Repo
    - notes: CA cert | setup.sh managed | symlink
    - details: pip-help <section>  (example: pip-help repos)

## 섹션

### diagnostics

- check-pip            Run full pip diagnostic
- check-pip config     Show pip configuration
- check-pip file       pip.conf file check
- check-pip repo       Repository connectivity test
- check-pip env        Environment variables

### commands

- pip config list                 Show all pip settings
- pip config list --verbose       Show pip config files loading
- cat $HOME/.config/pip/pip.conf  View user pip config
- pip --version                   Check pip version

### setup

- ./setup.sh                      Run setup (choose environment)
-                1) Public PC
-                2) Internal company PC (proxy + internal repo)
-                3) External company PC (VPN)

### repos

- Proxy:            http://12.26.204.100:8080
- Internal Repo:    http://repository.samsungds.net/repository/proxy-pypi-files.pythonhosted.org/simple
- DataService Repo: http://nexus.adpaas.cloud.samsungds.net/repository/dataservice-pypi/simple

### notes

- CA certificate: Configured via security.local.sh (REQUESTS_CA_BUNDLE)
- Config files are managed by setup.sh - do not edit manually
- Symlink: ~/.config/pip/pip.conf -> pip/pip.conf.{environment}

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/pip.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/package_managers_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
