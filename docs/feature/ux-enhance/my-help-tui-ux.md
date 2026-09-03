# my-help 명령어 탐색 UX 개선 조사

- 작성일: 2026-09-03
- 상태: 조사 / 설계 제안 (구현 전)
- 대상: `shell-common/functions/my_help.sh`, `packages/my-cli/`
- 요청 배경: "my-help 을 lazygit 또는 Claude Code TUI 같은 형태로 만들고, `/` 로 내 함수·alias 를 조회하고 싶다"
- 교차 검토: 같은 디렉터리의 동료 문서 2종을 원문 검토하고 수용 판단을 §4 에 기록했다.
  - `docs/feature/ux-enhance/my-help-ux-modernization.md`
  - `docs/feature/ux-enhance/my-help-command-palette-ux-research.md`

---

## 1. 현황 (as-is)

이 절의 수치는 2026-09-03 이 checkout 에서의 실측값이다. 코드가 움직이면 같이 움직이므로 고정 계약으로 삼지 않는다.

| 항목 | 값 | 근거 |
|---|---|---|
| `my_help.sh` 크기 | 1,230줄 | `wc -l shell-common/functions/my_help.sh` |
| 등록된 help 토픽 | 82개 | `HELP_DESCRIPTIONS[...]` 등록 수 |
| 저장소 내 alias 정의 | 475개 | `grep -rhE '^alias [^ =]+=' bash zsh shell-common --include='*.sh' --include='*.bash' --include='*.zsh'` |
| 설치된 fzf | 0.44.1 (debian) | `fzf --version` |
| Node.js | v26.7.0 | `node --version` |
| `packages/my-cli` 최종 커밋 | 2026-02-20 (`0e87a6d3`) | `git log -1 -- packages/my-cli` |
| `packages/my-cli` 빌드 산출물 | 없음 (`dist/` 부재) | `ls packages/my-cli/packages/cli/dist` |

> alias 개수는 세는 방법에 따라 달라진다. `--include` 없이 세면 482개다. 위 475는 **인덱서가 실제로 쓰는 것과 동일한 필터**로 센 값이므로 이 수치를 기준으로 쓴다.

### 1.1 이미 있는 것

`my-help` 은 생각보다 많은 것을 이미 갖고 있다. 새 UX 를 "처음부터" 만들 필요는 없다.

- **카테고리 → 토픽 2단 구조**: `HELP_CATEGORIES`, `HELP_CATEGORY_MEMBERS`, `HELP_COMMAND_TO_CATEGORY` 세 개의 연관 배열이 SSOT.
- **fzf 퍼지 검색이 이미 존재**: `my-help search` / `find` → `_my_help_search`. TTY 가 없거나 fzf 가 없으면 정적 카테고리 표로 자동 강등(degrade)된다.
- **alias 인덱스가 이미 존재**: `_my_help_build_alias_index` 가 저장소 전체를 스캔해 5필드 TSV 로 캐싱한다 (`~/.cache/dotfiles/my-help-alias-index.tsv`, TTL 24h). 필드는 `name / desc / kind / location / definition` 이고, fzf 에는 `--with-nth=1,2` 로 앞 두 필드만 노출한다.
- **동명이의 alias 보존 정책**: 같은 이름이 서로 다른 본문으로 두 곳에 정의된 경우(예: `llm-help`) 임의로 승자를 고르지 않고 두 행을 모두 남긴다. 이 정책은 새 UX 에서도 유지해야 한다.
- **실패-안전 폴백**: alias 스캔이 비거나 캐시가 깨져도 에러 없이 topic-only 후보로 떨어진다.

즉 **사용자가 요청한 "`/` 누르면 내 함수·alias 목록" 의 데이터 레이어는 이미 대부분 완성돼 있다.** 빠져 있는 것은 진입 동선(UI)과, alias 외의 *shell function* 커버리지다.

### 1.2 현재 명령 라우팅 (실측)

`my_help_impl` 의 `case` 문을 직접 읽고 확인한 실제 동작이다. 설계 논의에서 이 부분이 자주 잘못 인용되므로 못 박아 둔다.

| 입력 | 실제 호출 | 출력 |
|---|---|---|
| `my-help` (인자 없음), `-h`, `--help`, `help` | `_my_help_summary` | **6줄 usage 요약** (카테고리 표가 아니다) |
| `my-help --list` / `list` / `section(s)` | `_my_help_list_sections` | 섹션 *이름* 3개만 |
| `my-help categories` | `_my_help_show_categories` | 카테고리 표 |
| `my-help popular` / `navigation` | `_my_help_section_rows` | 해당 섹션 |
| `my-help --all` / `all` | `_my_help_show_all` | 전체 덤프 |
| `my-help search` / `find` | `_my_help_search` | fzf 팔레트 (없으면 카테고리 표) |
| `my-help <topic|category> [args]` | 카테고리 매칭 → 토픽 라우팅 | 상세 |

