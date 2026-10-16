# category

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/category_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic category --force`

## 호출

- Help 진입점: `category-help [section|--list|--all]`
- 통합 라우팅: `my-help category [section]`
- Alias: `category-help`

## 요약 (category-help)

- Usage: category-help [section|--list|--all]
- sections
    - categories: list all help categories
    - topics: route to my-help <topic>
    - details: category-help <section>  (example: category-help categories)

## 섹션

### categories

**Categories**

- **Category** — Topics
- **AI/LLM (12)** — agy, cc, claude, claude_plugins, claude_skills_marketplace, +7 more
- **CLI Utilities (13)** — bat, del_file, fasd, fd, fzf, +8 more
- **Configuration (6)** — apt, crt, ghostty, p10k, pip, +1 more
- **Development (21)** — bun, cli, devx, du, gbr, +16 more
- **DevOps/Infra (14)** — docker, dproxy, gpu, mount, mysql, +9 more
- **Documentation (5)** — dot, notion, show_doc, work, work_log
- **Meta/Help (3)** — category, register, setup_mode
- **System/Tools (2)** — dir, opencode
- Use: my-help <category> (example: my-help ai)
- Use: my-help <topic> (example: my-help git)

### topics

- Run: my-help <topic> to view a topic's help
- Run: my-help for the full category list
- Run: category-help categories to see categories inline

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/category.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/category_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
