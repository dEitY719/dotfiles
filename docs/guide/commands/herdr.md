# herdr

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/herdr_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic herdr --force`

## 호출

- Help 진입점: `herdr-help [section|--list|--all]`
- 통합 라우팅: `my-help herdr [section]`
- Alias: `herdr-help`

## 요약 (herdr-help)

- Usage: herdr-help [section|--list|--all]
- sections
    - concept: agent multiplexer | 세션 유지 | prefix Ctrl+b
    - pane: split right/down | hjkl 이동 | zoom | rename | close
    - tab: new | next/prev
    - workspace: navigation | new
    - control: detach
    - plugin: 설치된 플러그인 | 키바인딩 | herdr plugin CLI
    - example | related
    - install: 사외 curl|sh · 사내 GitHub 릴리스 바이너리
    - details: herdr-help <section>  (example: herdr-help pane)

## 섹션

### concept

- 여러 코딩 agent를 한 터미널에서 실행하는 multiplexer
- 서버에 세션 유지 — 터미널/SSH 끊겨도 agent 계속 동작
- 모든 단축키: prefix (기본 Ctrl+b) 누른 뒤 해당 키

### pane

- **prefix+v** — split right (좌우 분할)
- **prefix+minus** — split down (상하 분할, horizontal)
- **prefix+h** — 왼쪽 pane으로 이동
- **prefix+j** — 아래 pane으로 이동
- **prefix+k** — 위 pane으로 이동
- **prefix+l** — 오른쪽 pane으로 이동
- **prefix+z** — 현재 pane 풀스크린 토글 (zoom)
- **prefix+shift+p** — 현재 pane 이름 변경
- **prefix+x** — 현재 pane 닫기

### tab

- **prefix+c** — 새 탭 생성
- **prefix+n / prefix+p** — 다음 / 이전 탭

### workspace

- **prefix+w** — workspace 간 이동
- **prefix+shift+n** — 새 workspace 생성

### control

- **prefix+q** — 세션에서 빠져나오기 (detach client) — agent는 계속 실행

### plugin

**설치된 플러그인**

- **plugin_id** — 설치 소스 (owner/repo) — 액션 — 용도
- **herdr-file-viewer** — smarzban/herdr-file-viewer — open-file-viewer[-tab] — git-aware 파일 뷰어
- **persiyanov.reviewr** — persiyanov/herdr-reviewr — toggle — agent diff 코드리뷰 페인
- **ray.plugin-manager** — speardragon/herdr-plugin-manager — open — 플러그인 매니저 팝업
- 현재 설치 상태는 herdr plugin list 가 SSOT — 위 표는 기본 구성
**신규 PC 부트스트랩**

- ./setup.sh 한 번이면 config 심링크 + 플러그인 + 외부 바이너리까지 끝 (멱등)
- 플러그인 herdr/plugins.conf · 외부 바이너리 herdr/tools.conf (lazygit · glow · delta · bat)
- 외부 바이너리는 gh 설치 + gh auth login 필요 — 익명 GitHub API 는 IP 당 60회/시간이라 공용 사내 IP 에서 먼저 소진된다
- 외부 바이너리 릴리스 자산은 Linux x86_64 로 고정 — 다른 플랫폼은 설치 안내만 하고 건너뛴다
- 설치 실패는 경고만 남기고 넘어간다 — 플러그인이 없으면 키바인딩이 무동작, 렌더러가 없으면 뷰어가 plain text
- HERDR_SKIP_PLUGINS=1 / HERDR_SKIP_TOOLS=1 ./setup.sh   # 각 단계 건너뛰기
**키바인딩**

- 커스텀 명령은 prefix+ctrl+<letter> 로 통일 (내장 액션과 충돌 회피)
- **Key** — Action
- **prefix+ctrl+f** — 파일 뷰어 (split)
- **prefix+ctrl+t** — 파일 뷰어 (별도 tab)
- **prefix+ctrl+r** — reviewr 토글
- **prefix+ctrl+p** — 플러그인 매니저 열기
- **prefix+ctrl+g** — lazygit 팝업 (플러그인 아님 — tools.conf 로 설치)
**herdr plugin CLI**

- herdr plugin install <owner>/<repo>              # 부트스트랩 실패분 수동 재시도
- herdr plugin uninstall <plugin-id>               # 업데이트는 uninstall 후 재설치
- herdr plugin list                                # 설치 목록 + plugin_id + config 경로
- herdr plugin enable|disable <plugin-id>
- herdr plugin config-dir <plugin-id>              # 플러그인별 설정 디렉터리
- herdr plugin log list                            # 실행 로그 (--plugin ID, --limit N)
- herdr plugin action list                         # 호출 가능한 액션 전체 (JSON)
- herdr plugin action invoke <action> --plugin <plugin-id>   # 액션명은 위 표 참조
- herdr plugin link <path> / unlink <plugin-id>    # 복제 없이 작업 디렉터리 연결
**설정**

- config.toml 은 dotfiles SSOT (herdr/config.toml) 심링크
- herdr config check                               # 문법 검증 (내장 액션과의 키 충돌은 검사하지 않음)
- herdr server reload-config                       # 재시작 없이 반영
- HERDR_CONFIG_PATH=/tmp/try.toml herdr config check  # 실제 설정을 건드리지 않고 후보 검증
- 파일 뷰어 렌더러 glow · delta · bat — setup.sh 가 설치, PATH 에 있으면 자동 사용

### example

- herdr                    # 세션 시작/재접속
- claude                   # pane 안에서 agent 실행
- prefix+v                 # 오른쪽 split
- prefix+minus             # 아래 split (오른쪽 pane 안에서)
- prefix+j / prefix+l 등   # pane 간 이동
- prefix+q                 # detach
- herdr                    # 나중에 다시 접속, agent 그대로

### related

- Docs: https://herdr.dev/docs/
- tmux 사용자라면: tmux-help

### install

- 사외(표준, 전 OS): curl -fsSL https://herdr.dev/install.sh | sh  (또는 brew install herdr / mise use -g herdr)
- 사내(프록시 차단 우회, Linux x86_64 전용): curl -fsSL -o ~/.local/bin/herdr https://github.com/ogulcancelik/herdr/releases/latest/download/herdr-linux-x86_64 && chmod +x ~/.local/bin/herdr
- macOS/Apple Silicon 사내망: 위 바이너리는 Linux 전용 — 사외(표준) brew/mise 경로 사용 또는 releases 페이지에서 darwin 자산명 확인
- 사내(버전 고정): 위 URL의 latest/download 대신 download/v0.7.5 로 태그 지정
- 근본 해결: 프록시 예외 신청 — GSAMS https://gsams.samsungds.net

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/herdr.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/herdr_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
