## Windows PowerShell에서 WSL 폴더로 이동해 폰트 설치하기

1. **기본 배포판 이름 확인**
   ```powershell
   wsl -l
   ```
   출력에서 설치하려는 배포판 이름(예: `Ubuntu-24.04`)을 기억해 둡니다.

2. **UNC 경로로 프로젝트에 진입**
   ```powershell
   cd "\\wsl$\Ubuntu-24.04\home\deity719\dotfiles"
   ```
   - 경로 전체를 큰따옴표로 감싸야 합니다.
   - Windows 11 최신 버전에서는 `\\wsl.localhost\Ubuntu-24.04\…`도 사용할 수 있습니다.

3. **`font/` 폴더 진입 및 설치 실행**
   ```powershell
   cd font
   .\install-fonts.bat
   ```
   배치 스크립트는 내부에서 `pushd`를 사용해 UNC 경로를 자동으로 드라이브 문자로 매핑하고 `install-fonts.ps1`을 실행합니다.

4. **PowerShell에서 직접 스크립트 실행을 선호할 경우**
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\install-fonts.ps1
   ```

5. **문제가 생길 때**
   - `UNC 경로는 지원되지 않습니다` 메시지가 반복되면 `pushd "\\wsl$\Ubuntu-24.04\home\deity719\dotfiles"` 후 `cd font`에서 실행하십시오.
   - “다른 프로세스가 파일을 사용 중”이라면 Windows Terminal/VS Code 등 폰트를 쓰는 앱을 모두 종료한 뒤 다시 실행합니다.

설치가 끝나면 Windows Terminal 또는 VS Code를 재시작하여 Meslo Nerd Font를 선택하면 됩니다.
