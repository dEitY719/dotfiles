# 커맨드 레퍼런스 인덱스

`shell-common/functions/` 의 `_<topic>_help_rows_<section>()` 정의에서
자동 생성한 커맨드별 상세 문서 모음입니다 (issue #1262).

## 사용법

```bash
# 동작을 까먹었을 때 — 전체 텍스트 검색
rg "fzf 피커" docs/guide/commands/

# 전체 재생성 (내용이 바뀐 파일만 갱신)
./shell-common/tools/custom/gen_command_docs.sh --force
```

이름 자체가 기억나지 않을 때는 `my-help search` (fzf topic finder) 를 쓰세요.

## 문서 목록

- [agy](./agy.md)
- [bat](./bat.md)
- [bun](./bun.md)
- [category](./category.md)
- [cc](./cc.md)
- [claude](./claude.md)
- [claude-plugins](./claude-plugins.md)
- [cli](./cli.md)
- [codex](./codex.md)
- [csm](./csm.md)
- [devx](./devx.md)
- [dir](./dir.md)
- [docker](./docker.md)
- [dot](./dot.md)
- [dproxy](./dproxy.md)
- [du](./du.md)
- [fasd](./fasd.md)
- [fd](./fd.md)
- [fzf](./fzf.md)
- [gbr](./gbr.md)
- [gc](./gc.md)
- [gcp](./gcp.md)
- [ghostty](./ghostty.md)
- [git](./git.md)
- [gpu](./gpu.md)
- [gwt](./gwt.md)
- [herdr](./herdr.md)
- [hermes](./hermes.md)
- [hook](./hook.md)
- [litellm](./litellm.md)
- [mount](./mount.md)
- [mysql](./mysql.md)
- [mytool](./mytool.md)
- [network](./network.md)
- [npm](./npm.md)
- [nvm](./nvm.md)
- [p10k](./p10k.md)
- [pet](./pet.md)
- [pip](./pip.md)
- [pp](./pp.md)
- [proxy](./proxy.md)
- [psql](./psql.md)
- [py](./py.md)
- [redis](./redis.md)
- [register](./register.md)
- [ripgrep](./ripgrep.md)
- [setup-mode](./setup-mode.md)
- [show-doc](./show-doc.md)
- [ssh](./ssh.md)
- [superpowers](./superpowers.md)
- [sys](./sys.md)
- [tmux](./tmux.md)
- [uv](./uv.md)
- [ux](./ux.md)
- [work](./work.md)
- [work-log](./work-log.md)
- [zsh](./zsh.md)
- [zsh-autosuggestions](./zsh-autosuggestions.md)

## 수기 보강 노트

소스 주석에만 있는 엣지케이스는 자동 추출 대상이 아닙니다.
`.notes/<커맨드>.md` 에 작성하면 재생성 시 각 문서의
"엣지케이스 / 의도된 동작" 절에 그대로 삽입됩니다.
