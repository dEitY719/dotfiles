# p10k frozen prompt — 1줄 진단과 캐시 cleanup 계약

## Context

- **출처**: [Issue #705](https://github.com/dEitY719/dotfiles/issues/705) —
  `e047b16` ([PR #696](https://github.com/dEitY719/dotfiles/pull/696)) 후에도
  `gwt spawn --launch` 직후 prompt 가 이전 디렉터리/브랜치에 frozen 되는 회귀
- **선행 fix**: `POWERLEVEL9K_INSTANT_PROMPT=verbose → off` 로 placeholder
  precmd 단계는 제거, 그러나 dump cache 잔존 + `emulate -L sh` race 가
  남아있어 회귀가 부분적으로 재현됨
- **파일**: `shell-common/functions/zsh.sh` 의 `_zsh_clear_p10k_caches`,
  `zsh/app/p10k.zsh:1741`

worktree spawn 직후 `%~` 와 vcs 세그먼트가 spawn 직전 디렉터리 (`~/dotfiles` /
`main`) 에 박혀 있고, `pwd` 는 정확한데 prompt 만 lagging 하는 패턴.
`exec zsh` 로만 복구되는 transient init race.

## Pattern

진단의 **SSOT 는 한 줄** 입니다 — array 에 진짜 `_p9k_precmd` 가 등록됐는지:

```zsh
print -lr -- $precmd_functions
```

**정상**: array 어딘가에 `_p9k_precmd` 가 보임.
**회귀**: `_p9k_do_nothing` 만 있거나 `_p9k_precmd` 부재.

`functions _p9k_precmd` 로 보면 *defined* 라고 나오기 때문에 헷갈리는데,
**defined ≠ registered**. precmd 후크 array 에 들어가야 매 prompt 마다
호출됨. 이 한 줄이 race 의 결과를 1분 안에 가른다.

회복 절차는 두 단계:

1. **모든 p10k 캐시 변종 제거** — 단일 `p10k-instant-prompt-${USER}.zsh`
   하나만 지우는 건 부족. dump cache (`.zsh` + `.zwc`) 와 per-user dir 까지
   같이 지워야 zsh 가 stale snapshot 을 자동 로드하지 못함.
2. **`exec zsh`** 로 fresh init — 새 터미널 한 번이면 충분.

## Code

진단:

```zsh
# 1줄 진단 — _p9k_precmd 가 array 에 등록됐는지
print -lr -- $precmd_functions

# 회귀일 때 — defined 인지 verify (헷갈림 방지)
functions _p9k_precmd >/dev/null && echo "defined but NOT registered"
```

복구 (helper 사용):

```sh
# SSOT cleaner (shell-common/functions/zsh.sh)
zsh-clear-p10k-caches
exec zsh
```

또는 수동:

```sh
rm -rf \
  ~/.cache/p10k-instant-prompt-${USER}.zsh{,.zwc} \
  ~/.cache/p10k-dump-${USER}.zsh{,.zwc} \
  ~/.cache/p10k-${USER}
exec zsh
```

## When to use

**적용하기 좋은 경우**

- `gwt spawn --launch` 직후 prompt 좌측이 spawn 직전 경로 그대로
- 워크트리에서 `cd` / branch 변경 후에도 vcs 세그먼트 미갱신
- "사용자 환경만 그런가?" 의심될 때 — 한 줄 진단으로 race 확인

**과할 수 있는 경우**

- prompt 색·아이콘만 깨진 케이스 — `p10k configure` 로 재설정이 정공법
- VS Code 터미널에서 `HOSTNAME%` 만 보이는 케이스 — `zsh-fix-vscode` 가 별도 entry

## Related

- **Cleaner SSOT**: `shell-common/functions/zsh.sh` 의 `_zsh_clear_p10k_caches`
  / `zsh_clear_p10k_caches` — 4개 파일 + per-user 디렉터리까지 cover
- **회귀 테스트**: `tests/bats/functions/zsh_p10k_cache.bats` —
  특히 "issue #705 core regression" 케이스 두 개가 dump cache 누락을 막음
- **이전 fix**: [PR #696](https://github.com/dEitY719/dotfiles/pull/696)
  (`e047b16`) — instant prompt placeholder 제거 (race 1차 layer)
- **race origin**: `gwt spawn --launch` 의 `cd → term_rename --persist →
  eval claude_yolo + emulate -L sh + subshell` 시퀀스 —
  `shell-common/functions/git_worktree.sh` 의 `emulate -L sh` 블록 다수
- **Trouble­shoot 진입**: `zsh-help troubleshoot` 가 본 문서의 1줄 진단을
  안내함
