# devx:claude-to-codex — AGENTS.md handling

Repository root means the nearest project root containing the main
project files (of the target project being worked on — not this dotfiles
repo).

When invoked:

- If root `AGENTS.md` does not exist, create it with exactly:

  ```md
  @CLAUDE.md
  ```

- If root `AGENTS.md` exists and already contains `@CLAUDE.md`, leave it
  unchanged.
- If root `AGENTS.md` exists and does not contain `@CLAUDE.md`, add
  `@CLAUDE.md` at the top unless doing so would obviously break an
  existing structured file. In that case, add it in the least disruptive
  location and preserve existing content.

Do not add extra Codex policy text to `AGENTS.md` unless the user
explicitly requests it.
