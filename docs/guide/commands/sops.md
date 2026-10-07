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
    - 키가 있는 PC: senv init -> senv enc -> git commit -> senv key export
    - 새 PC: git pull -> senv key import -> senv dec  (또는 senv run make run)
    - 점검: senv check
- sections
    - overview: 공개키=자물쇠 | 개인키=열쇠 | .env -> .enc.env 커밋
    - setup: install-sops-age | age-keygen | sops-status
    - newproject: senv init | senv enc | 커밋
    - usage: senv init|enc|dec|edit|run|check|key + senv 가 실행하는 sops 명령
    - newpc: senv key export -> senv key import -> senv check
    - risks: 분실=복구 불가 | 유출=원본 비밀값 교체
    - trouble: unmarshal 오류 | no master key | 권한
    - more: 공식 문서 | 관련 명령
    - details: sops-help <section>  (example: sops-help usage)

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
- 새 PC: git pull -> senv key import -> senv dec (파일 생성) 또는 senv run make run (파일 없음)
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
    - 새 PC: senv key import ~/senv-key.age -> senv dec -> senv check
- 수동 방법 A: 기존 PC 의 keys.txt 를 안전한 경로(scp, USB)로 복사
    - 복사 위치: ~/.config/sops/age/keys.txt  ->  chmod 600 ~/.config/sops/age/keys.txt
- 수동 방법 B: 비밀번호로 잠근 키 파일을 개인 저장소에 두고 새 PC 에서 1회 해제
    - 잠금 (기존 PC): age -p -o keys.txt.age ~/.config/sops/age/keys.txt
    - 해제 (새 PC):   age -d keys.txt.age > ~/.config/sops/age/keys.txt
    - 해제 후 반드시: chmod 600 ~/.config/sops/age/keys.txt  (기본 644 로 생성됨)
- age -p / age -d 는 터미널에서 비밀번호를 묻는다 (파이프/스크립트로 넘기지 말 것)
- 마무리: install-sops-age && sops-status

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

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/sops.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/sops_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
