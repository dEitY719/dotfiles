# markitdown

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/markitdown_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic markitdown --force`

## 호출

- Help 진입점: `markitdown-help [section|--list|--all]`
- 통합 라우팅: `my-help markitdown [section]`
- Alias: `markitdown-help`

## 요약 (markitdown-help)

- Usage: markitdown-help [section|--list|--all]
- sections
    - install: global-packages (uv-tools.txt) | Python 3.12 + pip-system-certs
    - usage: wrapper 자동 저장 | --output-path | 이름 규칙
    - examples: 파일 | YouTube URL | 저장 위치 지정 | stdin
    - troubleshoot: CERTIFICATE_VERIFY_FAILED | --output-path 미인식 | URL 따옴표
    - details: markitdown-help <section>  (example: markitdown-help usage)

## 섹션

### install

- markitdown 은 global-packages 로 관리 — 문서/URL → Markdown 변환 CLI
- SSOT: global-packages/uv-tools.txt 의 줄 markitdown[all] --python 3.12 --with pip-system-certs
- 설치: ./global-packages/setup.sh (또는 ./setup.sh)
- 수동: uv tool install --native-tls --python 3.12 --with pip-system-certs --force 'markitdown[all]'
- 확인: markitdown --version
- 이미 설치된 PC: uv receipt 의 --python/--with 가 uv-tools.txt 와 다르면 setup.sh 가 --force 재설치

### usage

- markitdown <파일|URL> — stdout 이 터미널이면 현재 디렉토리에 <이름>.md 저장
- --output-path DIR (또는 --output-path=DIR) — DIR 에 저장, 없으면 생성
- 기존 파일은 덮어쓰지 않는다
- 원본 stdout 동작: -o FILE 지정 / stdin 입력 / >·| 리다이렉트
- 인자 없이 TTY 에서 실행 → --help 출력 (stdin 대기로 멈추지 않음)
**저장 이름 규칙**

- 로컬 파일: 확장자 제거 (report.pdf → report.md)
- URL: query/fragment 를 떼고 마지막 경로 조각
- YouTube watch?v=ID → ID
**주의**

- wrapper 는 interactive 셸 전용 — 스크립트에서는 원본 markitdown 동작
- wrapper 수정 후 기존 터미널은 exec zsh 로 다시 로드

### examples

- markitdown report.pdf                              # ./report.md
- markitdown 'https://youtube.com/shorts/ID?si=x'    # ./ID.md
- markitdown 'URL' --output-path ~/para/project/obsidian-para/99-Inbox/YouTube
- markitdown doc.docx -o out.md                      # 원본 -o 동작
- cat a.pdf | markitdown -x pdf > a.md               # stdin + 리다이렉트

### troubleshoot

**1. CERTIFICATE_VERIFY_FAILED**

- 증상: Missing Authority Key Identifier 또는 unable to get local issuer certificate
- 원인: 사내 프록시 CA 에 AKI 가 없음 + Python 3.13+ 의 strict X509 검증
- 해결: install 섹션 수동 명령으로 Python 3.12 + pip-system-certs 재설치
**2. unrecognized arguments: --output-path**

- 원인: 셸에 옛 wrapper 가 로드돼 있음
- 해결: exec zsh
**3. URL 따옴표**

- URL 은 작은따옴표로 감싼다
- 큰따옴표 안의 \? 는 backslash 가 URL 에 그대로 남는다

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/markitdown.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/markitdown_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
