# Issue Body Templates — for gh:issue skill

Title format and body structures for the three issue categories (feature / bug / misc). Select the template matching the category chosen in Step 2.

## Title format
- feature: `[Feature] <구체적인 한 줄 요약>`
- bug: `[Bug] <증상 한 줄 요약>`
- misc: `[Misc] <주제 한 줄 요약>`

## Body structure (feature)
```markdown
## Context
<왜 이 기능이 필요한가 — 사용자가 말한 배경/동기>

## Proposal
<무엇을 만들 것인가 — 요구사항 목록>

## Discussion Log
<대화에서 오간 의사결정, 대안 검토, 네이밍 논의 등 원문에 가깝게>

## Open Questions
<아직 결정 안 된 것, 확인 필요한 것>

## References
- 관련 파일: `path/to/file.ext`
- 관련 이슈/PR: (있으면)
```

## Body structure (bug)
```markdown
## Symptom
<에러 메시지, 실패 증상>

## Reproduction
<재현 절차 — 대화에서 나온 명령, 환경>

## Root Cause Analysis
<원인 추적 과정과 결론>

## Fix Plan
<수정 방향 — 아직 수정 안 했으면 계획만>

## Logs / Evidence
<로그 발췌, 파일 위치 등>
```

## Body structure (misc)
```markdown
## Topic
<대화 주제>

## Summary
<논의된 내용 정리>

## Decisions
<도출된 결론>

## Notes
<추가 맥락>
```
