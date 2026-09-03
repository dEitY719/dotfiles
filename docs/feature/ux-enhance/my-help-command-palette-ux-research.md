---
status: draft
---

# my-help 명령 팔레트 UX 조사 및 제안

## 결론

`my-help`는 별도 풀스크린 TUI를 새로 만들기보다, 현재 가진 `fzf` 검색 기반을
**Claude Code식 slash command palette**로 확장하는 편이 적합하다. 기본 진입점은
`my-help`로 유지하되, TTY와 `fzf`가 있을 때는 검색·선택·미리보기 3요소를 갖춘
명령 팔레트를 연다. 의존성이 없거나 비대화형일 때는 현행 7줄 요약으로 안전하게
폴백한다.

이는 LazyGit의 "현재 선택 대상 + 즉시 보이는 키 힌트"는 취하고, 작은 명령어
레지스트리에 과한 다중 패널·상태 관리를 들이지 않는 선택이다.

## 현재 상태

`shell-common/functions/my_help.sh`는 이미 다음 기반을 제공한다.

- bash/zsh 공통 topic/category registry와 topic 상세 라우팅
- `my-help search` 및 `find`의 `fzf` fuzzy finder
- 저장소 alias 전체를 스캔한 TSV 인덱스와 24시간 캐시
- fzf 미설치 또는 non-TTY에서 카테고리 표로 폴백
- 기본 `my-help`의 7줄 compact summary

현재 검색 후보는 topic과 alias다. 임의 shell function은 등록된 `*_help` 토픽만
찾을 수 있으므로, 사용자가 말한 "나의 함수, alias 등"을 완성하려면 function도
명시적인 후보 종류로 추가해야 한다.

### 워크트리 교차 검토에서 확인한 사실

동료가 작성한 `dotfiles-feat-1`의 `my-help-tui-ux.md`와
`dotfiles-feat-agy-1`의 `my-help-ux-modernization.md`를 원문으로 검토했다. 두
문서의 스냅샷 수치(82 topics, 468 aliases)는 해당 checkout 시점의 값이므로 고정
계약으로 삼지 않는다. 이 checkout에서 다시 확인한 값은 다음과 같다.

| 항목 | 2026-09-03 현재 checkout 관찰 | 설계에 미치는 영향 |
|---|---:|---|
| `my_help.sh` | 1,230 lines | 이미 큰 cross-shell 파일이므로 작은 helper로 증분 변경한다. |
| source alias 정의 | 475 lines | 후보가 많으므로 kind filter와 preview가 필요하다. |
| fzf | 0.44.1 (Debian) | 0.45+의 `transform` action을 요구하지 않는다. |
| Node.js | v26.7.0 | Node 런타임은 있지만 shell help의 MVP 의존성으로 채택하지 않는다. |
| `packages/my-cli` | 2026-02-20 이후 변경 없음, `dist/` 없음 | 현재 엔트리포인트와 연결되지 않은 실험 코드로 취급한다. |

`packages/my-cli`에는 `App.tsx`뿐 아니라 CLI command와 tests에도
`/home/bwyoon/dotfiles/.../my_help.sh` 절대경로가 남아 있다. 따라서 이를 TUI의
기반으로 되살리는 작업은 단순 UX 변경이 아니라 별도 부채 정리 작업이다.

## 조사 결과

