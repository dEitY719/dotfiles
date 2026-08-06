# docker

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/devops_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic docker --force`

## 호출

- Help 진입점: `docker-help [section|--list|--all]`
- 통합 라우팅: `my-help docker [section]`
- Alias: `docker-help`

## 요약 (docker-help)

- Usage: docker-help [section|--list|--all]
- sections
    - compose: dc | dcu | dcud | dcd | dcl | dce
    - compose-extra: dcps | dcb | dcr | dcdv | dcdo | dcstop | dcstart
    - basics: dps | dpsa | di | dstats | dstop | drm | drmi | dlogs | dinspect
    - resources: ddf | dprune | dprune_full | dvols | dvol_rm | dnetwork_prune | dbuild_prune
    - utilities: dbash | denv | dinspect_env | dstopall | drmall | dexport | dinstall | dproxy_setup
    - i-want: goal-based lookup  (example: docker-help i-want)
    - --map: intent -> alias -> raw command table
    - raw: copy-paste-ready full commands  (example: docker-help raw resources)
    - lookup: alias -> raw command  (example: docker-help dprune)
    - details: docker-help <section>  (example: docker-help compose)

## 섹션

### compose

- **dc** — docker compose — Base command
- **dcu** — docker compose up — Foreground start
- **dcud** — docker compose up -d — Detached start
- **dcd** — docker compose down — Stop & remove
- **dcl** — logs <svc> — Smart logs (service/container)
- **dce** — exec <svc> <cmd> — Execute command

### compose-extra

- **dcps** — docker compose ps — Status
- **dcb** — docker compose build — Build services
- **dcr** — docker compose restart — Restart services
- **dcdv** — down -v — Stop & remove volumes
- **dcdo** — down --remove-orphans — Stop & remove orphan containers (fixes net 'still in use')
- **dcstop** — stop — Stop containers
- **dcstart** — start — Start containers

### basics

- **dps** — docker ps — Running containers
- **dpsa** — docker ps -a — All containers
- **di/dim** — docker images — List images
- **dstats** — docker stats — Resource usage
- **dstop** — docker stop — Stop container
- **drm** — docker rm — Remove container
- **drmi** — docker rmi — Remove image
- **dlogs** — docker logs -f — Follow logs
- **dinspect** — docker inspect — Inspect object

### resources

- **ddf** — system df — Disk usage
- **dprune** — system prune -f — Basic cleanup (-f only; keeps images & volumes)
- **dprune_full** — system prune -a --volumes — Deep cleanup (interactive; removes images+volumes)
- **dvols** — volume ls -f dangling — Dangling volumes
- **dvol_rm** — volume rm — Remove volume
- **dnetwork_prune** — network prune — Cleanup networks
- **dbuild_prune** — builder prune — Cleanup build cache

### utilities

- **dbash** — dbash <name> — Shell access (bash/sh)
- **denv** — denv <name> — Show env vars
- **dinspect_env** — inspect env — Inspect env section
- **dstopall** — Stop all — Stop all running
- **drmall** — Remove all — Remove all containers
- **dexport** — Export all — Backup to tar files
- **dinstall** — Install script — Install Docker on WSL
- **dproxy_setup** — Proxy setup — Corporate proxy config
- Note: 'docker compose' (V2) is used by default.

### intent

- **start a stack** — dcud — docker compose up -d
- **start with overlay** — (raw) — docker compose -f a.yml -f b.yml up -d --build
- **stop a stack** — dcd — docker compose down
- **wipe data too** — dcdv — docker compose down -v
- **stop + clear orphans** — dcdo — docker compose down --remove-orphans
- **rebuild a service** — dcb <svc> — docker compose build <svc>
- **reset stack with volumes + rebuild** — (raw) — docker compose down -v && docker compose up -d --build
- **restart a service** — dcr <svc> — docker compose restart <svc>
- **follow logs** — dcl <svc> — docker compose logs -f <svc>
- **shell into container** — dbash <name> — docker exec -it <name> bash
- **list running** — dps — docker ps
- **list all** — dpsa — docker ps -a
- **disk usage** — ddf — docker system df
- **clean dangling** — dprune — docker system prune -f
- **reclaim everything** — dprune_full — docker system prune -a --volumes
- Hint: 'docker-help here' inspects the current directory for compose files.

### map

- **Intent** — Alias — Raw command
- **start a stack** — dcud — docker compose up -d
- **start with overlay** — (raw) — docker compose -f a.yml -f b.yml up -d --build
- **stop a stack** — dcd — docker compose down
- **wipe data too** — dcdv — docker compose down -v
- **stop + clear orphans** — dcdo — docker compose down --remove-orphans
- **rebuild a service** — dcb <svc> — docker compose build <svc>
- **reset stack with volumes + rebuild** — (raw) — docker compose down -v && docker compose up -d --build
- **restart a service** — dcr <svc> — docker compose restart <svc>
- **follow logs** — dcl <svc> — docker compose logs -f <svc>
- **shell into container** — dbash <name> — docker exec -it <name> bash
- **list running** — dps — docker ps
- **list all** — dpsa — docker ps -a
- **disk usage** — ddf — docker system df
- **clean dangling** — dprune — docker system prune -f
- **reclaim everything** — dprune_full — docker system prune -a --volumes
- Hint: 'docker-help here' inspects the current directory for compose files.

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/docker.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/devops_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
