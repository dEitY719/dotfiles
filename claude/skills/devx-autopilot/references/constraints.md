# Constraints

- 단계는 이전 단계 성공 시에만 진행. 실패 시 재시도·스킵 금지 — 정지+리포트.
- **머지 금지**(사람 몫), 디폴트 브랜치 push 금지, `--force`/`--force-with-lease` 금지,
  `--no-verify` 금지, 테스트/typecheck/lint 실패 상태로 PR 금지.
- spec 자동 감지 실패 시 추측 금지 — `[spec-path]` 요청 후 정지.
- 원자 스킬을 재구현하지 않는다 — writing-plans/gh:issue-create/subagent-driven-development/
  gh:pr/simplify/gh-pr-reply 를 그대로 호출.
- 호스트는 gh_host.sh 로만 해석(하드코딩 금지).
- 체이닝된 Skill 호출 사이 대화 텍스트 0(early-stop 방지, critical-contract 참조).
- Advisor 검증은 worker 완료 보고를 그대로 믿지 않고 diff·테스트로 직접 확인(global CLAUDE.md).
- 이 스킬은 사용자 트리거 전용 — 다른 스킬 내부에서 호출 금지(gh:issue-flow 와 동급 최상위).
