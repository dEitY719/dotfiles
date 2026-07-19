# agentmemory Setup Playbook

[agentmemory](https://github.com/rohitg00/agentmemory) — 로컬 REST/MCP 메모리
서버. Claude Code 세션 간 관찰(observation)을 자동 캡처하고 `recall`/`remember`
등 스킬로 검색한다. 5개 PC ([`docs/.ssot/pc-environment.md`](../../.ssot/pc-environment.md))
전부 Windows + WSL2라 절차는 동일하지만, **PC마다 활성 Claude 계정
(`$CLAUDE_CONFIG_DIR`)이 다르므로** 계정 관련 단계는 PC마다 반복해야 한다.

> API 키, 실제 계정 디렉토리명 등 비밀/개인 정보는 이 문서에 적지 않는다.
> `$CLAUDE_CONFIG_DIR` 값은 `claude/AGENTS.md`의 계정 라우팅 규칙을 따른다.

## 1. 사전 요구사항

- Node.js ≥ 20, WSL2 (Windows는 native 미지원)
- systemd 활성화: `/etc/wsl.conf`에 `[boot] systemd=true` (자동 시작에 필요)
- 포트 3111/3112/3113/49134 비어있어야 함

## 2. 설치

```bash
sudo npm install -g @agentmemory/agentmemory
agentmemory --version
```

**주의**: 설치 직후 바로 `agentmemory &`로 백그라운드 실행하지 말 것 —
최초 실행 시 뜨는 인터랙티브 마법사가 TTY 입력을 기다리다 job control에
의해 suspend된다. 서버 상시 구동은 3번(systemd)으로 바로 진행한다.

## 3. systemd 유저 서비스로 상시 구동 + 자동 시작

```bash
mkdir -p ~/.config/systemd/user
cp docs/guide/playbooks/agentmemory/agentmemory.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now agentmemory.service
loginctl enable-linger "$USER"   # 로그인 세션 없이도 유지 (재부팅 자동시작 필수)
```

`WorkingDirectory=%h/.agentmemory`가 핵심이다 (4번 참고). Windows가 WSL을
로그인/부팅 시 자동 실행하도록 별도 설정돼 있어야 완전한 "부팅 시 자동 시작"이
된다 — WSL 자체를 안 띄우면 systemd도 안 뜬다.

확인:
```bash
systemctl --user status agentmemory.service
curl -fsS http://localhost:3111/agentmemory/livez
```

## 4. ⚠️ 데이터 저장 위치 — cwd 상대경로 함정

iii 엔진은 데이터를 `./data/state_store.db`(프로세스 실행 cwd 기준 상대경로)에
저장한다. 절대경로 고정 env var가 없다. `WorkingDirectory`를 안 정해두면
실행할 때마다 다른 디렉토리에 데이터가 쪼개진다. **위 유닛 파일의
`WorkingDirectory=%h/.agentmemory`가 이를 고정한다 — 절대 지우지 말 것.**

## 5. LLM/임베딩 키 설정

```bash
mkdir -p ~/.agentmemory
cat > ~/.agentmemory/.env <<'EOF'
OPENAI_API_KEY=sk-...
EOF
chmod 600 ~/.agentmemory/.env
systemctl --user restart agentmemory.service   # env 반영에 필수
```

키 없이도 BM25 키워드 검색은 동작한다 (`agentmemory doctor`로 확인).

## 6. Claude Code 연결 (MCP)

```bash
agentmemory connect claude-code
```

**버그**: 이 명령은 `$CLAUDE_CONFIG_DIR`를 무시하고 항상 홈 루트
`~/.claude.json`에만 쓴다. 계정 오버라이드가 있는 PC(다중 계정)에서는
`~/.claude.json`의 `mcpServers.agentmemory` 항목을 **활성 계정의
`$CLAUDE_CONFIG_DIR/.claude.json`에 수동으로 병합**해야 한다 (백업 먼저 뜨고
JSON 유효성 검증할 것). 단일 계정 PC라면 이 단계 불필요.

새 세션에서 `/mcp`로 연결 확인 (첫 연결은 npx 캐시 콜드스타트로 30초
타임아웃 날 수 있음 — 재시도하면 보통 해결).

## 7. 네이티브 스킬 + 자동 캡처 플러그인 설치

```bash
# 스킬 (수동 트리거: remember/recall/recap/handoff/forget/...)
npx -y skills add rohitg00/agentmemory -g -a claude-code -y

# 자동 캡처 플러그인 (세션/툴사용을 훅으로 자동 기록) — Claude Code 안에서 직접 입력
/plugin marketplace add rohitg00/agentmemory
/plugin install agentmemory@agentmemory
/reload-plugins
```

`skills add -g`는 `$CLAUDE_CONFIG_DIR`를 정상적으로 인식한다 (connect와
다르게 버그 없음).

## 8. ⚠️ `agentmemory doctor` 사용 시 주의

systemd로 서버가 이미 떠 있는 상태에서 **fix를 적용하는 `agentmemory doctor`를
실행하지 말 것**. `engine-version-mismatch` 체크가 이 환경에서 항상
false-positive로 뜨고, 그 fix가 systemd cgroup 밖에서 별도 엔진을 띄워
3111 포트를 가로챈다 (cwd를 맞게 해도 재현됨).

- 상태만 확인: `agentmemory status` (REST 조회만, 안전)
- 진단만 보고 싶으면: `agentmemory doctor --dry-run`
- 실수로 fix 버전을 실행했다면:
  ```bash
  ps -ef --forest | grep -E 'agentmemory|iii'   # doctor + 고아 iii 프로세스 확인
  kill -9 <doctor_pid> <iii_pid>
  systemctl --user restart agentmemory.service
  ```

## 9. 자주 쓰는 명령어

| 목적 | 명령어 |
|---|---|
| 상태 확인 | `agentmemory status` |
| 서비스 상태 | `systemctl --user status agentmemory` |
| 로그 | `journalctl --user -u agentmemory -f` |
| 재시작 | `systemctl --user restart agentmemory` |
| 헬스체크 | `curl -fsS http://localhost:3111/agentmemory/livez` |
| 뷰어 | `http://localhost:3113` |
| MCP 목록 확인 | `claude mcp list` |

## 10. 기타 알아둘 것

- `agentmemory demo --serve`의 "Notice: ... found the N+1 query fix" 문구는
  실제 검색 결과와 무관하게 항상 출력되는 고정 텍스트다 (버그). 데모 문구를
  믿지 말고 실제 `smart-search`/`memory_recall` 결과로 판단할 것.
- 데모 정리용 `curl -X DELETE .../sessions?project=...`는 405를 반환한다
  (동작 안 함, 무해 — 데모 데이터는 `/tmp`라 재부팅 시 사라짐).
