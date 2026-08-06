`csm` (`claude_skills_marketplace`) 의 소스 주석에만 있던 동작들. 출처는
`shell-common/functions/marketplace.sh` 의 `_claude_skills_marketplace_search()`.

- `csm find` 는 `csm search` 의 별칭이고, 둘 다 **fzf 피커** 로 동작한다.
  단 `fzf` 가 설치돼 있고 stdin/stdout 이 **모두 TTY** 일 때만 피커가 뜬다.
- 피커에서 **Esc 를 누르면 아무것도 선택하지 않은 것으로 보고 조용히 종료한다**
  (exit 0 — 에러가 아니다). 화면에 아무것도 안 남아서 실패처럼 보이지만 의도된
  동작이다. 매칭 결과가 없거나 fzf 가 다른 이유로 끝날 때도 같다.
- 피커 모드에서 넘긴 `<keyword>` 는 결과를 걸러내는 필터가 아니라 fzf 의
  **초기 query 프리필** 이다 — 입력을 지우면 전체 스킬 목록이 다시 보인다.
- 비대화형(파이프 · 스크립트 · 테스트 하네스)이거나 `fzf` 가 없으면 jq substring
  검색으로 폴백한다. 이 경로에서는 `<keyword>` 가 **필수** — 없으면
  `Query required` 에러와 함께 exit 1.
- 매니페스트 파싱 실패는 "사용자가 취소함" 으로 삼키지 않고
  `Failed to parse marketplace manifest` 에러로 드러난다. `jq` 실패와 `fzf` 취소를
  일부러 분리해 둔 것이다.
- 인자 없이 `csm` 만 치면 **help 가 출력된다** (라우터 기본값이 `help`).
  `csm help` 의 quickstart 절은 "Group by plugin (default): csm" 이라고 안내하지만,
  실제 플러그인 목록은 `csm list` 로 봐야 한다.
- 매니페스트 캐시는 24 시간 TTL. 만료되거나 파일이 없으면 자동 재생성되고,
  강제 재생성은 `csm refresh`.