### 1.3 빠져 있는 것 / 문제

1. **검색이 숨어 있다.** `my-help` 을 그냥 치면 6줄 usage 요약이 나오고, 퍼지 검색은 `my-help search` 라는 별도 하위 명령을 알아야만 닿는다. 회상(recall) 도구인데 회상 경로가 한 단계 더 깊다.
2. **미리보기(preview)가 없다.** 현재 fzf 호출에 `--preview` 가 없어서, 후보를 고르기 전에 그 토픽/alias 가 무엇인지 볼 수 없다. 고르고 나서야 내용이 뜬다 → 잘못 고르면 다시 처음부터.
3. **스코프 전환 수단이 없다.** 토픽과 alias 가 한 스트림에 섞여 들어간다. "지금은 alias 만 보고 싶다"를 표현할 방법이 없다.
4. **shell function 은 인덱싱되지 않는다.** 인덱서는 `^alias name=` 만 스캔한다. `_my_help_*` 같은 내부 함수는 물론 제외해야 하지만, 사용자가 실제로 쓰는 공개 함수들(`gh_*`, `devx_*` 등)도 함께 빠져 있다.
5. **`packages/my-cli` 가 고아 상태다.** Ink(React) 기반 TUI 3화면(`Home`/`Topics`/`TopicDetail`)이 구현돼 있지만 — 2026-02-20 이후 6개월 이상 정지 — 빌드 산출물이 없고, 어떤 셸 스크립트도 이것을 호출하지 않는다(`setup.sh`, `install.sh`, `mise.toml`, `shell-common/` 전부 무참조). 게다가 `App.tsx` 를 비롯해 CLI 커맨드·테스트에도 `/home/bwyoon/dotfiles/shell-common/functions/my_help.sh` 절대경로가 하드코딩돼 있어 워크트리에서 깨진다.

> 5번이 이번 결정의 핵심 변수다. "TUI 를 만들자"가 아니라 "이미 만들다 만 TUI 를 되살릴 것인가, 접을 것인가"가 실제 질문이다. 그리고 되살리는 일은 UX 작업이 아니라 **별도의 부채 정리 작업**이다.

---

## 2. 조사: 요즘 쓰이는 명령어 탐색 UX 패턴

### 패턴 A. fzf 피커 + preview (navi, pet, fzf-tab, zoxide)

fzf 는 "리스트를 파이프로 받아 퍼지 검색하고 고른 것을 파이프로 뱉는" 한 가지 일만 한다. 그 결과 다른 모든 것에 꽂히는 프레임워크가 됐고, 2026년 모던 터미널 스택 가이드들은 대체로 **fzf 를 가장 먼저 설치할 것**으로 권한다 — 이후 도구(atuin, zoxide 등)가 fzf 의 상호작용 패턴 위에 얹히기 때문이다.

- **navi**: 치트시트 인터랙티브 브라우저. 내부적으로 fzf/skim 을 쓴다. 인자 자리를 대화형으로 물어보고, `Ctrl-G` 같은 키에 바인딩해 입력 중 인라인 호출이 가능하며, tmux 위젯으로도 뜬다. cheat.sh / tldr 연동 내장.
- **pet**: 스니펫 매니저. 이 저장소에도 이미 `shell-common/functions/pet.sh` 로 들어와 있다.
- **fzf 자체의 표시 모드**: 기본은 전체화면이지만 `--height` 로 커서 아래 일부만 차지하게 할 수 있다. 즉 "풀스크린 TUI냐 인라인 피커냐"는 fzf 안에서 플래그 하나로 갈리는 선택지다.

핵심 특성: **구현 비용이 거의 없고, 종료 후 스크롤백에 아무것도 남기지 않으며, 조합 가능**. 대신 다중 패널·지속 상태·복잡한 모달은 못 한다.

### 패턴 B. 풀스크린 다중 패널 TUI (lazygit)

lazygit 은 여러 개의 "view"(박스) 집합으로 구성되고, 확대(zoom)하지 않는 한 대부분의 뷰가 어떤 작업 중이든 항상 보인다. 개발자들이 꼽는 lazygit 의 강점은 다음 넷이다.

1. **일관성**: 뷰 동작 방식이 전부 동일하다.
2. **패널별 키 재해석**: *같은 키가 패널마다 다른 의미*를 갖는다 — 키 개수를 늘리지 않고 기능을 늘리는 방식.
3. **발견 가능성(discoverability)**: 아무 때나 `?` 를 누르면 **현재 패널 기준의** 컨텍스트 치트시트가 뜬다. 144개 키바인딩을 외우지 않아도 되는 이유가 이것이다.
4. **합리적 기본값 + 단축 흐름**: 흔한 작업이 한 키.

