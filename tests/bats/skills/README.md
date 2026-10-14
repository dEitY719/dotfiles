# tests/bats/skills/ — 이전 보류 (held copy-only skill mirrors)

이 디렉토리의 bats 는 모두 **marketplace repo 로 떠난 skill(#1680) 의 단계를 손 복사본
fixture(`_fixtures/*.sh`)로 재현해 검사**한다. 정본이 바뀌어도 복사본만 보므로 계속 통과한다.
정본 repo 로 옮기는 것이 정답이지만, 대상 repo 에 bats CI 가 없어 **이전 보류** 상태다
(#2153 결정: 대상 repo CI 확인 전 삭제 금지). 이전 추적: #2200.

새 테스트를 여기 추가하지 않는다 — `tests/AGENTS.md` "No copy-fixture tests" 규칙.
이 저장소의 코드를 검사하는 테스트는 `functions/`(shell-common/functions), `claude_hooks/`
(claude/hooks), `git/` 등 대상 코드 위치에 둔다.

## 이전 보류 목록 (2026-10-14 기준, 대상 repo 모두 bats CI 없음)

| 파일 | @test | 정본 skill | 대상 repo |
|---|---:|---|---|
| claude_plugin_structure.bats | 79 | packaging:structure-check / structure-refactor | dEitY719/packaging-skills |
| gh_add_ai_metrics_date.bats | 27 | gh-setup:add-ai-metrics | dEitY719/gh-setup-skills |
| gh_add_ai_metrics_pace.bats | 31 | gh-setup:add-ai-metrics | dEitY719/gh-setup-skills |
| gh_disable_ai_metrics.bats | 7 | gh-*:* ai-metrics env guard | dEitY719/gh-setup-skills |
| gh_issue_create_auto_labels.bats | 9 | gh-issue:issue-create | dEitY719/gh-issue-skills |
| gh_issue_create_dependency_detect.bats | 29 | gh-issue:issue-create | dEitY719/gh-issue-skills |
| gh_issue_create_open_questions_gate.bats | 38 | gh-issue:issue-create | dEitY719/gh-issue-skills |
| gh_issue_implement_claim.bats | 20 | gh-issue:implement | dEitY719/gh-issue-skills |
| gh_issue_proceed_safety.bats | 23 | gh-issue:proceed | dEitY719/gh-issue-skills |
| gh_issue_proceed_schema.bats | 5 | gh-issue:proceed | dEitY719/gh-issue-skills |
| gh_pr_approve_board_sync.bats | 6 | gh-pr:approve | dEitY719/gh-pr-skills |
| gh_pr_merge_herdr_notify.bats | 23 | gh-pr:merge | dEitY719/gh-pr-skills |
| gh_pr_merge_review_passed_cleanup.bats | 10 | gh-pr:merge | dEitY719/gh-pr-skills |
| gh_pr_merge_train_approval_gate.bats | 36 | gh-pr:merge-train | dEitY719/gh-pr-skills |
| gh_pr_merge_train_close_impl_tab.bats | 29 | gh-pr:merge-train | dEitY719/gh-pr-skills |
| gh_pr_push_policy.bats | 52 | gh-pr:create | dEitY719/gh-pr-skills |
| gh_pr_reply_board_sync.bats | 6 | gh-pr:reply | dEitY719/gh-pr-skills |
| gh_pr_stacked_detect.bats | 31 | gh-pr:create | dEitY719/gh-pr-skills |
| helper_fallback_nf1.bats | 4 | gh-pr:* helper-source guard | dEitY719/gh-pr-skills |
| gh_pr_post_merge_verify.bats | 98 | gh-verify:post-merge-verify | dEitY719/gh-verify-skills |
| gh_pr_resolve_ci_fail_review_passed.bats | 8 | gh-resolve:ci-fail | dEitY719/gh-resolve-skills |
| gh_pr_resolve_conflict_review_passed.bats | 7 | gh-resolve:conflict | dEitY719/gh-resolve-skills |
| gh_pr_resolve_outdated_review_passed.bats | 31 | gh-resolve:outdated | dEitY719/gh-resolve-skills |
| skill_check_description_length.bats | 13 | authoring:skill-check | dEitY719/authoring-skills |

`_fixtures/skill_description_length.sh` 는 `scripts/measure-skill-descriptions.sh` 도
재사용한다 — 이전 시 그 스크립트의 경로도 함께 고친다.
