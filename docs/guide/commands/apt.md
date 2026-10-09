# apt

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/apt_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic apt --force`

## 호출

- Help 진입점: `apt-help [section|--list|--all]`
- 통합 라우팅: `my-help apt [section]`
- Alias: `apt-help`

## 요약 (apt-help)

- Usage: apt-help [section|--list|--all]
- sections
    - update: au | aug | afa | adu | auug
    - cleanup: aar | aac | ac | afd | acheck
    - install: ai | ar | arp | adpkg
    - search: as | ash | ainfo | alist | aulist
    - deps: adep | ardep | afiles | awhich
    - hold: ahold | aunhold
    - ppa: appa_add | appa_list | appa_remove | aclean_kernel | astat | asize
    - details: apt-help <section>  (example: apt-help install)

## 섹션

### update

- **au** — apt-get update — Update lists
- **aug** — apt-get upgrade — Safe upgrade
- **afa** — apt-get full-upgrade — Aggressive upgrade
- **adu** — apt-get dist-upgrade — Dist upgrade
- **auug** — update+upgrade+cleanup — Full cleanup (auto-yes)

### cleanup

- **aar** — apt-get autoremove — Remove unused deps
- **aac** — apt-get autoclean — Clean old cache
- **ac** — apt-get clean — Clean all cache
- **afd** — apt-get install -f — Fix broken deps
- **acheck** — apt-get check — Verify consistency

### install

- **ai** — apt-get install — Install package
- **ar** — apt-get remove — Remove (keep config)
- **arp** — apt-get purge — Remove completely
- **adpkg** — dpkg -i — Install .deb file

### search

- **as** — apt-cache search — Search packages
- **ash** — apt-cache show — Show details
- **ainfo** — ainfo <pkg> — Info + deps
- **alist** — list --installed — List installed
- **aulist** — list --upgradable — List upgradable

### deps

- **adep** — depends <pkg> — Show deps
- **ardep** — rdepends <pkg> — Show reverse deps
- **afiles** — dpkg -L <pkg> — List files
- **awhich** — dpkg -S <file> — Find owner pkg

### hold

- **ahold** — apt-mark hold — Lock version
- **aunhold** — apt-mark unhold — Unlock version

### ppa

- **appa_add** — add-apt-repository — Add PPA
- **appa_list** — List PPAs — Show installed PPAs
- **appa_remove** — remove PPA — Remove PPA
- **aclean_kernel** — Clean kernels — Remove old kernels
- **astat** — Stats — System pkg stats
- **asize** — Cache size — Check cache size

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/apt.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/apt_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
