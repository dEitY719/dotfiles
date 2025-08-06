# **`npm` 전역 패키지 설치 경로 재설정 가이드**

## **1. 문제 인식**

`npm install -g` 명령어 실행 시, 일반 사용자에게 쓰기 권한이 없는 시스템 전역 디렉터리(`/usr/lib/node_modules`)에 접근하려 할 때 **`EACCES: permission denied`** 오류가 발생합니다. 매번 `sudo`를 사용하는 것은 보안상 좋지 않고, 권한 충돌을 야기할 수 있습니다.

## **2. 목표**

`npm`의 전역 패키지 설치 경로를 사용자의 홈 디렉터리(`~/.npm-global`)로 변경하여, `sudo` 없이 안전하고 편리하게 전역 패키지를 관리합니다.

-----

## **3. 절차**

### **Step 1. Node.js 및 `npm` 재설치**

`npm` 실행 파일 자체를 삭제한 경우, `npm` 명령어를 사용할 수 없으므로 `Node.js`를 재설치하여 `npm`을 복구합니다.

```bash
# 기존 Node.js 패키지 완전 삭제
sudo apt-get purge nodejs
sudo apt-get autoremove

# Node.js 재설치 (npm이 함께 설치됨)
sudo apt-get update
sudo apt-get install -y nodejs
```

> **참고:** 이 과정에서 `LANG_LC` 관련 경고가 발생할 수 있으나, Node.js 설치 자체에는 문제가 없으므로 무시해도 됩니다.

-----

### **Step 2. 전역 패키지 설치 경로 재설정**

`npm`이 복구되었으므로, 이제 전역 패키지가 설치될 새로운 경로를 설정합니다.

1. **전역 설치 폴더 생성 및 `npm` 설정 변경**

    ```bash
    # 사용자 홈 디렉터리에 전역 폴더 생성
    mkdir ~/.npm-global

    # npm의 전역 설치 경로를 새로운 폴더로 설정
    npm config set prefix '~/.npm-global'
    ```

2. **`PATH` 환경 변수 업데이트**
    `~/.npm-global`에 설치된 패키지 실행 파일(binaries)을 터미널에서 바로 사용할 수 있도록 `PATH` 환경 변수에 추가합니다.
    사용하는 쉘 설정 파일(`.bashrc` 또는 `.zshrc`)을 텍스트 편집기로 열어 아래 코드를 추가합니다.

    ```bash
    # .bashrc 파일에 추가할 내용
    export PATH=~/.npm-global/bin:$PATH
    ```

3. **설정 적용**
    변경된 설정을 즉시 적용하기 위해 터미널을 다시 시작하거나, 다음 명령어를 실행합니다.

    ```bash
    source ~/.bashrc
    ```

    > **참고:** `zsh` 사용 시에는 `source ~/.zshrc`를 입력합니다.

-----

### **Step 3. 기존 패키지 삭제 및 재설치**

이제 새로운 경로가 정상적으로 설정되었습니다. 기존 `/usr/lib/node_modules`에 설치되어 있던 패키지들을 정리하고, 새로운 경로에 다시 설치합니다.

1. **기존 전역 패키지 삭제**

    ```bash
    # sudo 권한으로 기존 전역 패키지 디렉터리 정리
    sudo rm -rf /usr/lib/node_modules/*
    ```

2. **필요한 패키지 재설치**
    이제 `sudo` 없이도 패키지를 설치할 수 있습니다.

    ```bash
    # npm 최신 버전으로 업데이트
    npm install -g npm@11.5.2

    # 기타 필요한 패키지들 재설치
    npm install -g corepack
    npm install -g markdownlint-cli
    npm install -g @anthropic-ai/claude-code
    ```
