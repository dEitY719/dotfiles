# Global Instructions

**Always write Korean (and other non-ASCII) strings in tool-call parameters as literal UTF-8; never as \uXXXX unicode escapes.**

## 모델 역할 분담: Advisor / Worker

메인 세션(Advisor)은 판단에 집중하고, 열린 구현 작업(open-ended implementation)은
opus 서브에이전트(Worker)에게 Agent 도구(model: "opus")로 위임한다.

**위임 대상** — 여러 파일에 걸친 수정, 새 기능/모듈 구현, 테스트 반복이 필요한 구현.
서로 독립적인 작업은 병렬로 위임한다.

**직접 처리** — 한두 파일의 소규모 수정, 설정/문서 변경 등 위임 오버헤드가 작업보다 큰 일.
skill이 메인 세션의 직접 실행을 명시한 단계(git/gh 명령 등)는 항상 직접 실행한다.

**브리프 기준** — Worker가 재탐색하지 않도록 이미 파악한 컨텍스트를 담는다: 파일 경로,
프로젝트 컨벤션, 알려진 함정, 완료 기준(통과해야 할 테스트). 브리프 1건 = 완료 기준
달성까지 — Worker는 테스트 작성→구현→통과 반복(TDD 루프 포함)을 브리프 안에서 자체 소화한다.

**검증** — Worker의 완료 보고를 그대로 믿지 않는다. Advisor가 diff 확인과 테스트 실행으로
직접 검증한 뒤 승인하고, 실패 시 수정 브리프로 재위임한다(직접 수정은 사소한 마무리만).

계획 문서 기반 다중 작업 실행 시에는 superpowers:subagent-driven-development가 이 원칙의
구체 절차다.

## 슬래시 명령 안내 규칙

사용자에게 `/명령`을 안내할 때는 SKILL.md description·README·스킬 출력에 적힌 이름
(`/gh-flow:issue` 같은 plugin 네임스페이스형)을 그대로 옮기지 않는다. 그 이름은 plugin 으로
설치됐을 때만 유효하다. 반드시 **현재 세션의 available skills 목록에 실제로 등록된 이름**을
쓴다 — 목록에 `gh-flow:issue` 가 있으면 `/gh-flow:issue`, `issue` 만 있으면 `/issue`
(`~/.claude*/skills/` 의 평면 심볼릭 링크는 네임스페이스가 붙지 않는다). 둘 다 없으면 없다고
말한다. 목록 이름과 문서 이름이 다르면 그 불일치(plugin 미설치 drift)도 함께 알린다.

## 무인 세션 rm 규칙

yolo 무인 세션에서 `rm` 이 `sh -c`/`xargs ... sh -c`/`eval`/`$(...)` 안에 들어 있으면 하네스가
`could not be checked` 프롬프트를 띄우고, 응답이 없으면 자동 거부돼 작업이 끊긴다.

- `rm`/`rmdir` 은 복합 쉘 안에 넣지 말고 **독립된 단순 명령 한 줄**로 분리한다 (`rm -rf "$C"`).
- 임시 파일·디렉토리는 scratchpad(`/tmp/claude-<uid>/...`) 안에서만 만들고 지운다. 대상은 리터럴
  경로이거나 같은 명령에서 `mktemp -d /tmp/claude-<uid>/...` 로 대입한 변수여야 한다.
- `$sh -c "..."`·`env -i ... zsh -c "..."` 처럼 스크립트가 불투명한 `-c` 도 같은 프롬프트를 띄운다 — 임시 스크립트 파일로 쓰고 `bash file.sh` 로 실행한다.
- 대상이 불확실하면(`$HOME`, `~`, `..`, 미할당 변수) 지우지 말고 사용자 결정 사항으로 남긴다.
