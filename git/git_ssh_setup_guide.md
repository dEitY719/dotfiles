# Git SSH 설정하는 방법 (Enterprise GitHub 기준)

이 문서는 **HTTPS 인증 오류(403 등)**를 해결하고,  
안전하게 SSH 키를 이용해 GitHub Enterprise(`github.samsungds.net`)에 연결하는 방법을 정리한 가이드입니다.

---

## 🔹 1. SSH 공개키 생성

이미 SSH 키(`~/.ssh/id_ed25519`)가 있다면 생략해도 됩니다.

```bash
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -C "bwyoon@KORCO158847"
````

* `-t ed25519`: 최신 보안 알고리즘
* `-C`: 식별용 주석(이메일이나 호스트명)

### 실행 예제

```bash
bwyoon@KORCO158847:~/dotfiles(main)$ [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -C "bwyoon@KORCO158847"
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/bwyoon/.ssh/id_ed25519): 
Enter passphrase (empty for no passphrase): 
Enter same passphrase again: 
Your identification has been saved in /home/bwyoon/.ssh/id_ed25519
Your public key has been saved in /home/bwyoon/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:wxbLTGnBFE4bAdRuueX3pwRjO1Uf57wGn/8au2G4IOU bwyoon@KORCO158847
```

---

## 🔹 2. SSH 에이전트 등록

생성한 키를 `ssh-agent`에 등록합니다.

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

### 실행 예제

```bash
bwyoon@KORCO158847:~/dotfiles(main)$ eval "$(ssh-agent -s)"
Agent pid 172432
Identity added: /home/bwyoon/.ssh/id_ed25519 (bwyoon@KORCO158847)
```

---

## 🔹 3. 공개키를 Enterprise GitHub 웹 UI에 등록

1. 공개키 내용 확인

   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```

   예시 출력:

   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJnidzs5YvRjaPSdQl4OtG8uXNtoaHQL8yWi/hW9Ht5t bwyoon@KORCO158847
   ```

2. 브라우저에서 [https://github.samsungds.net](https://github.samsungds.net) 접속

3. 다음 순서로 등록:

   * 오른쪽 위 프로필 사진 클릭 → **Settings** 선택
   * 왼쪽 사이드바에서 **SSH and GPG keys** 클릭
   * **New SSH key** 버튼 클릭
   * 아래 항목 입력:

     * **Title:** 예) `KORCO158847 (laptop)`
     * **Key type:** `Authentication Key` (기본값)
     * **Key:** 위에서 복사한 공개키 (`ssh-ed25519 ...`)
   * **Add SSH key** 클릭

> ✅ 등록 후 관리자 승인 절차가 있을 수 있습니다.

---

## 🔹 4. 연결 테스트

SSH 인증이 정상인지 확인합니다.

```bash
ssh -T git@github.samsungds.net
```

### 성공 시 출력 예시

```
Hi byoungwoo-yoon! You've successfully authenticated, but GitHub does not provide shell access.
```

이 메시지가 나오면 SSH 인증이 정상입니다.

---

## 🔹 5. Git 리모트 URL을 SSH로 전환

기존 HTTPS 리모트를 SSH 방식으로 바꿉니다.

```bash
cd ~/dotfiles
git remote set-url origin git@github.samsungds.net:byoungwoo-yoon/dotfiles.git
```

### 확인

```bash
git remote -v
```

출력 예시:

```
origin  git@github.samsungds.net:byoungwoo-yoon/dotfiles.git (fetch)
origin  git@github.samsungds.net:byoungwoo-yoon/dotfiles.git (push)
```

---

## 🔹 6. 푸시 테스트

```bash
git push -u origin main
```

### 정상 푸시 시 메시지 예시

```
Enumerating objects: 42, done.
Counting objects: 100% (42/42), done.
Writing objects: 100% (42/42), done.
Total 42 (delta 0), reused 0 (delta 0)
To github.samsungds.net:byoungwoo-yoon/dotfiles.git
 * [new branch]      main -> main
```

---

## ✅ 요약

| 단계 | 설명                                 |
| -- | ---------------------------------- |
| 1  | SSH 키 생성 (`ssh-keygen -t ed25519`) |
| 2  | SSH 에이전트 등록 (`ssh-add`)            |
| 3  | GitHub 웹에서 공개키 등록                  |
| 4  | SSH 연결 테스트 (`ssh -T git@...`)      |
| 5  | 리모트 URL SSH로 전환                    |
| 6  | 푸시 테스트로 확인                         |

---

## 💡 참고

* 공개키: `~/.ssh/id_ed25519.pub`
* 개인키: `~/.ssh/id_ed25519`
* SSH 설정 파일(선택): `~/.ssh/config`
* 여러 리포에서 재사용 가능 (한 번 등록하면 동일 계정에서 모두 사용 가능)
