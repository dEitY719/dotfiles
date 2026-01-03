# Maintenance Scripts

Dotfiles 유지보수를 위한 1회성/주기적 도구 모음

## 📁 포함된 스크립트

### analyze_shebangs.py
- **목적**: Shell 스크립트 shebang 일관성 분석
- **사용**: `python3 analyze_shebangs.py`
- **출력**: Bash 전용 기능 감지 및 올바른 shebang 권장
- **보고서 위치**: `docs/analysis/`

### check_bash_status.sh
- **목적**: Bash 파일 회귀 테스트 (Shell 버전)
- **사용**: `bash check_bash_status.sh`
- **기능**:
  - Syntax checking (bash -n)
  - Source testing (isolated/chain 모드)
  - Trace 로깅 (bash -x)
  - 상세 로그 파일 생성

### check_bash_status.py
- **목적**: Bash 파일 회귀 테스트 (Python 버전)
- **사용**: `python3 check_bash_status.py`
- **요구사항**: `pip install rich`
- **기능**:
  - Shell 버전과 동일한 테스트
  - Progress bar 및 rich formatting
  - 더 읽기 쉬운 출력 형식

## 💡 사용 시나리오

### Shebang 검증
- 새로운 shell 스크립트 추가 후 shebang 검증
- 대규모 리팩토링 후 일관성 확인
- Bash/POSIX 호환성 검토

### Bash 파일 회귀 테스트
- Bash 파일 수정 후 동작 검증
- 대규모 리팩토링 후 회귀 방지
- 새로운 .bash 파일 추가 후 통합 테스트

## 🔗 관련 문서

- [Shebang 분석 보고서](../../docs/analysis/SHEBANG_ANALYSIS_REPORT.md)
- [검증된 수정 가이드](../../docs/analysis/VERIFIED_PRIORITY_FIXES.md)
