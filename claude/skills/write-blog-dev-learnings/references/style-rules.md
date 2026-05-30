# Writing Style Rules

1. **한국어 기본**, 기술 용어는 영어 유지 (`mock`, `docker compose`, `env-file` 등)
2. **1인칭 서사**: "나는", "했습니다", "겪었습니다" — 경험담이므로
3. **이모지 적극 사용**: 섹션 헤딩에 🔥 ⚠️ ✅ 📊 💣 🧟 등
4. **에러 로그는 코드블록**: 실제 로그처럼 생생하게
5. **비유와 은유**: "친절한 금자씨 같은 라이브러리의 배신", "파이프라인의 다음 관문" 등
6. **독자에게 말 걸기**: "당신도 이런 경험 있지 않나요?", "이거 읽고 있는 Free 이용자 여러분..."
7. **분량**: 150~300줄 (너무 짧으면 깊이 없고, 너무 길면 안 읽음)

## File Naming and Location

- **Path**: `~/para/archive/playbook/docs/dev-learnings/{topic}-blog.md`
- **Naming**: kebab-case, `-blog` suffix, no date prefix
- **Examples**: `redis-password-sed-injection-blog.md`, `wsl-systemd-false-positive-blog.md`
