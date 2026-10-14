# Plugin Manifest (claude/plugin/)

> `claude/AGENTS.md` 에서 분리 (#2151). 요약·라우팅은 [`claude/AGENTS.md`](../AGENTS.md).

플러그인 변경은 **두 진입 경로** 모두에서 동기화된다:

1. **Shell CLI** (`claude plugin install/uninstall`, `claude plugin
   marketplace add/remove`) — `claude/hooks/plugin-sync.sh` (PostToolUse+Bash
   hook)가 명령어 문자열을 정규식으로 감지.
2. **내장 slash command** (`/plugin install|uninstall`, `/plugin marketplace
   add|remove`) — Claude Code UI 파이프라인을 통과해 Bash tool call 을 만들지
   않으므로 PostToolUse hook 이 안 잡힌다. `claude/hooks/plugin-sync-session.sh`
   (SessionStart+Stop hook)가 SSOT (`~/.claude-shared/plugins/{known_marketplaces,
   installed_plugins}.json`) 해시를 세션 시작 시 stash 하고, 매 Stop 마다 diff 해
   변화가 있으면 `plugin-sync.sh` 의 add/uninstall 분기를 재실행한다 — 진입 경로
   무관 (add + remove 대칭 처리, #1082). Claude Code 2.1.x 는 slash command 전용
   hook event 를 노출하지 않아 이 SSOT-diff 방식을 택했다.

두 경로 모두 공용(scope:user + source:github만) 항목을
`claude/plugin/{marketplaces,plugins}.local.json` **오버레이**에 병합 반영한다.

**계약 / 로컬 상태 분리 (#1685)** — 공용 매니페스트는 두 겹이다: tracked
`{marketplaces,plugins}.json` 은 upstream 이 소유하는 **등록 계약**(사람이 PR 로
변경, 훅은 읽기만 함)이고, gitignored `*.local.json` 은 **이 PC 의 설치 상태**
(`plugin-sync.sh` / `reconcile.sh --apply` 가 쓰는 유일한 대상)다. 한 파일이 두
소유자를 가지던 탓에 fork/mirror 가 upstream 의 등록 커밋마다 충돌했다. 소비자
(`restore.sh`, `reconcile.sh --check`)는 둘의 **union** 을 보되, 키가 충돌하면
**계약이 이긴다**(낡은 오버레이가 upstream 의 URL 정정을 덮어쓰지 못하도록).
공용 스코프는 더 이상 커밋하지 않는다 — `sync manifest` 자동 커밋은 `company/`
에만 남는다. 훅은 계약을 못 쓰므로, 계약 항목을 uninstall 하면 gitignored
`removed.local.json` **묘비**에 기록해 `restore.sh` 의 재설치를 막는다(재설치하면
묘비가 취소된다). 묘비는 스코프별 파일이고, 마켓플레이스 묘비는 그 마켓플레이스의
플러그인까지 복원 대상에서 뺀다.

커밋 제목의 변경 키 나열 규칙
(`... sync manifest (+foo -bar 외 N개)`)은 `shell-common/functions/plugin_sync_title.sh`
가 SSOT — `plugin-sync.sh` 의 벌크 재동기화 경로와 `claude/plugin/reconcile.sh
--apply` 가 같은 파일을 source 한다(#1558). 사내 전용
(non-github source) 항목은 `claude/plugin/company/`(dotfiles 트리 안이지만
자체 `.git`을 가진 별도 private GHES 레포, `.gitignore`로 public 레포
추적 제외)로 간다 — internal PC에서 최초 1회 `git clone <url>
claude/plugin/company` 필요.

external/public PC에서 사내 GHES 마켓플레이스가 우연히 감지되면(company/
레포 미clone) hook은 격리 정책상 저장하지 않고 stderr 힌트만 남긴다 — 조용한
skip이 아니다 (#1080).

신규 PC: `./claude/plugin/restore.sh` (mode-aware, `--dry-run` 지원). 대상
config dir 은 setup-mode 로 라우팅된다 (#1103) — internal → `~/.claude`,
그 외 → `~/.claude-<account>` (기본 `$CLAUDE_DEFAULT_ACCOUNT`). 특정 계정은
`--user <account>`, 전체 계정은 `--all-accounts`.

이미 설치된 플러그인 갱신: `./claude/plugin/update-plugins.sh` (`skills-sync` 4/5, `--dry-run`).
플러그인 저장소·version bump 규칙·진단 SSOT: `docs/.ssot/skills-distribution.md`.
`claude/workspace/AGENTS.md` 는 스킬 작업 폴더 루트 라우터 원본이다 —
`scripts/setup-skills-ssot.sh` 가 `${WORKSPACE_ROOT}/{AGENTS,CLAUDE}.md` 로 링크한다 (#2123).

두 레포 모두 "PR을 통해서만 변경 가능" 규칙이 걸려 있어 로컬 커밋이
origin에 직접 push되지 않는다 — `./claude/plugin/publish-sync.sh`
(`--dry-run` 지원)를 수동 실행하면 쌓인 변경분을 브랜치+PR+admin-merge로
게시한다. internal PC는 github.com이 pull-only라 public 단계를 자동으로
건너뛴다 (company/ GHES 단계만 게시, #1080). 자세한 설계: `docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md`,
`docs/feature/superpowers-specs/2026-07-02-plugin-manifest-batch-publish-design.md`.