핵심 특성: **지속적으로 상태를 조작하는 도구**(스테이징, 리베이스, 체리픽)에 최적. 상태가 화면에 계속 떠 있어야 가치가 나온다.

### 패턴 C. 대화 루프 + 슬래시 커맨드 팔레트 (Claude Code, OpenCode)

Claude Code 의 TUI 는 **Ink(React 기반 터미널 렌더러)의 고도로 커스터마이즈된 포크** 위에 올라가 있다. 커스텀 React reconciler, TypeScript 로 이식한 Yoga 레이아웃 엔진(flexbox), ANSI/CSI/DEC/OSC 파서 스택을 직접 갖는다. 대규모 갱신 시 깜빡임을 막는 synchronized output 도 들어간다.

UX 측면에서 눈여겨볼 부분은 `PromptInput` 컴포넌트다. 멀티라인 편집, 고스트 텍스트 제안, 그리고 **슬래시 커맨드**를 지원한다. `/` 를 치면 built-in·사용자 정의·plugin/MCP 항목이 한 목록으로 열리고 뒤에 붙는 문자열로 필터링된다. 슬래시 메뉴 자체의 다듬기 포인트도 공개돼 있다 — 선택된 행에만 파란 마킹, 매치된 글자만 볼드, 이모지/악센트 이름 보존.

핵심 특성: **입력 라인이 UI 의 1급 시민**일 때 정당화된다. 사용자가 자유 텍스트를 계속 치는 것이 본업이고, `/` 는 그 흐름을 끊지 않으면서 명령 모드로 넘어가는 이스케이프 해치다.

### 패턴 D. 히스토리 DB (atuin)

셸 히스토리를 SQLite 로 대체하고, 전체화면 검색 UI + (선택) E2E 암호화 동기화를 제공한다. "내가 전에 뭐 쳤더라"를 푸는 축. my-help 의 "내가 뭘 정의해뒀더라"와 인접하지만 데이터 소스가 다르다 (실행 이력 vs 정의 목록).

### 패턴 E. 강화된 페이저 (tldr / tealdeer)

색상 강조된 고빈도 예제 5~6개만 보여준다. 빠르고 직관적이지만 상호작용(탐색/검색)이 없다. "예제를 몇 개만, 잘 보여준다"는 **preview 패널의 내용 설계 기준**으로 참고할 가치가 있다 — 전체 덤프가 아니라 상위 예제 몇 개.

### 패턴 F. 셸 스크립트용 TUI 위젯 (gum / charm)

`gum` 은 셸 스크립트가 chooser/filter/pager/table 을 그리게 해준다. 이 PC 에는 미설치. Go 바이너리 의존이 추가되므로 MVP 의존성으로 채택하지 않는다.

### 패턴 비교

| 패턴 | 대표 | 구현 비용 | 신규 의존성 | 다중 패널 | 슬래시 팔레트 | my-help 적합도 |
|---|---|---|---|---|---|---|
| A. fzf 피커 | navi, pet | 매우 낮음 | 없음(설치됨) | 불가 | 흉내 가능 | **높음** |
| B. 풀스크린 패널 | lazygit | 높음 | Go/gocui | 가능 | 별도 구현 | 낮음 |
| C. Ink 대화형 | Claude Code | 높음 | Node+React | 가능 | 네이티브 | 중간 (보류) |
| D. 히스토리 DB | atuin | 해당 없음 | Rust | — | — | 데이터 축이 다름 |
| E. 강화 페이저 | tldr | 낮음 | Rust | 불가 | 불가 | preview 내용 설계에 참고 |
| F. 셸 위젯 | gum | 낮음 | Go 바이너리 | 제한적 | 불가 | 낮음 |

---

## 3. 사용자 제안 UX 검토

### 3.1 "lazygit 형태"

**부분 채택을 권한다.** lazygit 의 *레이아웃*(항상 떠 있는 다중 패널)은 my-help 에 과하다. 이유는 도구의 성격 차이다.

- lazygit 은 **상태 조작 도구**다. 스테이징 영역, 브랜치, 커밋 로그가 동시에 보여야 다음 행동을 결정할 수 있다. 세션이 길다.
- my-help 은 **회상 도구**다. 세션이 3초다. "csm 이 뭐였지" → 답 → 종료. 다중 패널이 계속 떠 있을 필요가 없고, 오히려 종료 후 답이 스크롤백에 남는 편이 낫다.

다만 lazygit 의 **원칙 3가지는 그대로 훔칠 가치가 있다**:

- `?` → 컨텍스트 민감 도움말 (현재 스코프에서 가능한 것만)
- 같은 키의 스코프별 재해석 (`Enter` 가 토픽에선 "본문 표시", alias 에선 "정의 표시")
- 하단 상태바에 현재 스코프와 결과 수를 항상 노출

### 3.2 "Claude Code TUI 형태"

