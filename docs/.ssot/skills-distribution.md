# 스킬 배포 구조 (작업 사본 vs Claude 플러그인 저장소)

스킬 1벌이 두 경로로 배포된다. **Claude Code 는 작업 사본을 읽지 않는다** — 작업 사본만
갱신하고 Claude 에 새 스킬이 안 보이는 실수가 반복돼 이 문서를 둔다 (#2123).

## 1. 배포 경로

```
GitHub repo ──git pull──> ${WORKSPACE_ROOT:-~/para/project/skills}/<repo>   (작업 사본)
                            └─ 심볼릭 링크 / external_dirs ─> Codex / agy / OpenCode / Hermes  (즉시 반영)
GitHub repo ──claude plugin marketplace update + claude plugin update──>
            플러그인 저장소: marketplaces/<mkt>  +  cache/<mkt>/<plugin>/<version>
                            └─> Claude Code  (여기서만 로드, 세션 시작 시)
```

- 작업 사본 열거 SSOT: `shell-common/lib/skill_sources.sh`. 비-Claude 도구 합성:
  `scripts/setup-skills-ssot.sh`.
- 이 코드들이 사는 위치별 역할표와 "새 기능은 어디에" 결정 트리:
  [`claude/plugin/README.md`](../../claude/plugin/README.md) (#2147).
- Claude Code 쪽 목록 SSOT: `claude/plugin/{marketplaces,plugins}.json`. 신규 등록·설치는
  `claude/plugin/restore.sh`, 이미 설치된 것의 갱신은 `claude/plugin/update-plugins.sh`.
  둘 다 `skills-sync` 단계다 (#2344) — restore 는 owner 필터 없이 매니페스트 전체, update 는
  dEitY719 만 대상이라 범위가 다르므로 한 스크립트로 합치지 않는다.
- dEitY719 마켓플레이스에는 `autoUpdate` 가 없다. 명시적으로 갱신하지 않으면 설치 시점
  버전에 머문다 (사례: gh-flow 가 0.1.13 에 머문 채 소스는 0.2.0).

## 2. 모드별 플러그인 저장소 위치

| 모드 | 실제 저장소 | 계정 경로 | 비고 |
|------|-------------|-----------|------|
| public / external | `~/.claude-shared/plugins` | `~/.claude-<acct>/plugins` → 심볼릭 링크 | 한 번 갱신하면 모든 계정에 반영 |
| internal | `~/.claude-shared/plugins` | `~/.claude/plugins` → 심볼릭 링크 (단일 계정) | `claude/setup.sh` internal 분기가 수렴시킨다. setup 재실행 전 PC 는 `~/.claude/plugins` 가 실제 폴더일 수 있다 — `ls -la ~/.claude/plugins` 로 확인 |

`update-plugins.sh` 는 internal 이면 `CLAUDE_CONFIG_DIR=~/.claude`, 그 외는
`~/.claude-<account>` (기본 personal, `--user`) 로 `claude plugin` 을 실행한다. 저장소가
공유이므로 계정 하나로 돌리면 충분하다. 모드 판별: `cat ~/.dotfiles-setup-mode`
([pc-environment.md](./pc-environment.md) §4).

## 3. `skills-sync` 6단계 (`scripts/update-skills.sh`)

| 단계 | 스크립트 | 갱신 대상 |
|------|----------|-----------|
| 1/6 | `claude/plugin/git-clone-skills.sh` | 없는 작업 사본 clone (선택: gitignored `claude/plugin/skills-workspace.local.json` 의 `{"<repo>": "<folder>"}` 로 폴더명 변경, #2241. 폴더를 하드코딩한 `scripts/measure-skill-descriptions.sh` (`authoring-skills`) 는 매핑을 따르지 않는다. 추가 clone 대상: gitignored `claude/plugin/skills-workspace-repos.local.json` 의 `{"<name>": "<owner>/<repo>"}` 를 tracked manifest 와 합집합으로 읽고 owner 필터를 거치지 않는다, #2244 — 훅이 쓰고 restore.sh 가 marketplace 로 등록하는 `marketplaces.local.json` 은 읽지 않는다) |
| 2/6 | `claude/plugin/git-pull-skills.sh` | 작업 사본 `git pull --ff-only` |
| 3/6 | `claude/setup.sh` | 계정 디렉토리 링크, 남은 평면 스킬 링크 정리 (스킬 자체는 플러그인으로 로드) |
| 4/6 | `claude/plugin/restore.sh --skip-if-no-claude` | **플러그인 저장소** — 매니페스트에 있는데 저장소에 없는 marketplace/플러그인만 add/install (#2344) |
| 5/6 | `claude/plugin/update-plugins.sh` | **플러그인 저장소** — marketplace clone 갱신 + 플러그인 version 갱신 |
| 6/6 | `scripts/setup-skills-ssot.sh` | Codex / agy / OpenCode / Hermes 합성 + 작업 폴더 루트 라우터 링크 |

4/6 은 3/6 뒤여야 한다 — 계정 `plugins` 링크가 맞춰지기 전에 `claude` 를 부르면 실제 폴더가
생긴다(그래서 `plugins` 경로가 없으면 CLI 를 부르지 않고 건너뛴다). 저장소는 계정 공유라
`--all-accounts` 없이 한 번만 돈다. 4/6 은 멱등이다: 저장소의 `known_marketplaces.json` /
`installed_plugins.json` **키** 와 비교해 누락분만 CLI 로 보내므로, 수렴된 PC 에서는 `claude`
호출 0회, 저장소 파일 변경 없음. 파일이 없으면 전 항목이 누락이고, 깨져 있으면 CLI 호출 없이
실패한다. 묘비(`removed.local.json`) 항목은 설치하지 않는다. add/install 실패는 계속 진행하되
집계해 비0 으로 끝나고, 다음 `skills-sync` 가 남은 항목만 재시도한다. `install` 은
`update-plugins.sh` 와 같은 `flock` 파일로 직렬화된다. `claude` 가 없는 PC 는 실패가 아니라
건너뜀이다(직접 실행한 `restore.sh` 는 여전히 오류).

4/6·5/6 이 실패해도 이후 단계는 진행하고, 마지막에 첫 비0 종료 코드로 끝난다. `--dry-run` 이면
1/6·2/6·4/6·5/6 을 미리보기로만 실행하고 3/6·6/6 은 건너뛴다. digest: 4/6 은
`신규 설치 N` (+ 설치가 있으면 세션 재시작 안내와 항목 목록), 5/6 은 복원 뒤에도 등록되지 않은
마켓플레이스를 `미등록 skip N` 으로 보인다(add 실패 또는 묘비).
출력은 기본 요약 모드(스텝당 1줄 + 변경 건수 digest, 경고/실패만 상세, 전체 로그는
`${TMPDIR:-/tmp}/skills-sync-*.log`, 경고/실패 시에만 경로 표시)이고, `-v` 또는 `SKILLS_SYNC_VERBOSE=1` 이면 전부 흘린다 (#2126).
요약 모드는 stdout 이 tty 가 아니므로 하위 스크립트의 대화형 확인(예: `claude/setup.sh` 의 stale sudoers 정리)이 뜨지 않는다 — 필요하면 `-v` 로 실행.

작업 폴더 루트 라우터: `scripts/setup-skills-ssot.sh` 가 `${WORKSPACE_ROOT}/AGENTS.md`,
`${WORKSPACE_ROOT}/CLAUDE.md` 를 `claude/workspace/AGENTS.md` 로 심볼릭 링크한다
(작업 폴더는 git repo 가 아니라 dotfiles 문서 체인이 세션에 들어오지 않기 때문). 일반
파일이 이미 있으면 덮어쓰지 않고 경고만 한다.

## 4. 진단: "Claude 에 스킬이 안 보인다"

1. **버전 비교** — 소스 `<workspace>/<repo>/.claude-plugin/plugin.json` 의 `version` 과
   `~/.claude-shared/plugins/installed_plugins.json` 의 `"<plugin>@<mkt>"` 항목 `version`
   (그리고 `gitCommitSha`) 를 비교한다.
2. **캐시 확인** — `ls ~/.claude-shared/plugins/cache/<mkt>/<plugin>/<version>/skills/` 에
   해당 스킬 디렉토리가 있는지 본다.
3. **설치·갱신** — `skills-sync` 한 번이 누락 설치(4/6)와 갱신(5/6)을 모두 한다. 미리보기는
   `skills-sync --dry-run` (4/6 의 `설치 예정 N`). 4/6 이 `신규 설치 0` 인데 플러그인이 없으면
   `installed_plugins.json` 에 키는 있는데 캐시 폴더가 사라진 손상이다 — 자동 복구 대상이 아니므로
   `claude plugin uninstall` 후 다시 `skills-sync`. 5/6 의 `미등록 skip N` 은 마켓플레이스 add 가
   실패했거나 묘비에 있다는 뜻이다(`skills-sync -v` 로 확인).
4. **세션 재시작** — 플러그인은 세션 시작 시 로드된다.

1에서 버전이 같은데 소스가 더 새롭다면 아래 §5 의 version bump 누락이다.

## 5. 버전 규칙 — 릴리스 시 version bump 필수

**규칙**: 스킬 repo 에서 Claude Code 사용자에게 반영돼야 하는 변경을 push 할 때는
`.claude-plugin/plugin.json` 과 `.claude-plugin/marketplace.json` 의 해당 플러그인
`version` 을 함께 올린다. version 이 같으면 `claude plugin update` 는 새 커밋을 가져오지
않는다.

**실험 (2026-10-13, Claude Code 2.1.296)** — 격리된 `CLAUDE_CONFIG_DIR` 과 로컬 git
마켓플레이스(`source: "./"`, plugin.json + marketplace.json 에 version, dEitY719 repo 와
같은 구조)로 관찰했다. 실제 repo 에 실험용 커밋을 push 하지 않으려는 대체 실험이다.

| 단계 | 커밋 | `claude plugin marketplace update` → `claude plugin update` 결과 |
|------|------|------------------------------------------------------------|
| 설치 | v1, version 0.1.0 | `cache/<mkt>/probe/0.1.0/` 생성, `gitCommitSha` = v1 |
| bump 없이 내용 변경 | v2, version 0.1.0 | `already at the latest version (0.1.0)` — 캐시 내용 v1 그대로, `gitCommitSha` 불변 |
| bump | v3, version 0.1.1 | `updated from 0.1.0 to 0.1.1` — `cache/<mkt>/probe/0.1.1/` 새로 생성, v3 내용 |

캐시 디렉토리와 갱신 판정이 모두 version 키라 bump 없는 커밋은 Claude Code 에 도달하지
않는다. 실제 사례(gh-flow 0.1.13 캐시 유지)도 같은 결과와 일치한다.
