# Plugins — 체리픽 플러그인 가이드

수많은 Claude Code 플러그인 중 이 dotfiles에서 실제로 설치해 쓰는 플러그인의
설치 방법 · 스킬 설명 · 사용 예제를 정리합니다. 설치된 전체 목록은
`claude/plugin/plugins.json`이 SSOT입니다.

## Index

- [ponytail](./ponytail.md) — 과잉설계 방지 (YAGNI/stdlib/native 우선 강제)

## 문서 구성

플러그인 1개 = 파일 1개, 3개 섹션 고정: 설치 방법 → 스킬 설명 → 사용법.
스킬 수가 많고 개별 분량이 긴 플러그인(예: superpowers)은 예외적으로
스킬별 서브디렉토리를 둔다 — [`../superpowers-ko/`](../superpowers-ko/README.md) 참조.
