# mount

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/mount.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic mount --force`

## 호출

- Help 진입점: `mount-help [section|--list|--all]`
- 통합 라우팅: `my-help mount [section]`
- Alias: `mount-help`

## 요약 (mount-help)

- Usage: mount-help [section|--list|--all]
- sections
    - description: generic bind mount helpers
    - commands: addmnt | show-mnt
    - info: per-command --help references
    - notes: sudo & sudoers configuration
    - details: mount-help <section>  (example: mount-help commands)

## 섹션

### description

- Generic bind mount helpers (Claude skills/docs now use directory symlinks, #575)

### commands

- addmnt <source> <target>    Create bind mount
- show-mnt [path]             Display mount status

### info

- addmnt --help       Usage for addmnt command
- show-mnt --help     Usage for show-mnt command

### notes

- Requires sudo for mount operations
- Configure sudoers for passwordless mounting in /etc/sudoers.d/

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/mount.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/mount.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