| 사례 | 확인한 UX 원칙 | my-help에 적용 |
|---|---|---|
| [Lazygit keybindings](https://github.com/jesseduffield/lazygit/blob/master/docs/keybindings/Keybindings_en.md) | `j/k`·화살표로 목록을 이동하고 `/`로 현재 목록을 필터링하며 `Enter`로 실행한다. `Esc`는 취소/닫기다. | fzf의 기본 이동/필터/취소 동작을 유지하고, 하단에 짧은 키 힌트를 보인다. |
| [Claude Code interactive mode](https://code.claude.com/docs/en/interactive-mode) | `/`를 입력하면 command/skill 목록이 열리고, 뒤의 문자열로 필터링한다. 목록은 built-in·사용자 정의·plugin/MCP 항목을 한곳에 모은다. | slash를 palette 내부의 검색 언어로 채택한다. 예: `/alias`, `/function`, `/git`, `/all`. |
| [fzf Getting Started](https://junegunn.github.io/fzf/getting-started/) | 표준입력 목록을 실시간 fuzzy filtering하고, preview와 key binding으로 작은 interactive app을 조합할 수 있다. full-screen뿐 아니라 높이를 제한한 표시도 지원한다. | 후보 registry를 TSV로 내보내고, preview 창에서 선택한 항목의 설명/정의/실행 예시를 보여준다. |
| [fzf shell integration](https://junegunn.github.io/fzf/shell-integration/) | fzf는 bash/zsh shell integration과 `Ctrl-R` history 탐색을 기본 제공한다. | Bash/Zsh 호환성은 유지하고, shell line editor의 `/` 키를 가로채지 않는다. |
| [Charm Gum](https://github.com/charmbracelet/gum) | shell script용 chooser/filter/pager/table을 제공하지만 별도 실행 파일 의존성이 생긴다. | MVP 의존성으로 추가하지 않는다. 이후 더 풍부한 wizard가 필요할 때만 선택지로 검토한다. |

### 참고 UX의 수용/비수용 판단

- LazyGit: pane focus, persistent keymap, confirmation UX는 복잡한 상태 변경 작업에
  뛰어나다. 그러나 help 탐색은 읽기 전용이고 짧으므로 다중 pane TUI는 과하다.
  대신 `Esc` 취소, `Enter` 열기, 눈에 보이는 키 힌트, 선택 미리보기만 수용한다.
- Claude Code: command discovery의 핵심인 "`/` 입력 후 즉시 필터"가 정확히 목표와
  맞는다. 다만 일반 zsh/bash 프롬프트의 `/`는 path 입력의 정상 문자다. 따라서
  프롬프트에서 `/` 자체를 전역 단축키로 만들지 않고, `my-help`가 연 palette 안에서
  slash를 사용한다.
- fzf: 이미 설치 시 사용하도록 설계돼 있고 bash/zsh를 지원하므로 가장 작은 변화다.
  `my-help search`의 기존 동작도 자연스럽게 확장할 수 있다.

### 동료 제안의 통합 결정

| 제안 | 결정 | 근거 |
|---|---|---|
| 헤더에 현재 scope와 결과 수 표시 | 수용 | 후보가 수백 개인 경우 현재 탐색 범위를 즉시 알 수 있다. |
| `?`의 컨텍스트 key help | 수용 | LazyGit식 발견성을 얻되, 별도 panel은 만들지 않는다. |
| preview를 별도 subprocess로 렌더 | 수용 | fzf preview가 부모 interactive shell의 함수를 상속하지 않는 문제를 피한다. |
| fzf `reload`/`change-prompt` 중심 구현 | 수용 | 로컬 fzf 0.44.1와 호환된다. `transform`은 MVP에서 금지한다. |
| public function source index와 alias와 같은 24h 원자적 cache | 조건부 수용 | Phase 2에서 public 규칙과 중복 제거를 고정한 뒤 추가한다. |
| `Tab` shell-buffer 주입, `Ctrl-Y` clipboard, `Ctrl-O` editor | 후속 opt-in | 기본 "보기만 하는 help" 안전성 및 Bash/Zsh 이식성을 깨므로 MVP에 넣지 않는다. |
| Ink/React `packages/my-cli` 부활 | 보류 | 절대경로와 build/연결 부채를 먼저 별도 해결해야 하며, 현재 UI 문제에는 fzf가 충분하다. |

## 권장 사용자 경험

### 진입 규칙

| 입력 | TTY + fzf | 비대화형 또는 fzf 없음 |
|---|---|---|
| `my-help` | 명령 팔레트 열기 | 현행 compact summary 출력 |
| `my-help search` / `my-help find` | 명령 팔레트 열기 | 카테고리 표 출력 (현행 유지) |
| `my-help <topic>` | 해당 topic 도움말 | 동일 |
| `my-help --list` / `--all` | 현행 섹션/전체 출력 | 동일 |

`my-help`의 무인 실행 결과를 바꾸지 않으므로 pipe, test, 문서 생성과 원격 shell에서
예측 가능한 텍스트 출력을 보존한다.

### 팔레트 화면 스케치

```text
 my-help  Type a command, alias, or /kind filter
 > /alias docker

   alias     docker-clean       remove stopped containers
 > alias     docker-logs        shell-common/aliases/docker.sh:18
   topic     docker             Docker commands and aliases

 ─ Preview ────────────────────────────────────────────────────
 Alias: docker-logs
 definition: docker compose logs -f
 source: shell-common/aliases/docker.sh:18

 Enter details  ? help  Esc cancel  /alias /function /topic /category /all
```

- 첫 입력 상태: 모든 후보를 relevance/고정 순서로 표시한다. 고정 항목은 `git`,
  `docker`, `claude`, `uv`, `fzf`와 최근 선택 항목(선택 구현)이다.
- 일반 텍스트: 이름·설명·태그를 fuzzy match한다.
- `/` 필터: `/alias`, `/function`, `/topic`, `/category`, `/all` 가운데 하나를
  입력해 후보 종류를 좁힌다. `/` 뒤에 공백과 검색어를 붙일 수 있다.
- `Enter`: topic/category는 기존 `my_help_impl`으로 연다. alias/function은
  **실행하지 않고** 정의·위치·설명만 출력한다.
- `Esc`/빈 선택: 출력 없이 성공 종료한다.
- header는 활성 scope와 해당 후보 수를 표시한다. count는 cache가 없거나 스캔에
  실패했을 때도 표시 실패가 palette 전체 실패가 되지 않도록 best-effort로 계산한다.

### 후보 데이터 계약

기존 5열 TSV를 크게 흔들지 않고, 표준 후보를 다음 필드로 정규화한다.

```text
name<TAB>description<TAB>kind<TAB>location<TAB>detail
```

| kind | name | description | location/detail | 선택 결과 |
|---|---|---|---|---|
| `topic` | `git` | topic 설명 | 빈 값 | `my-help git` |
| `category` | `development` | category 설명 | member 수 | `my-help development` |
| `alias` | `gco` | trailing comment 또는 위치 | 정의 파일/정의문 | 정의 보기 |
| `function` | `gwt` | 등록 설명 또는 첫 주석 | 정의 파일/시그니처 | 정의 보기 |

Function 후보는 runtime `declare -F`/`whence`만으로 수집하지 않는다. 셸과 로딩 순서에
따라 목록이 달라지고, private helper까지 노출하기 쉽기 때문이다. 우선 `my-help`
registry의 public topic과 함수가 실제 공개 명령임을 나타내는 등록 정보를 합친다.
이후 전체 public function 탐색이 필요해질 때만, source 위치·공개 규칙·설명을 갖춘
별도 indexer를 도입한다.

## 구현 경계와 단계

### 1단계: fzf 팔레트화

- `_my_help_search_candidates()`에 `category` 후보를 추가하고, alias/topic record
  형식은 유지한다.
- `_my_help_search()`의 fzf 옵션에 `--height`, `--layout=reverse`, delimiter,
  prompt, header, preview, `Esc`/`Enter` 동작을 추가한다. `?`에는 현재 scope에서
  유효한 키와 slash 문법을 설명하는 정적 help를 연결한다.
- 입력을 해석해 `/kind [query]`를 candidate filter로 바꾸되, plain fuzzy query는
  fzf에 전달한다.
- 기본 인자 없음이 interactive TTY에서는 `_my_help_search`로 진입하도록 바꾼다.
- preview renderer는 alias 정의와 topic/category 요약만 만들며 부작용이 없어야 한다.
- 구현은 fzf 0.44.1에서 동작하는 `reload`, `change-prompt`, `toggle-preview`만
  사용한다. 0.45 이상에만 있는 `transform` action은 사용하지 않는다.

fzf preview는 별도 subprocess이므로 현재 shell에서 source된 helper를 직접 호출할 수
없다. preview에는 TSV row를 shell command string에 보간하지 않고, private renderer에
표준입력 또는 안전한 임시 파일로 전달한다. `--preview-entry` 같은 내부 CLI entrypoint는
Bash/Zsh 양쪽에서 source·인자 전달 테스트가 준비된 경우에만 도입한다.

### 2단계: 명시적 function registry

- `HELP_DESCRIPTIONS`와 별개로 public command 이름, kind, 설명, source를 등록하는
  작은 registry를 둔다.
- alias가 아닌 public function을 `function` 후보로 보이고, 기존 help topic과
  중복되면 한 후보에 `topic` 태그를 우선한다.
- source parsing 및 cache 정책은 existing alias index의 실패-안전 패턴(빈 결과는
  topic-only로 폴백)을 재사용한다.

### 3단계: 선택 기능

- 최근 선택 목록은 `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/` 아래에
  저장하고, 쓰기 실패 시 무시한다.
- `Ctrl-/` 또는 `?`로 팔레트 키 도움말을 토글한다. 핵심 탐색에는 추가 keybinding을
  요구하지 않는다.
- 사용량 측정이나 자동 실행은 범위 밖이다.
- shell buffer 주입, clipboard 복사, `$EDITOR` 열기는 기본 동작으로 추가하지 않는다.
  필요성이 확인되면 각각 명시적 opt-in keybinding과 Bash/Zsh별 회귀 테스트를 갖춘
  별도 phase로 설계한다.

### 4단계: 고아 my-cli의 결정

팔레트 MVP와 분리해 `packages/my-cli`의 유지 여부를 결정한다.

- 보존: 모든 절대경로를 `DOTFILES_ROOT` 또는 실행 위치 기반으로 바꾸고, 빌드·설치
  경로와 "experimental, not wired to my-help" 상태를 README에 명시한다.
- 폐기: 구현 코드 삭제 여부는 별도 승인 후 결정하고, 설계/배경 문서는 `docs/archive/`
  로 옮겨 추적성을 남긴다.

이 결정을 내리기 전에는 `my-help`가 Node/Ink를 호출하지 않는다.

## 수용 기준

- Bash와 Zsh에서 TTY + fzf일 때 `my-help`가 palette를 열고, `Esc`가 exit 0으로
  닫힌다.
- fzf가 없거나 stdin/stdout이 TTY가 아닐 때 `my-help` 기본 출력은 현재의 compact
  summary를 유지한다.
- `/alias`, `/topic`, `/category`, `/all`은 각각 해당 종류만 표시한다.
- 선택한 alias/function은 절대 실행되지 않으며 정의·source만 표시한다.
- 선택한 topic/category는 기존 `my_help_impl` 경로로 열려 기존 인자 라우팅을 보존한다.
- alias index cache 손상/미존재와 source tree 부재는 오류 없이 topic/category 후보로
  폴백한다.
- 기존 `my-help search`/`find`, `my-help <topic> [args]`, `--list`, `--all`의
  Bash/Zsh 테스트를 유지하고 palette의 필터·선택·폴백 테스트를 추가한다.

## 결정이 필요한 사항

1. 기본 `my-help`를 interactive palette로 전환할지: 본 문서는 **전환**을 권장한다.
   현재의 텍스트 요약은 non-TTY 폴백으로 보존된다.
2. function 탐색 범위: 1단계에서는 registry 기반 public command만, 2단계에서만
   전체 public function으로 넓히는 것을 권장한다.
3. `fzf`를 필수 의존성으로 만들지: 본 문서는 **선택 의존성** 유지를 권장한다.
   WSL/minimal 환경과 CI가 바로 동작한다.

## 구현 시 주의점

- `my_help.sh`는 POSIX 형태로 source되지만 bash/zsh 양쪽에서 실행된다. bash 전용
  배열 문법이나 zsh 전용 parameter expansion은 이미 사용 중인 `eval`/helper 경계를
  지켜야 한다.
- 프롬프트 ZLE 위젯으로 `/`를 재정의하지 않는다. 경로 입력과 충돌하며 Bash/Zsh의
  구현도 달라진다.
- fzf preview command에는 후보 값을 shell interpolation으로 직접 넣지 않는다.
  TSV 레코드를 안전한 함수/임시 파일 경로로 넘기고, `--`와 quoting을 적용한다.
- fzf action의 지원 범위는 설치된 최소 지원 버전에서 확인한다. 특히 `transform`에
  의존하는 slash-query 재작성은 fzf 0.44.1에서 사용할 수 없다.
- palette는 읽기 전용 도움말 UI다. alias와 function을 선택한 것만으로 command를
  실행하거나 shell buffer를 변경하지 않는다.

## 다음 작업

승인되면 별도 구현 설계에서 fzf 후보 필터 문법, preview 전달 방식, cache 무효화와
Bash/Zsh Bats 테스트 케이스를 확정한다.
