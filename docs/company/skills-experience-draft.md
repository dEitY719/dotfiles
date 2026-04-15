# 배경: 동료가 스킬 사용해보고 경험 공유를 작성해달라고 요청

## 파일 이름이 skills-experience.md 은 적절한가? 영어 오타는 없는지 확인. 더 좋은 이름 추천하고 파일이 이름 변경해도 됩니다.

## 내가 작성하고 싶은 내용은 아래와 같습니다.

1. 내가 왜 스킬을 사용하게 된 이유는 `토큰을 절약하기 위해서` 입니다.
   앤트로픽의 기술 흐름이 MCP -> AGENT -> SKILL로 변화하는 기술 트렌드에 따라서 학습하게 되었음.
   내 경험상 skills 의 context가 제일 적게 소모하는 것을 눈으로 확인

아래 예제를 같은 기능을 수행하는 MCP, Agent 사용하는 것과 SKILL을 사용하는 토큰을 비교보여 주면 좋겠음.

```bash
❯ /context
  ⎿  Context Usage
     ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛀ ⛁ ⛁ ⛁   Opus 4.6
                           claude-opus-4-6
     ⛁ ⛁ ⛀ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁   38.8k/200k tokens (19%)

     ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   Estimated usage by category
                           ⛁ System prompt: 6.4k tokens (3.2%)
     ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ System tools: 7k tokens (3.5%)
                           ⛁ Custom agents: 9.5k tokens (4.7%)
     ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Memory files: 1.3k tokens (0.7%)
                           ⛁ Skills: 12.8k tokens (6.4%)
     ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Messages: 1.8k tokens (0.9%)
                           ⛶ Free space: 128.2k (64.1%)
     ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛝ Autocompact buffer: 33k tokens (16.5%)

     ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶

     ⛶ ⛶ ⛶ ⛝ ⛝ ⛝ ⛝ ⛝ ⛝ ⛝

     ⛝ ⛝ ⛝ ⛝ ⛝ ⛝ ⛝ ⛝ ⛝ ⛝
```

## 내가 자주 사용하는 스킬 예제

1. gh(github) 계열 스킬들
   내가 동료에게 이 스킬을 설명하는 이유는
   자연어로 명령을 해도 되지만, 반복해서 입력하기도 귀찮고 스킬로 만들어 두면 더 세부적으로 자세하게 일을 시킬수 있다는 점을 강조하고 싶음

1) gh:issue

```bash
# AI와 대화 후에 중요한 내용을 issue로 등록하고 싶을때
# 스킬 사용전,
지금 너와 대화한 내용을 요약해서 현재 repository의 issue로 등록해. label은 enhnacement 로 설정.

# 스킬 사용후,
/gh:issue
```

claude/skills/gh-issue/SKILL.md 내용을 이해하기 쉽게 핵심 3줄 이내로 요약

2. gh:commit

```bash
# AI와 구현/버그 수정 등의 작업을 완료 한 후에 커밋을 할때
# 스킬 사용전,
지금 너와 작업한 내용을 커밋으로 만들어.

# 스킬 사용후,
/gh:commit
```

claude/skills/gh-commit/SKILL.md 내용을 이해하기 쉽게 핵심 3줄 이내로 요약

3. gh:pr

```bash
# AI와 2~3개의 커밋 작업을 완료 한 후에 PR 작성 할때
# 스킬 사용전,
지금까지 작업한 커밋을 묶어서 PR 만들어. PR은 신규 브랜치에서 생성해.

# 스킬 사용후,
/gh:pr
```

claude/skills/gh-pr/SKILL.md 내용을 이해하기 쉽게 핵심 3줄 이내로 요약

4. gh:pr-reply

```bash
# PR 작성 후, 동료의 리뷰 코멘트가 달렸을때 점검
# 스킬 사용전,
동료가 PR#132에 리뷰를 달았어. 검토하고 타당하면 수용해. 리뷰 에티켓에 맞춰서 답글도 꼭 달아. 너는 답글 다는 것을 매번 놓치더라.

# 스킬 사용후,
/gh:pr-reply
```

claude/skills/gh-reply/SKILL.md 내용을 이해하기 쉽게 핵심 3줄 이내로 요약

2. visualize 스킬
   `요즘 내가 자주 사용하는 최애 스킬` 입니다.
   claude/skills/visualize/SKILL.md 내용을 이해하기 쉽게 핵심 3줄 이내로 요약

```bash
# usage
/visualize xxx-yyy.md
```

output examples: claude/skills/visualize/examples
