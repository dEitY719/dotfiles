# Maintenance Scripts

Dotfiles 유지보수를 위한 1회성/주기적 도구 모음

## 📁 포함된 스크립트

### analyze_shebangs.py
- **목적**: Shell 스크립트 shebang 일관성 분석
- **사용**: `python3 analyze_shebangs.py`
- **출력**: Bash 전용 기능 감지 및 올바른 shebang 권장
- **보고서 위치**: `docs/analysis/`

## 💡 사용 시나리오

- 새로운 shell 스크립트 추가 후 shebang 검증
- 대규모 리팩토링 후 일관성 확인
- Bash/POSIX 호환성 검토

## 🔗 관련 문서

- [Shebang 분석 보고서](../../docs/analysis/SHEBANG_ANALYSIS_REPORT.md)
- [검증된 수정 가이드](../../docs/analysis/VERIFIED_PRIORITY_FIXES.md)
