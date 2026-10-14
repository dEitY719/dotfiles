# scripts/

저장소 유지보수·CI/lint·setup 체인 전용 **비대화형** 스크립트를 둔다 (#2142).

## 경계 — 어디에 두나

| 위치 | 용도 | 누가 실행하나 |
|------|------|---------------|
| `scripts/` | 저장소 유지보수, CI/lint 게이트, root `setup.sh` 체인의 보조 스텝 | `mise` 태스크, CI, `setup.sh`, git hook — 일상적으로 셸에서 부르는 도구가 아니다(1회성 이관·유지보수 스크립트는 사람이 수동 실행) |
| `shell-common/tools/custom/` | 사용자가 셸에서 직접 실행하는 도구 (자동 source 안 됨) | 사람 |
| `<module>/setup.sh` | 그 모듈 하나를 이 PC 에 수렴(링크·시드·확인) — 멱등 | root `setup.sh main()` (`scripts/lint_setup_steps.sh` 가 등록 여부 검사) |
| `scripts/maintenance/` | 1회성/주기적 분석·정리 도구 | 사람 (수동) |

새 스크립트가 사용자 대면 명령이면 `tools/custom/`, 한 모듈의 설치·링크면
`<module>/setup.sh`, 그 외 비대화형 저장소 작업이면 여기에 둔다.

## 현재 분류

- **lint/CI 게이트**: `lint_docs_filenames.sh`, `lint_agents_md_lines.sh`,
  `lint_docs_status.sh`, `lint_setup_steps.sh` (`mise run lint-docs`),
  `lint_changelog_fragments.sh`(중단), `lint_shell_common_fallback.sh`(수동),
  `check_port_registry.sh`, `test_smoke.sh` (`mise run test-smoke`)
- **setup 체인 스텝**: `disable-git-crypt-local.sh`, `setup-skills-ssot.sh`,
  `verify-config-files.sh` (root `setup.sh main()`)
- **internal PC 1회 이관** (dry-run 후 `--apply`, `docs/.ssot/pc-environment.md`):
  `internal-config-migrate.sh`, `internal-ssh-git-migrate.sh`
- **skills 유지보수**: `update-skills.sh`, `sync-gemini-skills-namespace.sh`,
  `measure-skill-descriptions.sh`
- **진단**: `debug_pip_config.sh`

## 이동 후보 (후속 — 이 문서는 기록만 한다)

호출부를 함께 바꿔야 해서 별도 PR 로 다룬다.

- `debug_pip_config.sh` → `shell-common/tools/custom/` (사용자가 직접 실행하는 진단 도구)
- `internal-*-migrate.sh` → `shell-common/setup.d/`
- `setup-skills-ssot.sh` + `sync-gemini-skills-namespace.sh` → `skills/setup.sh` 로 승격
  — 호출부 `setup.sh` main() 의 `skills-ssot` 스텝과 `scripts/update-skills.sh` 5단계를
  동시에 바꿔야 한다.
