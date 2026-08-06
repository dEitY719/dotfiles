# dot

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/dot_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic dot --force`

## 호출

- Help 진입점: `dot-help [section|--list|--all]`
- 통합 라우팅: `my-help dot [section]`
- Alias: `dot-help`

## 요약 (dot-help)

- Usage: dot-help [section|--list|--all]
- sections
    - overview: project pillars (SOLID, cross-platform, skills SSOT)
    - setup: setup.sh | maintenance | diagnostics
    - features: shell separation | UX | help | git | skills
    - commands: my-help | src | dot | ux-help
    - docs: SETUP_GUIDE | AGENTS | UX_GUIDELINES
    - details: dot-help <section>  (example: dot-help setup)

## 섹션

### overview

- SOLID-based shell configuration separation (bash/zsh)
- Cross-platform support (Windows WSL, macOS, Linux)
- Environment-aware setup (Internal/External PC)
- Claude Code skills SSOT via directory symlink (no sudo, #575)

### setup

- Initial setup: ./setup.sh
- Maintenance: scripts/maintenance/fix_crlf_issue.sh
- Diagnostic: shell-common/tools/custom/check_ux_consistency.sh

### mounts

- Claude environment directories automatically configured
- (렌더 실패)

### features

1. Shell separation: bash/ and zsh/ directories
2. UX guidelines: Consistent color and formatting
3. Help system: Type help or [function]-help for info
4. Git attributes: Automatic CRLF/LF line ending management
5. Skills integration: SSOT exposed as directory symlinks (#575)

### commands

- **my-help** — List all available help topics
- **src** — Reload shell configuration
- **dot** — Navigate to dotfiles directory
- **ux-help** — View UX guidelines and semantic colors

### docs

- Complete setup guide: ./SETUP_GUIDE.md
- Project structure: ./AGENTS.md
- UX standards: ./shell-common/tools/ux_lib/UX_GUIDELINES.md

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/dot.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/dot_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