**룩앤필은 채택, 아키텍처는 비채택을 권한다.**

Claude Code 가 Ink/React 를 쓰는 이유는 UI 가 대화 로그라는 **가변 길이 스트림**이고, 스트리밍 갱신·부분 리렌더·복잡한 포커스 관리가 필요하기 때문이다. my-help 의 화면은 "필터 가능한 단일 리스트 + 상세 패널"이다. 이 정도를 위해 React reconciler 를 끌고 오는 것은 명백한 과설계다.

반대로 **`/` 슬래시 팔레트라는 상호작용 문법 자체는 훌륭하고, fzf 안에서도 재현 가능하다.**

### 3.3 "`/` 로 함수·alias 출력"

**전면 채택.** 게다가 이건 새 기능이 아니라 **이미 있는 인덱스에 진입로를 뚫는 일**이다 (§1.1). 슬래시는 "무엇을 검색할지"를 바꾸는 **스코프 전환자**로 정의하는 것이 가장 자연스럽다.

**단, `/` 를 셸 프롬프트의 전역 키로 만들면 안 된다.** bash/zsh 프롬프트에서 `/` 는 경로 입력의 정상 문자다. ZLE 위젯이나 readline 바인딩으로 `/` 를 가로채면 `cd /usr/local` 같은 평범한 입력이 깨지고, 게다가 bash 와 zsh 의 구현이 서로 달라 유지보수 비용이 두 배가 된다. **슬래시는 `my-help` 가 연 팔레트 *안에서만* 문법으로 동작한다.**

---

## 4. 동료 문서 교차 검토 결과

두 문서를 원문 검토했다. 수용/비수용과 근거는 다음과 같다.

### 4.1 수용

| 출처 | 제안 | 수용 이유 |
|---|---|---|
| codex | **`/` 를 ZLE/readline 전역 키로 만들지 않는다** | 경로 입력과 충돌하고 bash/zsh 구현이 갈린다. 팔레트 내부 문법으로 한정 (§3.3) |
| codex | **preview 에 후보 값을 셸 문자열로 보간하지 않는다** | 인덱스 내용이 명령 문자열에 섞여 들어가는 인젝션 표면. stdin 또는 안전한 임시 파일로 전달 (§5.2) |
| codex | **함수 수집에 런타임 `declare -F`/`whence` 를 쓰지 않는다** | 셸·로딩 순서에 따라 목록이 달라지고 private helper 가 새어 나온다. 정적 소스 스캔 + 공개 규칙 (§6 Phase 3) |
| codex | **함수 인덱싱을 2단계로 쪼갠다** (registry 우선 → 전면 스캔은 나중) | 노이즈 폭증 리스크를 설계 단계에서 미리 자른다 |
| codex | **`category` 도 후보 종류에 포함** | 카테고리 자체를 검색해 열 수 있어야 2단 구조가 팔레트에 온전히 실린다 |
| codex | **진입 규칙 매트릭스** (입력 × TTY 여부) | 비대화형 출력 불변을 계약으로 못 박는다 (§5.1) |
| codex | **수용 기준(acceptance criteria) 명문화** | 구현·테스트로 바로 넘어갈 수 있게 한다 (§7) |
| codex | 최근 선택 목록은 `XDG_STATE_HOME` 아래, 쓰기 실패는 무시 | 캐시가 아니라 상태이므로 위치가 맞고, 실패-안전 |
| agy | **kind 배지** (`[topic] [alias] [func] [cat]`) 컬럼 표시 | 스코프 전환 없이도 후보 종류를 즉시 구분 |
| agy | **`Ctrl-Y` 클립보드 복사 / `Tab` 셸 버퍼 주입** | navi 의 핵심 UX. 단 **후속 opt-in** 으로 미룬다 (§4.2) |
| agy | **좁은 터미널(80컬럼 이하) 대응** | 3분할·2분할 프리뷰가 깨진다. `--preview-window` 반응형 필요 (§8) |
| agy | preview 하이라이팅에 `bat` 활용 | 이미 설치돼 있고(`~/.local/bin/bat`) 이 저장소에 통합돼 있다. 단 **없을 때 평문 폴백 필수** |
| agy | 인덱스 캐시 원자적 쓰기 (temp → `mv`) | 기존 alias 인덱서에도 적용할 가치가 있는 개선 |
| agy | tldr/tealdeer 벤치마크 | preview 내용 설계 기준으로 흡수 (§2 패턴 E) |

### 4.2 비수용 / 유보

