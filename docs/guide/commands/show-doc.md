# show-doc

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/manage_doc.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic show_doc --force`

## 호출

- Help 진입점: `show-doc-help [section|--list|--all]`
- 통합 라우팅: `my-help show_doc [section]`
- Alias: `doc-help`, `show-doc-help`

## 요약 (show-doc-help)

- Usage: show-doc-help [section|--list|--all]
- sections
    - clear: clear-doc <file|pattern> usage and examples
    - delete: del-doc <file|pattern> usage and examples
    - description: behavior and safety notes
    - patterns: glob pattern reference
    - details: show-doc-help <section>  (example: show-doc-help clear)

## 섹션

### clear

- Clear content of documentation files
- Usage: clear-doc <file|pattern>
- Examples:
- clear-doc docs/archive/review-2026/abc-review-G.md       // Clear single file
- clear-doc docs/archive/review-2026/abc-review*           // Unquoted glob (both work!)
- clear-doc 'docs/archive/review-2026/abc-review*'         // Quoted pattern
- clear-doc docs/file1.md docs/file2.md       // Multiple files
- clear-doc 'docs/*.md' notes.txt             // Mixed patterns + files

### delete

- Permanently delete documentation files
- Usage: del-doc <file|pattern>
- Examples:
- del-doc docs/archive/review-2026/abc-review-G.md         // Delete single file
- del-doc docs/archive/review-2026/abc-plan*               // Unquoted glob
- del-doc 'docs/archive/review-2026/abc-review*2.md'       // Quoted pattern (deletes *2.md files)
- del-doc docs/file1.md docs/file2.md         // Multiple files
- del-doc 'docs/abc-*' notes.txt              // Mixed patterns + files

### description

- Safely clears the content of documentation files (clear-doc)
- Permanently deletes documentation files (del-doc)
- Both operations require user confirmation (destructive)
- Support both individual files and glob patterns

### patterns

- * matches any characters
- ? matches single character

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/show-doc.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/manage_doc.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
