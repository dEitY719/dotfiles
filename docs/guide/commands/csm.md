# csm (claude-skills-marketplace)

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/marketplace.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic claude_skills_marketplace --force`

## 호출

- Help 진입점: `claude-skills-marketplace-help [section|--list|--all]`
- 통합 라우팅: `my-help claude_skills_marketplace [section]`
- Alias: `claude-skills-marketplace`, `claude-skills-marketplace-help`, `csm`

## 요약 (claude-skills-marketplace-help)

- Usage: claude-skills-marketplace-help [section|--list|--all]
- sections
    - quickstart: csm | csm list --all | csm search | csm info
    - commands: list | group | stats | search (find) | info | refresh | help
    - aliases: claude_skills_marketplace | csm
    - examples: common usage examples
    - caching: manifest cache details
    - details: claude-skills-marketplace-help <section>

## 섹션

### quickstart

- Group by plugin (default): csm
- All skills by marketplace: csm list --all
- Search skills: csm search python
- Get details: csm info api-design-principles

### commands

1. list [--all|-A]         - Group by plugin (default), or --all for marketplace view
2. group [plugin]          - Group skills by plugin (optionally filter)
3. stats                   - Show marketplace statistics
4. search|find [keyword]   - fzf fuzzy picker (needs fzf+TTY), else keyword search
5. info <skill-name>       - Show detailed skill information
6. refresh                 - Force rebuild skill manifest
7. help                    - Show this help message

### aliases

- Long form: claude_skills_marketplace
- Short form: csm
- Subcommand: csm find = csm search

### examples

- Show plugins: csm (shows plugin headers)
- Same as above: csm list
- Show marketplaces: csm list --all
- Explore plugin: csm search backend (or filter: csm group backend)
- Search skills: csm search python
- Fuzzy pick: csm find (fzf picker over all skills)
- Skill details: csm info api-design-principles
- Statistics: csm stats

### caching

- Manifest cache: ~/.claude/plugins/marketplaces/.skills-manifest.json
- Cache TTL: 24 hours
- Auto-refresh: When cache expires or manifest missing

## 엣지케이스 / 의도된 동작

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

## 소스

- `shell-common/functions/marketplace.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
