# notion

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/notion_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic notion --force`

## 호출

- Help 진입점: `notion-help [section|--list|--all]`
- 통합 라우팅: `my-help notion [section]`
- Alias: `notion-help`

## 요약 (notion-help)

- Usage: notion-help [section|--list|--all]
- sections
    - status: NOTION_API_KEY environment check
    - apikey: generate API key from Notion integrations
    - install: npm install -g @notionhq/notion-mcp-server
    - register: claude mcp add notion --scope user
    - verify: cat ~/.claude.json | grep notion
    - test: curl api.notion.com/v1/users/me
    - env: .env example (NOTION_API_KEY | WORKSPACE_ID | WORKSPACE_NAME)
    - links: developers.notion.com | claude.com/claude-code | modelcontextprotocol.io
    - details: notion-help <section>  (example: notion-help install)

## 섹션

### status

- NOTION_API_KEY is not set
- Run: export NOTION_API_KEY='your_key_here' or source ~/.env

### apikey

1. Visit https://www.notion.so/profile/integrations
2. Click 'Create new integration' button
3. Configure integration name and capabilities
4. Copy the API key
5. Store in .env: NOTION_API_KEY='your_key_here'

### install

- npm install -g @notionhq/notion-mcp-server
- Requires Node.js and npm to be installed

### register

- claude mcp add notion --scope user --env NOTION_API_KEY=$NOTION_API_KEY -- npx -y @notionhq/notion-mcp-server
- Uses: --scope user (per-user configuration)

### verify

- cat ~/.claude.json | grep notion
- Should output: "notion": { "@notionhq/notion-mcp-server" ... }

### test

- curl https://api.notion.com/v1/users/me -H "Authorization: Bearer $NOTION_API_KEY" -H "Notion-Version: 2022-06-28" | jq
- Success response: returns workspace and user information (formatted with jq)

### env

# .env or shell env file
NOTION_API_KEY='ntn_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'

# Optional: Workspace settings
NOTION_WORKSPACE_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
NOTION_WORKSPACE_NAME='Your-Workspace-Name'

### links

- Notion Integration Docs: https://developers.notion.com
- Claude Code Docs: https://claude.com/claude-code
- MCP Specification: https://modelcontextprotocol.io

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/notion.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/notion_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