| 출처 | 제안 | 판단 |
|---|---|---|
| agy 초판 | `Enter` 로 함수 **즉시 실행** | **비수용.** 회상 도구가 실수 한 번에 파괴적 명령을 실행하면 안 된다. `Enter` 는 읽기 전용(정의·위치·설명 표시)으로 고정한다 |
| agy | `Tab`/`Ctrl-Y` 를 MVP 에 포함 | **유보 → Phase 3.** 셸 버퍼 주입은 fzf 자식 프로세스가 부모 셸의 라인 에디터를 못 건드리므로 부모 함수 쪽 처리가 필요하다 (§5.4). MVP 안전성·이식성을 먼저 확보한다 |
| agy | `packages/my-cli` Ink TUI 를 로드맵 Phase 로 편성 | **비수용.** 되살리기는 UX 작업이 아니라 부채 정리다. §6 Phase 4 에서 *처분 결정*으로만 다룬다 |
| agy | "54 funcs", "cold-start 10ms 이하 / Node 300ms+" | **비수용.** 측정하지 않은 수치다. 벤치마크 전까지 문서에 넣지 않는다 |
| 양쪽 | 다중 패널 동시 표시 | **비수용.** §3.1 |

### 4.3 동료 지적으로 정정한 것

- codex 지적대로, 인자 없는 `my-help` 의 현재 출력은 **카테고리 표가 아니라 6줄 usage 요약**(`_my_help_summary`)이다. 초판에서 이를 "정적 카테고리 표"로 잘못 적었고, 폴백 대상과 `--list` 의 역할도 함께 틀렸다. §1.2 에 실측 라우팅 표로 대체했다.
- alias 개수는 세는 필터에 따라 468/475/482 로 갈린다. 인덱서와 동일한 필터 기준인 **475** 로 통일했다.

---

## 5. 권장안: fzf 단일 화면 + 슬래시 스코프 (Ink TUI 는 보류)

### 5.1 결론과 진입 규칙

**`my-help` 을 인자 없이 실행하면 곧바로 fzf 팔레트가 뜨게 하고, 그 안에서 `/` 로 스코프를 전환한다.** 별도 TUI 프로세스를 만들지 않는다.

근거:

1. **필요한 UI 가 "리스트 + 필터 + 미리보기" 한 화면이다.** 이 형상은 fzf 의 정확한 사양이다.
2. **fzf 는 이미 설치돼 있고 이미 이 코드에서 쓰이고 있다.** 신규 의존성 0.
3. **`packages/my-cli` 부활 비용이 실제로 크다.** 6개월 정지, 빌드 산출물 없음, 여러 파일에 하드코딩된 절대경로, Node 런타임 상시 기동, dotfiles 전역에 npm 빌드 단계 추가. 얻는 것은 "패널을 더 그릴 수 있음"인데 그 패널이 필요하지 않다.
4. **강등 경로가 이미 검증돼 있다.** fzf 부재 / 비 TTY 에서 정적 출력으로 떨어지는 로직이 이미 있어서, CI·파이프·스크립트 호환이 공짜다.

| 입력 | TTY + fzf | 비대화형 또는 fzf 부재 |
|---|---|---|
| `my-help` | **팔레트 열기** (변경점) | 현행 6줄 usage 요약 (불변) |
| `my-help search` / `find` | 팔레트 열기 | 카테고리 표 (현행 유지) |
| `my-help <topic|category> [args]` | 현행 상세 | 동일 |
| `my-help --list` / `--all` / `categories` / `popular` / `navigation` | 현행 | 동일 |

**비대화형 출력은 한 글자도 바뀌지 않는다.** 파이프·CI·테스트·원격 셸·문서 생성이 전부 그대로 동작한다.

### 5.2 화면 설계

```
┌───────────────────────────────────────────────────────────────────────┐
│ my-help  ›  /all                       82 topics · 475 aliases · N fn │  ← 헤더(스코프+카운트)
├──────────────────────────────┬────────────────────────────────────────┤
│ > /git                       │  # git                                 │
│                              │                                        │
│ ▶ git    [topic] Git short.. │  Category : development                │
│   gc     [alias] commit -m   │  Source   : shell-common/functions/... │
│   gwt    [func]  worktree    │                                        │
│   development [cat] 12 items │  • 상위 예제 5~6개만 (tldr 방식)       │
│   ...                        │                                        │
├──────────────────────────────┴────────────────────────────────────────┤
│ ⏎ show   / scope   ? keys   esc quit                                  │  ← 하단 힌트
└───────────────────────────────────────────────────────────────────────┘
```

헤더의 카운트는 **best-effort** 로 계산한다. 캐시가 없거나 스캔이 실패해도 카운트 표시 실패가 팔레트 전체 실패가 되면 안 된다.

### 5.3 슬래시 스코프 문법

`/` 로 시작하는 입력을 스코프 지시자로 해석하고, 나머지는 그대로 fzf 의 퍼지 쿼리로 넘긴다 (`/alias docker` = alias 스코프 + `docker` 검색).

