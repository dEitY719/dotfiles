# graphify

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/graphify_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic graphify --force`

## 호출

- Help 진입점: `graphify-help [section|--list|--all]`
- 통합 라우팅: `my-help graphify [section]`
- Alias: `graphify-help`

## 요약 (graphify-help)

- Usage: graphify-help [section|--list|--all]
- sections
    - concept: 2-pass 추출 | Leiden clustering | confidence 태그
    - install: graphify-setup [dir] (one-click) | pip install graphifyy | graphify install | claude install
    - uninstall: graphify claude uninstall | graphify uninstall [--purge]
    - usage: /graphify . | update | query | path | explain | add | graphify-vault
    - output: graphify-out/ (graph.html, GRAPH_REPORT.md, graph.json)
    - accounts: 멀티 계정에서 스킬이 안 보일 때
    - related
    - details: graphify-help <section>  (example: graphify-help install)

## 섹션

### concept

- 코드/문서/이미지를 지속형 knowledge graph 로 바꿔 AI 가 저장소를 grep 대신 질의하게 한다 — 토큰 절감
- pass 1: Tree-sitter AST 로 코드 구조를 로컬 추출 (LLM 없음, 비용 0)
- pass 2: 문서/이미지 등은 LLM 으로 semantic 추출
- NetworkX 그래프 + Leiden community detection 으로 모듈/god node 도출
- edge confidence 태그: EXTRACTED (확정) / INFERRED (추론) / AMBIGUOUS (불확실)

### install

- 요구사항: Python 3.10+
- one-click: graphify-setup [dir]  (멱등: CLI + 스킬/계정 링크 + .gitignore + claude install + 첫 그래프)
- pip install graphifyy          # 패키지명 graphifyy, CLI 이름은 graphify
- graphify install [--platform claude|codex|opencode|claw|gemini|...]   # SKILL.md 복사
- graphify claude install        # CLAUDE.md 섹션 + PreToolUse hook (always-on, 스킬은 설치 안 함)
- graphify hook install          # git commit/checkout 시 그래프 자동 재빌드
- dotfiles: ./graphify/setup.sh  (스킬 설치 + 계정별 링크, 멱등, pip 는 수동)

### uninstall

- graphify claude uninstall      # CLAUDE.md 섹션 + hook 제거
- graphify uninstall             # 감지된 모든 플랫폼에서 스킬 제거
- graphify uninstall --purge     # graphify-out/ 디렉터리까지 삭제
- dotfiles: ./graphify/uninstall.sh  (계정 링크만 제거, 원본 제거는 위 명령 안내)

### usage

**Claude Code 스킬**

- /graphify .                    # 현재 디렉터리 그래프 생성
- /graphify <path> --update      # 변경분만 증분 갱신
- /graphify <path> --watch       # 파일 변경 감시 후 자동 갱신
- /graphify <path> --wiki        # 커뮤니티별 wiki 생성
- /graphify <path> --cluster-only  # 클러스터링만 재실행
- /graphify <path> --no-viz      # graph.html 생략 (대형 그래프)
**CLI**

- graphify update .              # AST 만 재추출 — LLM 비용 없음 (코드 수정 후)
- graphify query "<q>"           # 질문으로 BFS 부분 그래프 (--dfs, --budget N)
- graphify path "A" "B"          # 두 노드 간 최단 경로
- graphify explain "X"           # 노드와 이웃 설명
- graphify add <url>             # URL 을 ./raw 에 저장 후 그래프 갱신
**Obsidian 노드 단위 탐색**

- graphify-vault                   # repo 루트에서 실행 -> ~/vaults/<repo>-graph 생성 (덮어쓰기)
- GRAPHIFY_VAULT_ROOT=<dir>      # vault 상위 경로 변경 (기본 ~/vaults)
- 수동: graphify export obsidian --dir ~/vaults/<repo>-graph

### output

- **graphify-out/graph.html** — 브라우저용 인터랙티브 시각화
- **graphify-out/GRAPH_REPORT.md** — god node / community / 구조 요약
- **graphify-out/graph.json** — query/path/explain 이 읽는 그래프
- **graphify-out/cache/** — 추출 캐시 (증분 갱신용)

### accounts

- 증상: /graphify 스킬이 ~/.claude-<account> 계정에서 검색되지 않음
- 원인 1: graphify claude install 은 CLAUDE.md + hook 만 등록 — 스킬은 graphify install 이 설치
- 원인 2: graphify install 은 CLAUDE_CONFIG_DIR 를 따른다 — 터미널엔 미설정이라 ~/.claude/skills/graphify 에 설치됨
- 해결: 원본 ~/.claude/skills/graphify 하나를 각 계정 <cdir>/skills/graphify 로 심볼릭 링크
- 자동화: ./graphify/setup.sh 후 Claude Code 에서 /reload-skills
- 사내 모드(단일 계정 ~/.claude)는 링크가 필요 없다

### related

- 소개: https://discuss.pytorch.kr/t/graphify-ai-knowledge-graph/9652
- 전체 명령: graphify --help
- Claude Code: claude-help

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/graphify.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/graphify_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
