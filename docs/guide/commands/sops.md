# sops

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/sops_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic sops --force`

## 호출

- Help 진입점: `sops-help [section|--list|--all]`
- 통합 라우팅: `my-help sops [section]`
- Alias: `sops-help`, `age-help`

## 요약 (sops-help)

- Usage: sops-help [section|--list|--all]   (alias: age-help)
- quick start (senv, 현재 디렉터리 기준)
    - 키가 있는 PC: senv init -> senv enc -> git commit
    - 키 백업: senv key export -> cp ~/senv-key.age ~/para/project/vault/secrets/ -> vault 에서 git commit && git push
    - 새 PC: cd ~/para/project/vault && git pull -> senv key import ~/para/project/vault/secrets/senv-key.age -> senv dec -f (기존 .env 덮어씀) -> senv check
- sections
    - overview: 공개키=자물쇠 | 개인키=열쇠 | .env -> .enc.env 커밋
    - setup: install-sops-age | age-keygen | sops-status
    - newproject: senv init | senv enc | 커밋
    - usage: senv init|enc|dec|edit|run|check|key + senv 가 실행하는 sops 명령
    - newpc: senv key export -> senv key import -> senv check
    - risks: 분실=복구 불가 | 유출=원본 비밀값 교체
    - trouble: unmarshal 오류 | no master key | 권한
    - more: 공식 문서 | 관련 명령
    - details: sops-help <section>  (example: sops-help usage | secrets: dotfiles .enc.env, 새 키 추가)

## 섹션

### overview

- age: 키 쌍 생성/암호화 도구. 공개키(age1...)=자물쇠, 개인키(AGE-SECRET-KEY-1...)=열쇠
- sops: 파일의 값만 암호화 (키 이름은 평문) -> git diff 로 변경 항목 확인 가능
- 흐름: .sops.yaml 에 공개키 기재 -> .env 를 .enc.env 로 암호화해 커밋
- 복호화: 각 PC 의 개인키 ~/.config/sops/age/keys.txt 로 해제 (sops 기본 경로)
- 개인키는 외울 수 없는 약 74자 문자열 -> PC 마다 파일로 배치해야 한다 (sops-help newpc)

### setup

- **install-sops-age** — sops + age 설치 — mise 우선, 없으면 ~/.local/bin
- **sops-status** — 설치/키/권한 진단 — 개인키 값은 출력하지 않음
- 개인키 생성은 직접 실행 (AI 에게 시키지 말 것: 키가 대화 기록에 남는다)
    - mkdir -p ~/.config/sops/age
    - age-keygen -o ~/.config/sops/age/keys.txt
    - chmod 600 ~/.config/sops/age/keys.txt
    - age-keygen -y ~/.config/sops/age/keys.txt   # 공개키(age1...) 출력
- Claude Code 에서는 '! age-keygen -o ...' 처럼 ! 접두사로 사용자가 직접 실행

### newproject

- 프로젝트 루트에서 (개인키가 먼저 있어야 한다: sops-help setup)
    - senv init   # .sops.yaml(공개키) 생성 + .gitignore 에 .env 추가
    - senv enc    # .env -> .enc.env
    - git add .sops.yaml .gitignore .enc.env && git commit
- 개인키 내보내기: senv key export  (~/senv-key.age, sops-help newpc)
- 새 PC: cd ~/para/project/vault && git pull -> senv key import ~/para/project/vault/secrets/senv-key.age -> senv dec -f (기존 .env 덮어씀) -> senv check  (파일 없이: senv run make run)
- senv init 이 만드는 .sops.yaml (공개키만 들어가므로 커밋 OK)
    - creation_rules:
    -   - path_regex: '(^|/)\.(enc\.)?env(\.enc)?$'
    -     age: age1xxxxxxxx...   # 여러 키면 콤마로 구분
- 체크: git status 에 .env 가 안 보이는지, .enc.env 값이 ENC[AES256_GCM,...] 인지

### usage

- **senv init** — .sops.yaml + .gitignore — 기존 .sops.yaml 은 덮어쓰지 않음
- **senv enc [file]** — .env -> .enc.env ([file] -> [file].enc) — 실패 시 기존 암호문 유지
- **senv dec [-f] [file]** — .enc.env 또는 .env.enc -> .env (600) — 기존 .env 는 -f 없이 안 덮어씀
- **senv edit [file]** — $EDITOR 로 편집 — 저장 시 재암호화
- **senv run <cmd...>** — 환경변수로 주입해 실행 — 디스크에 평문 없음, eval 안 함
- **senv check** — 키/권한 600/공개키 일치/복호화 점검 — 평문 미출력, 실패마다 다음 행동
- **senv create-pr** — enc -> 브랜치 -> 커밋 -> push -> PR — 기본 브랜치에서만, .enc.env 만 add, 머지 안 함
- **senv key show** — 공개키 + .sops.yaml 일치 여부 — 비밀 출력 없음
- **senv key export [-o f] [-f]** — 개인키를 비밀번호로 잠금 (~/senv-key.age) — git 작업트리 안 거절, 되풀어 검증
- **senv key import [f] [-f]** — 잠금 파일 -> keys.txt (600) — 기존 keys.txt 는 -f 없이 안 덮어씀
- 암호문 파일: 인자 [file] 우선, 없으면 .enc.env, 그것도 없으면 옛 이름 .env.enc
- senv 가 실행하는 sops 명령 (옛 이름 .env.enc 도 열도록 타입 플래그를 늘 붙인다)
    - sops -e --input-type dotenv --output-type dotenv .env > .enc.env
    - sops -d --input-type dotenv --output-type dotenv .enc.env > .env
    - sops edit --input-type dotenv --output-type dotenv .enc.env
- sops exec-env 는 타입 플래그 미지원 -> .env.enc 불가 (senv run 이 대체)
    - 직접 쓰려면 이름이 .env 로 끝나야 함: sops exec-env .enc.env 'npm start'
- 주의: 'sops -d .env.enc' (플래그 없음) 는 unmarshal 오류로 실패한다 (실측)

### newpc

- 권장: senv 로 옮긴다 (age 가 터미널에서 비밀번호를 직접 묻는다)
    - 키가 있는 PC: senv key export   # ~/senv-key.age (git 작업트리 밖에만 쓴다)
    -   -> cp ~/senv-key.age ~/para/project/vault/secrets/ -> vault 에서 git commit && git push -> rm ~/senv-key.age
    -   # vault(개인 private 저장소)에 잠금 파일을 두는 것은 의도된 정책: 보안은 age 비밀번호 강도에 달린다
    -   # git 이력은 영구 -> passphrase 를 바꿔도 옛 커밋 파일은 옛 passphrase 로 열린다. 긴 passphrase 필수
    -   #   (age -p 에서 비워 두면 age 가 강한 passphrase 를 생성. 직접 정하면 diceware 단어 6개 이상, 약 77bit)
    -   # 유출 의심(계정 침해, 실수로 공개) 시 passphrase 교체로는 부족 -> 새 age 키로 교체 (sops-help risks)
    -   # export 가드는 실수로 프로젝트 repo 에 넣는 것만 막는다
    - 새 PC: cd ~/para/project/vault && git pull
    -   -> senv key import ~/para/project/vault/secrets/senv-key.age
    -   -> senv dec -f   # 기존 .env 를 덮어쓴다. 먼저 작업트리 밖으로 백업 (install -m 600 .env ~/<프로젝트명>.env.bak, 확인 후 rm)
    -   -> senv check
- 수동 방법 A: 기존 PC 의 keys.txt 를 안전한 경로(scp, USB)로 복사
    - 복사 위치: ~/.config/sops/age/keys.txt  ->  chmod 600 ~/.config/sops/age/keys.txt
- 수동 방법 B: 비밀번호로 잠근 키 파일을 개인 저장소에 두고 새 PC 에서 1회 해제
    - 잠금 (기존 PC): age -p -o keys.txt.age ~/.config/sops/age/keys.txt
    - 해제 (새 PC):   age -d keys.txt.age > ~/.config/sops/age/keys.txt
    - 해제 후 반드시: chmod 600 ~/.config/sops/age/keys.txt  (기본 644 로 생성됨)
- age -p / age -d 는 터미널에서 비밀번호를 묻는다 (파이프/스크립트로 넘기지 말 것)
- 마무리: install-sops-age && sops-status

### secrets

- 개인 비밀값(API 키, 쿠키)은 dotfiles 루트의 .enc.env 한 곳에 둔다
    - 사내 식별값(호스트, 도메인, 프록시 CA 등)과 AWS 값은 넣지 않는다 (public repo: 암호문과 키 이름이 history 에 영구히 남음)
    - PC 마다 다른 비밀 아닌 값(CA 경로, 활성 계정)은 *.local.sh 유지
- **secret-run [-k KEY]... <cmd>** — $DOTFILES_ROOT/.enc.env 를 주입해 실행 — cwd 불변, 평문 파일 없음, 셸에는 안 남음
- **mcporter <args>** — EXA_API_KEY 만 주입 — mcporter.json 은 ${EXA_API_KEY:-} 로 읽음
- **mcporter-exa-setup** — mcporter.json 의 exa 를 placeholder 로 교체 — .enc.env 에 EXA_API_KEY 가 있어야 실행, ./setup.sh 가 자동 실행
- **twitter <args>** — TWITTER_AUTH_TOKEN / TWITTER_CT0 만 주입 — twitter status 로 확인
- **./hermes/setup.sh** — HERMES_LLM_BASE_URL / HERMES_LLM_API_KEY — 둘 다 없을 때만 hermes/llm_endpoint.local.sh (키별 병합 없음)
- 실패(키 없음, 권한 600 아님, 복호화 실패)는 경고 후 값 없이 실행 -> 기존 fallback 그대로
- mcporter/twitter 는 셸 함수: timeout/xargs 로 감싸면 래퍼를 건너뛴다 -> secret-run -k KEY timeout 60 twitter status
- 새 키 추가 절차
    - 1. cd ~/dotfiles && senv edit   # $EDITOR 에 KEY=value 한 줄 추가, 저장 시 재암호화
    - 2. senv check && git diff .enc.env   # 키 이름만 평문, 값은 ENC[...]
    - 3. 소비 명령: secret-run -k KEY <cmd>, 자주 쓰면 functions/secret_run.sh 에 -k KEY 래퍼 추가
    - 4. git commit .enc.env (평문 .env 는 만들지 않는다. 남은 평문 복제본은 삭제)
- mcporter/twitter 래퍼는 대화형 셸 함수다. cron 처럼 함수가 없는 곳은 래퍼를 안 거친다 (secret-run 도 셸 함수)
    - 어느 경우든 복호화는 개인키가 passphrase 없는 keys.txt 일 때만 비대화형으로 된다

### risks

- **개인키 분실** — 복구 불가 — keys.txt 백업 필수 (잠금 파일/오프라인 보관)
- **개인키 유출** — 재암호화만으로 부족 — 원본 비밀값(DB 암호, API 키) 자체를 교체
- 유출 대응: 새 키 생성 -> .sops.yaml 공개키 교체 -> 비밀값 교체 -> 재암호화
    - sops updatekeys 는 수신자만 바꾼다. 옛 키로 git 이력의 .enc.env 는 여전히 열린다
- 평문 .env 커밋 사고: .gitignore 확인, 이미 push 했다면 비밀값 교체
- keys.txt 권한은 600 유지 (sops-status 로 점검)

### trouble

- **Could not unmarshal input data** — 형식 추론 실패 — --input-type dotenv --output-type dotenv 추가
- **no master key was able to decrypt** — 개인키 없음/불일치 — keys.txt 위치 확인 (sops-status)
- **no matching creation rules found** — .sops.yaml path_regex 불일치 — 파일명이 규칙과 맞는지 확인
- **File has not changed, exiting.** — 편집 내용 없음 (종료 코드 200) — 정상 동작
- **권한 경고** — keys.txt 가 600 아님 — chmod 600 ~/.config/sops/age/keys.txt
- 키 경로를 바꿨다면 SOPS_AGE_KEY_FILE=/path/to/keys.txt 로 지정 (dotfiles 는 export 안 함)

### more

- sops: https://github.com/getsops/sops
- age:  https://github.com/FiloSottile/age
- 설치 스크립트: shell-common/tools/custom/install_sops_age.sh
- 진단/워크플로 함수: sops-status, senv (shell-common/tools/integrations/sops.sh)
- 주입 함수: secret-run, mcporter, twitter (shell-common/functions/secret_run.sh)

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/sops.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/sops_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