| 슬래시 명령 | 별칭 | 스코프 | 후보 소스 |
|---|---|---|---|
| `/all` | — | 전체 (기본) | 아래 전부 |
| `/topic` | `/t` | help 토픽 | `_my_help_enumerate_topic_names` |
| `/alias` | `/a` | alias | `_my_help_alias_index` |
| `/func` | `/f` | 공개 shell 함수 | 신규 인덱서 (§6 Phase 3) |
| `/cat [이름]` | `/c` | 카테고리 | `HELP_CATEGORY_MEMBERS` |

`?` 는 현재 스코프에서 유효한 키와 슬래시 문법만 보여주는 도움말로 전환한다 (lazygit 방식).

### 5.4 키맵

| 키 | 동작 | 단계 |
|---|---|---|
| `Enter` | **읽기 전용** 표시 후 종료. 토픽/카테고리 → `my_help_impl` 경로로 열기, alias/func → 정의·위치·설명 출력 | MVP |
| `/` | 스코프 전환 | MVP |
| `?` | 컨텍스트 키 도움말 토글 | MVP |
| `Esc` | 출력 없이 exit 0 | MVP |
| `Ctrl-O` | 정의 파일의 해당 줄을 `$EDITOR` 로 열기 (alias·func 만) | Phase 3 |
| `Ctrl-Y` | 클립보드 복사 (`wl-copy`/`pbcopy`/`clip.exe` 감지, 없으면 조용히 무시) | Phase 3 |
| `Tab` | 셸 프롬프트 버퍼에 주입 후 종료 | Phase 3 |

> **`Tab` 구현 제약**: fzf 는 자식 프로세스이므로 부모 셸의 라인 에디터를 직접 못 건드린다. zsh 는 `print -z`, bash 는 `READLINE_LINE`/`bind` 로 **부모 셸 함수 쪽에서** 처리해야 하고, fzf 는 `--expect=tab` 으로 "어떤 키로 나왔는지"만 알려주는 역할을 한다. 두 셸의 구현이 갈리므로 MVP 에 넣지 않는다.

### 5.5 후보 데이터 계약

기존 5필드 TSV 스키마를 그대로 확장한다. 새 스키마를 만들지 않는다.

```
name <TAB> description <TAB> kind <TAB> location <TAB> detail
```

| kind | name | description | location / detail | Enter 결과 |
|---|---|---|---|---|
| `topic` | `git` | 토픽 설명 | 빈 값 | `my_help_impl git` |
| `category` | `development` | 카테고리 설명 | 멤버 수 | `my_help_impl development` |
| `alias` | `gco` | trailing 주석 또는 위치 | 정의 파일:줄 / 정의문 | 정의 표시 |
| `func` | `gwt` | 등록 설명 또는 첫 주석 | 정의 파일:줄 / 시그니처 | 정의 표시 |

fzf 에는 `--with-nth` 로 앞 3필드(name/desc/kind 배지)만 노출하고, 나머지는 선택된 행에서 읽는다. **동명이의 보존 정책은 그대로 승계** — 이름 키로 dedupe 하지 않고 레코드 전체로만 `sort -u` 한다.

### 5.6 명시적으로 포기하는 것

- 다중 패널 동시 표시 → 회상 도구에 불필요.
- 팔레트 안에서의 명령 **실행** → 위험 대비 이득 없음. 표시까지만 하고 실행은 사용자 몫.
- Ink/React TUI → §5.1 3번. 보류이지 영구 폐기는 아니다(§9).
- 사용량 측정·자동 실행 → 범위 밖.

---

## 6. 구현 로드맵

### Phase 0 — 진입 동선만 바꾸기 (가장 큰 체감, 가장 작은 diff)

- 인자 없는 `my-help` 을 TTY + fzf 일 때만 `_my_help_search` 로 라우팅.
- 비 TTY / fzf 부재 시 `_my_help_summary` 유지 (회귀 방지).
- 검증: TTY 에서 `my-help`, 파이프에서 `my-help | cat`, `fzf` 를 PATH 에서 가린 상태 — 3케이스.

### Phase 1 — 미리보기 + 헤더 + 힌트

- fzf 호출에 `--height`, `--layout=reverse`, `--preview`, `--preview-window`, `--header`, `--bind '?:toggle-preview'` 추가.
- preview 렌더러는 기존 `_my_help_show_alias_entry` / 토픽 렌더러를 재사용한다. 새 렌더러를 만들지 않는다.
- **preview 는 별도 서브셸이라 부모 셸 함수를 직접 못 부른다.** 내부 진입점을 하나 뚫되, **TSV 레코드를 명령 문자열에 보간하지 않고** stdin 또는 안전한 임시 파일 경로로 넘긴다. `--` 와 quoting 을 적용한다.
- `bat` 이 있으면 하이라이팅, 없으면 평문 폴백.
- preview 렌더러는 **부작용이 없어야 한다** (파일 쓰기·명령 실행 금지).

### Phase 2 — 슬래시 스코프 + 카테고리 후보

