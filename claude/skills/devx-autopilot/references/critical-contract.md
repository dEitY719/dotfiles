# CRITICAL CONTRACT — early-stop 방지

`gh:issue-flow` 와 동일 계열의 실패 모드: 체이닝 중간 단계 후 조용히 정지.

## 가드 (제거 금지)
1. 체이닝된 `Skill()` 호출(Step 0a·0b·2·3·4·5) 사이 **대화 텍스트 0** — recap·헤더·진행 bullet 금지.
   각 호출 성공 직후 바로 다음 호출.
2. 각 원자 스킬 호출에 조기 종료를 유발하는 힌트 억제(예: 하위 스킬의 `Next:` 힌트가 흐름을
   끊지 않도록 `--no-next-hint` 계열 옵션이 있으면 사용).
3. 하네스 Stop-hook 가드 `claude/hooks/devx_autopilot_stop_guard.py` — 순서화된 단계 완료 마커
   (`[step:devx-autopilot/<id>] OK`)가 없으면 정지를 막고 남은 단계 계속 지시.

## 백스톱은 면허가 아니다
가드는 안전망이지 "중간에 멈춰도 된다"는 허가가 아니다. 정상 경로는 Step 0→6 을 한 턴 흐름으로
완주하는 것이다. 하드 실패만 [FAIL] 정지 사유다.
