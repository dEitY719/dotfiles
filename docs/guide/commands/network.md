# network

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/system_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic network --force`

## 호출

- Help 진입점: `network-help [section|--list|--all]`
- 통합 라우팅: `my-help network [section]`
- Alias: `network-help`

## 요약 (network-help)

- Usage: network-help [section|--list|--all]
- sections
    - diagnostics: check-network | quick | dns | ping | https | git | apt | pip | curl
    - typical: check-network | check-network quick | check-proxy
    - checks: DNS | ICMP | HTTPS | git | apt | pip
    - notes: ICMP fallback | APT auto-skip | check-proxy
    - details: network-help <section>  (example: network-help diagnostics)

## 섹션

### diagnostics

- check-network         Run full network diagnostic
- check-network quick   DNS + HTTPS + git quick check
- check-network dns     DNS resolution test
- check-network ping    ICMP ping test
- check-network https   HTTPS HEAD request test
- check-network git     Git remote access test
- check-network apt     APT repository reachability
- check-network pip     pip repository reachability
- check-network curl    curl GET request test

### typical

- check-network         Verify internet access end-to-end
- check-network quick   Fast sanity check after shell startup
- check-proxy           Diagnose proxy-specific configuration

### checks

- DNS lookup to confirm name resolution
- ICMP ping to detect low-level reachability
- HTTPS and curl requests to validate outbound web access
- git, apt, and pip endpoints for real tool-level access

### notes

- ICMP ping may fail even when normal web traffic works
- APT check is skipped automatically on non-APT systems
- Use check-proxy for proxy variables and proxy.local.sh issues

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/network.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/system_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