- `_my_help_search_candidates` 에 `category` 후보 추가. 기존 alias/topic 레코드 형식은 유지.
- `--bind '/:change-prompt(...)+reload(...)'` 로 스코프별 후보 스트림 교체.
- **fzf 버전 게이트**: 이 PC 는 0.44.1. `reload` / `change-prompt` / `toggle-preview` / `become` 은 사용 가능하나 **`transform` 은 0.45+** 다. MVP 에서 `transform` 사용 금지. 미지원 환경에서는 `/` 를 무시하고 기존 동작을 유지한다.

### Phase 3 — 함수 후보 (2단계로 분할)

- **3a. registry 기반**: 공개 명령 이름·kind·설명·source 를 명시 등록하는 작은 registry 를 두고 그것만 `func` 후보로 노출한다. 기존 help topic 과 겹치면 `topic` 태그를 우선한다.
- **3b. 정적 소스 스캔** (3a 가 부족할 때만): `_my_help_build_alias_index` 옆에 `_my_help_build_function_index` 를 추가. 동일한 5필드 스키마, `kind=func`, 동일한 24h TTL, **원자적 쓰기(temp → `mv`)**, 동일한 실패-안전 폴백.
  - 스캔 대상: `shell-common/functions/`, `shell-common/tools/`, `bash/`, `zsh/`
  - 공개 규칙: `_` 로 시작하지 않을 것. `*_help` 는 이미 topic 이므로 `func` 에서 배제.
  - **런타임 `declare -F`/`whence` 는 쓰지 않는다** — 셸·로딩 순서에 따라 결과가 달라지고 private helper 가 샌다.

### Phase 4 — 키보드 인터랙션 (opt-in)

- `Ctrl-O` 에디터 열기 → `Ctrl-Y` 클립보드 → `Tab` 버퍼 주입 순으로, 각각 독립적으로 켤 수 있게.
- 최근 선택 목록은 `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/` 아래. 쓰기 실패는 무시.

### Phase 5 — `packages/my-cli` 처분

되살리지 않기로 한다면 방치가 최악이다. 둘 중 하나를 택한다.

- (a) 설계 문서(`docs/feature/my-cli/`)만 `docs/archive/` 로 남기고 `packages/my-cli` 삭제.
- (b) 남긴다면 최소한 모든 하드코딩 절대경로를 `DOTFILES_ROOT` 기반으로 고치고 README 에 "실험적 / 미연결" 을 명시.

---

## 7. 수용 기준 (acceptance criteria)

- [ ] bash 와 zsh 양쪽에서, TTY + fzf 일 때 `my-help` 이 팔레트를 열고 `Esc` 가 exit 0 으로 닫힌다.
- [ ] fzf 부재 또는 stdin/stdout 이 TTY 가 아닐 때 `my-help` 기본 출력이 **현행 6줄 usage 요약과 바이트 단위로 동일**하다.
- [ ] `/all`, `/topic`, `/alias`, `/func`, `/cat` 이 각각 해당 종류만 표시한다.
- [ ] 선택한 alias/func 는 **절대 실행되지 않고** 정의·위치·설명만 표시된다.
- [ ] 선택한 topic/category 는 기존 `my_help_impl` 경로로 열려 기존 인자 라우팅이 보존된다.
- [ ] alias 인덱스 캐시가 없거나 손상됐거나 소스 트리가 없어도 에러 없이 topic/category 후보로 폴백한다.
- [ ] preview 렌더링이 어떤 파일도 쓰지 않고 어떤 명령도 실행하지 않는다.
- [ ] preview 명령 문자열에 인덱스 내용이 보간되지 않는다 (인젝션 표면 부재).
- [ ] fzf 0.44.1 에서 전 기능이 동작한다 (`transform` 미사용).
- [ ] 80컬럼 터미널에서 레이아웃이 깨지지 않는다.
- [ ] 기존 `my-help search`/`find`, `my-help <topic> [args]`, `--list`, `--all` 의 bash/zsh 테스트가 그대로 통과하고, 팔레트의 필터·선택·폴백 테스트가 추가된다.

---

## 8. 리스크

