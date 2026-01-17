# Reviewer Info

- Reviewer: GPT-5.2 (Codex CLI)
- Date: 2026-01-15
- Scope: `git-crypt` + `.env` 로딩 실패(내부 PC) 원인 분석 및 복구 가이드, 관련 스크립트/로더 수정

# Project Structure Summary (관련 영역)

- `.env`: dotfiles 루트의 환경변수 파일 (git-crypt로 암호화 대상)
- `.gitattributes`: `.env filter=git-crypt diff=git-crypt` 설정
- `shell-common/env/dotenv.sh`: 로그인 시 `.env`를 자동 source
- `shell-common/tools/integrations/git_crypt.sh`: `gcpush` 등 git-crypt 헬퍼
- `shell-common/functions/gc_help.sh`: `gc-help` 문서/가이드 출력

# Incident Summary

내부 PC에서 `git pull` 이후 `source ~/.bashrc` 실행 시 아래 에러가 발생했습니다.

- `bash: /home/bwyoon/dotfiles/.env: line 1: syntax error near unexpected token ')'`
- `.env` 1라인이 `GITCRYPT...`로 시작하는 “바이너리/난독화 문자열”로 보임

이는 거의 확실하게 **repo가 `git-crypt lock` 상태(또는 unlock 불가 상태)에서 `.env`가 “암호문 그대로” 워킹트리에 존재하는데, 이를 bash가 그대로 `source` 하면서 파싱에 실패**한 케이스입니다.

# Root Cause Analysis

## 원인 1: `.env`를 무조건 `source` 하는 로더

`shell-common/env/dotenv.sh`가 `.env` 존재 여부만 확인하고 바로 `. "${DOTFILES_ROOT}/.env"`를 수행했습니다.

- repo가 unlock 상태면 문제 없음 (워크트리에 평문이 존재)
- repo가 lock 상태면 `.env`가 `GITCRYPT...` 헤더를 가진 암호문이며, `source` 시 문법 에러 발생

## 원인 2: 내부 PC에서 `git-crypt unlock` 실패 (GPG 개인키 부재)

사용자 로그:

- `git-crypt unlock` → `Error: no GPG secret key available to unlock this repository.`

즉, repo의 `.git-crypt/keys/...*.gpg`에 등록된 “해당 키를 복호화할 수 있는” **GPG 개인키가 내부 PC에 없어서 unlock 자체가 불가능**한 상태였습니다.

## 원인 3: 헬퍼 스크립트가 잘못된 메타데이터 경로를 안내 (`.git/git-crypt`)

`gcpush` 로그에서:

- “`.git/git-crypt 디렉토리를 찾을 수 없습니다`”
- “`rm -rf .git/git-crypt` 후 `git-crypt init`” 같은 복구 가이드

하지만 `git-crypt`의 공유/추적 메타데이터는 일반적으로 repo 루트의 **`.git-crypt/` (트래킹 대상)** 입니다.
`.git/git-crypt`는 git의 내부 디렉토리이며 clone/pull로 공유되지도 않고, 스크립트가 이를 “정상성 체크”로 쓰면 **항상 오진**할 수 있습니다.

# Your Actions Review (의미/특이점)

## `rm -rf .git/git-crypt`는 의미가 거의 없습니다

해당 경로는 git-crypt의 공유 메타데이터 경로가 아니므로, 없다고 해서 “손상”이라고 보기 어렵고, 삭제해도 근본 원인(내부 PC의 GPG 개인키 부재) 해결에 도움이 되지 않습니다.

## `git-crypt init`는 “기존 암호화 repo”에서는 위험합니다

`git-crypt init`은 새로운 키를 생성/초기화합니다. 이미 `.env`가 암호화되어 운영 중인 repo에서 이를 다시 수행하면:

