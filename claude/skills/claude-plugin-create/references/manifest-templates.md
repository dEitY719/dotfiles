# claude-plugin:create — Manifest, LICENSE & .gitignore Templates

These are written in Step 5 (`mono` golden layout). `<plugin-name>` is the
repo name (`claude-plugin-harness`); `<plugin>` is the plugin key
(`harness`); `<owner>`/`<host>` come from the flags; `<skill>` entries come
from the dynamically discovered skill list. Keep `marketplace.json`
`name` equal to the repo name 1:1 (same rule as `claude-plugin:rename-repo`).

## `.claude-plugin/marketplace.json`

```json
{
  "name": "<plugin-name>",
  "owner": "<owner>",
  "description": "<one-line marketplace description>",
  "plugins": [
    {
      "name": "<plugin>",
      "source": "./plugins/<plugin>",
      "description": "<plugin description>"
    }
  ]
}
```

The `source` is a **relative** path (`./plugins/<plugin>`) — repo-name
independent, so a later `rename-repo` never has to touch it.

## `plugins/<plugin>/.claude-plugin/plugin.json`

```json
{
  "name": "<plugin>",
  "version": "0.1.0",
  "description": "<plugin description>",
  "maintainer": "<owner>",
  "keywords": ["claude-plugin", "<domain>"],
  "category": "skills",
  "skills": ["./skills/<skill>"]
}
```

Fill `skills[]` from the copied skill list (one `./skills/<skill>` per
skill). Start at `version: "0.1.0"`.

## `LICENSE` (MIT, current year)

Derive the year at runtime (`date +%Y`) — do not hardcode it.

```
MIT License

Copyright (c) <year> <owner>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## `.gitignore`

```gitignore
# OS
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/
*.swp

# Node
node_modules/

# Local
*.local
.env
```