| 리스크 | 영향 | 완화 |
|---|---|---|
| fzf 0.44 의 액션 제약 | 슬래시 구현 형태가 제한됨 | `transform` 미사용, 버전 게이트, 미지원 시 `/` 무시하고 기존 동작 유지 |
| preview 서브셸에서 셸 함수 접근 불가 | preview 미동작 | 내부 진입점 경유 + stdin/임시파일 전달 |
| preview 명령 문자열에 후보 값 보간 | 인젝션 표면 | 보간 금지, quoting + `--` 적용 |
| 인자 없는 `my-help` 동작 변경 | 스크립트/문서 회귀 | 비 TTY 경로 **바이트 불변** 보장 |
| 함수 인덱스가 내부 함수까지 노출 | 노이즈 폭증 | Phase 3a(registry) 우선, `_` 접두 제외, `*_help` 중복 배제 |
| 후보 과다 (475 alias + 함수) | 검색 정확도 저하 | kind 배지 + 슬래시 스코프. 기본 스코프를 `/topic` 으로 둘지 §9 에서 결정 |
| 80컬럼 이하 터미널 | 프리뷰 분할 깨짐 | `--preview-window` 반응형(폭 좁으면 하단 배치 또는 프리뷰 숨김) |
| `bat` 부재 환경 | preview 렌더 실패 | 평문 폴백 필수 |
| ZLE/readline `/` 가로채기 유혹 | 경로 입력 파괴, bash/zsh 분기 | 팔레트 내부 문법으로만 한정 (설계 고정) |

---

## 9. 확정 사항 (Decisions)

초판의 미결 4건은 2026-09-03 사용자 확인으로 전부 결정으로 전환했다.

- **D-1. 기본 스코프는 `/topic`** — 근거: 후보가 550+ 라 `/all` 로 시작하면 첫 화면이 노이즈가 된다. 82개 토픽만 먼저 보여주고 필요할 때 `/all` 로 넓힌다.
- **D-2. `packages/my-cli` 는 삭제하고 설계 문서만 아카이브** — 근거: fzf 로 방향이 정해진 이상 유지 비용만 남는다. `docs/feature/my-cli/` 는 `docs/archive/my-cli/` 로 옮겨 이력을 보존한다.
- **D-3. 이번 작업 범위는 Phase 0~3 (MVP)** — 근거: 액션 키(`Ctrl-Y`/`Tab`/`Ctrl-O`)는 bash/zsh 라인 에디터 분기를 타므로 범위를 키운다. Phase 4 는 후속 이슈로 분리한다.
- **D-4. `fzf` 는 선택 의존성으로 유지** — 근거: WSL/minimal/CI 가 설치 없이 그대로 동작해야 한다. 부재 시 기존 정적 출력으로 강등하는 경로가 이미 검증돼 있다.
- **D-5. Ink TUI 재개 조건** — "한 화면에서 여러 카테고리를 *동시에* 비교해야 하는" 요구가 실제로 관측될 때만 재검토한다. 그 전까지는 재개하지 않는다. 근거: 회상 도구의 세션 길이(수 초)가 다중 패널의 전제와 맞지 않는다.

---

## 10. 참고 자료

- [jesseduffield/lazygit — DeepWiki](https://deepwiki.com/jesseduffield/lazygit)
- [lazygit Keybindings (en)](https://github.com/jesseduffield/lazygit/blob/master/docs/keybindings/Keybindings_en.md)
- [The (lazy) Git UI You Didn't Know You Need — bwplotka](https://www.bwplotka.dev/2025/lazygit/)
- [Lazygit Cheat Sheet 2026 — 144 Keybindings](https://toolsbase.dev/en/reference/lazygit-commands)
- [Claude Code interactive mode](https://code.claude.com/docs/en/interactive-mode)
- [UI Layer (Ink/React TUI) — claude-code DeepWiki](https://deepwiki.com/alesha-pro/claude-code/7-ui-layer-(inkreact-tui))
- [UI/UX & Terminal Integration — anthropics/claude-code DeepWiki](https://deepwiki.com/anthropics/claude-code/3.9-uiux-and-terminal-integration)
- [I studied Claude Code's leaked source and built a terminal UI toolkit from it](https://dev.to/minnzen/i-studied-claude-codes-leaked-source-and-built-a-terminal-ui-toolkit-from-it-4poh)
- [denisidoro/navi — An interactive cheatsheet tool for the command-line](https://github.com/denisidoro/navi)
- [fzf: Getting Started — junegunn](https://junegunn.github.io/fzf/getting-started/)
- [fzf: Shell Integration — junegunn](https://junegunn.github.io/fzf/shell-integration/)
- [Charm Gum](https://github.com/charmbracelet/gum)
- [How fzf changed the way I think about CLI tools](https://medium.com/@josephdaunt70/how-fzf-changed-the-way-i-think-about-cli-tools-6fc3853fdd39)
- [The Ultimate Terminal Stack in 2026](https://medium.com/vmacwrites/the-ultimate-terminal-stack-in-2026-a-cross-platform-guide-for-macos-linux-and-windows-c0d1f93cd9cc)
- [12 Modern CLI Tools Every Developer Should Use in 2026](https://nexasphere.io/blog/modern-cli-tools-developers-2026)
- 동료 문서: `docs/feature/ux-enhance/my-help-ux-modernization.md`, `docs/feature/ux-enhance/my-help-command-palette-ux-research.md`
- 저장소 내부: `docs/archive/my-cli/` (2026-02 my-cli 마이그레이션 분석, 정지 상태)
- 추적 이슈: #1740
