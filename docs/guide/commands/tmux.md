# tmux

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/tmux_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic tmux --force`

## 호출

- Help 진입점: `tmux-help [section|--list|--all]`
- 통합 라우팅: `my-help tmux [section]`
- Alias: `tmux-help`

## 요약 (tmux-help)

- Usage: tmux-help [section|--list|--all]
- sections
    - concept: 세션 유지 | 화면 분할 | prefix Ctrl+b
    - session: tmux new | attach | ls | kill-session
    - pane: % | " | arrow | z | x | Alt+arrow
    - control: d | s | $
    - window: c | n/p | 0-9 | ,
    - copy: [ | Space | Enter | q | ]
    - example | companion | custom | related
    - details: tmux-help <section>  (example: tmux-help session)

## 섹션

### concept

- SSH/터미널 종료 후에도 세션 유지
- 화면 분할로 여러 작업 동시 수행
- 모든 단축키: Ctrl+b (prefix) 누른 뒤 해당 키

### session

- **tmux new -s <name>** — 새 세션 생성
- **tmux attach -t <name>** — 세션 다시 연결
- **tmux ls** — 세션 목록 확인
- **tmux kill-session -t <name>** — 세션 삭제

### pane

- **%** — 좌우 분할
- **"** — 상하 분할
- **arrow keys** — 패인 이동
- **z** — 현재 패인 전체화면 토글
- **x** — 현재 패인 닫기
- **Alt+arrow (no prefix)** — 패인 크기 조절

### control

- **d** — 세션에서 빠져나오기 (detach)
- **s** — 세션 목록 선택 이동
- **$** — 현재 세션 이름 변경

### window

- **c** — 새 윈도우 생성
- **n / p** — 다음 / 이전 윈도우
- **0-9** — 해당 번호 윈도우로 이동
- **,** — 현재 윈도우 이름 변경

### copy

- **[** — 카피 모드 (스크롤 가능)
- **Space** — 선택 시작 (카피 모드 내)
- **Enter** — 선택 영역 복사 (카피 모드 내)
- **q** — 카피 모드 종료
- **]** — buffer_0 붙여넣기

### example

- tmux new -s dev        # 세션 시작
- Ctrl+b %               # 좌우 분할
- 오른쪽에서 claude 실행
- Ctrl+b z               # 전체화면 토글
- Ctrl+b d               # detach
- tmux attach -t dev     # 나중에 다시 연결

### companion

- **marmonitor** — tmux 상태바 모니터링 플러그인
- Install: npm install -g marmonitor
- Setup:   marmonitor setup tmux
- tmux 안에서 prefix+I 로 플러그인 활성화

### custom

- **tmux-spawn [agent]** — 3-pane AI 세션 생성
- **tmux-teardown [name|all]** — 세션 정리 (기본: all)

### related

- Cheat sheet: https://tmuxcheatsheet.com/
- Terminal: ghostty-help
- Zsh shell: zsh-help

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/tmux.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/tmux_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
