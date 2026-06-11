# harness-refactor.js — 워크플로우 파일 구조

Step 3 에서 생성할 파일의 필수 구조.

## 상수 정의 (필수)

```js
export const meta = {
  name: 'harness-refactor',
  description: 'Apply low-risk harness improvements identified in the latest audit',
  phases: [
    { title: 'Pre-flight',     detail: 'Verify target files exist, create archive directory' },
    { title: 'Apply Changes',  detail: 'Parallel agents modify non-overlapping file groups' },
    { title: 'Verify',         detail: 'Line count validation on all modified files' },
    { title: 'Final Report',   detail: 'Change summary, behavior delta, smoke-test prompts' },
  ],
}

const HOME    = (typeof process !== 'undefined' && process.env?.HOME) || '/home/deity719'
const ARCHIVE = `${HOME}/dotfiles/.claude/archive/harness-refactor-YYYY-MM-DD`
const SKILLS  = `${HOME}/dotfiles/claude/skills`
const ROOT    = `${HOME}/dotfiles`
```

날짜(`YYYY-MM-DD`)는 오늘 날짜로 고정한다.

## 설계 원칙

- 각 에이전트는 비중첩 파일 그룹 담당, `CHANGE_SCHEMA` 로 구조화된 결과 반환
- Pre-flight: 대상 파일 존재 여부 확인 + archive 디렉토리 생성 (파일 수정 없음)
- Apply Changes: `parallel()` 병렬 에이전트, 아카이브 후 수정
- Verify: `wc -l` 비교 + references/ 파일 생성 확인
- Final Report: 변경 목록·이유·behavior delta·smoke-test 5개·Human Approval Required 섹션