- 기존에 암호화되어 커밋된 파일들을 **원래 키로 복호화할 수 없게 만드는 방향**으로 문제를 키울 수 있습니다.
- 특히 “unlock이 안 되는 상황”에서 init로 우회하는 것은, 장기적으로 다른 PC(External)와의 호환성을 깨뜨릴 수 있습니다.

이번 로그의 “Generating key...”는 **새 키를 만들었다는 신호**이므로, 내부/외부 PC 간에 키 일관성이 깨졌을 가능성을 강하게 시사합니다.

# Fix Implemented (Repo Changes)

## 1) 잠긴(encrypted) `.env`를 source 하지 않도록 방어

- 변경: `shell-common/env/dotenv.sh`
- 내용: `.env`의 시작 바이트가 `GITCRYPT`로 보이면(잠김 상태), `source`를 건너뛰고 경고만 출력

효과:
- `source ~/.bashrc` 시 `.env`가 암호문이어도 더 이상 bash 파싱 에러로 초기화가 깨지지 않음

## 2) git-crypt 가이드/헬퍼에서 잘못된 경로 `.git/git-crypt` 제거

- 변경: `shell-common/tools/integrations/git_crypt.sh`
- 변경: `shell-common/functions/gc_help.sh`
- 내용:
  - 체크/안내 경로를 `.git-crypt/` 기준으로 수정
  - “기존 repo에서 `git-crypt init` 재실행”을 복구책으로 무심코 안내하지 않도록 문구를 안전하게 조정

# Recovery Playbook (Internal PC 기준)

## 목표: 내부 PC에서 repo를 정상 unlock 상태로 만들기

1. 외부 PC(이미 unlock 가능한 PC)에서 아래 중 하나를 준비
   - (권장) GPG 개인키 export 후 내부 PC에 import
   - 또는 symmetric key(export-key) 파일을 안전하게 전달

2. 내부 PC에서 unlock 수행
   - GPG 방식: `git-crypt unlock`
   - symmetric key 방식: `git-crypt unlock ~/repo-key.txt`

3. 내부 PC의 새 GPG 키를 repo에 “추가”하려면 (이미 unlock 된 상태에서만 가능)
   - `gpg --list-secret-keys --keyid-format=long`
   - `git-crypt add-gpg-user <KEY_ID>`
   - `git add .git-crypt/ && git commit && git push`

# Severity-Grouped Issues

## High

- `.env` 자동 로딩이 lock 상태를 고려하지 않아, 로그인/쉘 초기화가 깨짐
- `gcpush`/`gc_help`가 `.git/git-crypt`를 기준으로 “손상”을 오진하고, 위험한 재초기화(init)를 유도
- 내부 PC에 GPG 개인키가 없으면 unlock이 불가 (운영/재현성 관점에서 치명적)

## Medium

- “unlock 실패”와 “초기화(init)”가 섞여 실행될 때, 내부/외부 PC 간 키 불일치로 장기 장애 가능

## Low

- `.env`에 실제 비밀 값이 존재하는 구조상, 디버깅/출력 시 유출 위험이 큼 (업무 PC/공유 로그 주의)

# Action Items (Priority)

- P0: 내부 PC에 기존 GPG 개인키 또는 symmetric key로 unlock 경로를 확립
- P0: unlock 전에는 `git-crypt init` 재실행 금지 (새 키 생성으로 기존 암호문 복구 불가 위험)
- P1: `gcbackup/gcrestore`(또는 별도 절차)로 “다른 PC에서 unlock 가능한 최소 요건”을 문서화/자동화
- P2: `.env`는 평문 출력/preview를 기본적으로 금지하고(특히 자동 스크립트), 필요한 경우에만 opt-in

# Conclusion

이번 에러는 “잠긴 git-crypt 암호문 `.env`를 bash가 source한 것”이 직접 원인이며, 내부 PC에서 unlock이 실패한 것이 근본 원인입니다.
로더는 잠긴 `.env`를 자동으로 건너뛰도록 수정했고, git-crypt 헬퍼/가이드의 잘못된 경로 안내를 바로잡았습니다.
