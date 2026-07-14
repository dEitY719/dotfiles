# PORTS.md — 중앙 포트 레지스트리 (SSOT)

## 목적

유사 아키텍처(frontend + backend + DB)의 프로젝트를 여러 개 병행 운영할 때
각 스택의 default 포트(Vite 5173 / uvicorn 8000 / Postgres 5432·5433)를 그대로
쓰면 프로젝트끼리 충돌한다. 이 파일은 각 프로젝트에 **정수 index 하나만** 배정하면
포트 3개가 공식으로 자동 결정되도록 하는 단일 진실 소스(SSOT)다. 새 프로젝트는
"다음 빈 index"만 집으면 되고, 충돌 여부는 이 표 한 장으로 확인한다.

## 할당 공식 (decade block)

```
port = 9200 + index*10 + role_offset

role_offset:
  backend  = 0
  frontend = 1
  db(host) = 2
  # +3..9 는 여분 (worker / cache / metrics 등)
```

- 프로젝트당 10칸 블록을 통째로 예약 → 한 프로젝트의 포트가 다 붙어 있어 스캔·정리가 쉽다.
- `9200`~`9299` 범위에 최대 10개 프로젝트(index 0..9)를 수용한다.
- 주의: **9200 은 Elasticsearch/OpenSearch 기본 HTTP 포트**다. ES/OpenSearch 를
  쓰는 프로젝트가 생기면 그때 해당 블록(index 0)만 피한다.

## 레지스트리

| index | project       | backend | frontend | db(host) | 비고      |
|------:|---------------|--------:|---------:|---------:|-----------|
| 0     | stock-steward | 9200    | 9201     | 9202     | 적용 완료 |
| 1     | (TBD)         | 9210    | 9211     | 9212     |           |
| 2     | (TBD)         | 9220    | 9221     | 9222     |           |
| 3     | (TBD)         | 9230    | 9231     | 9232     |           |
| 4     | (TBD)         | 9240    | 9241     | 9242     |           |
| 5     | (TBD)         | 9250    | 9251     | 9252     |           |
| 6     | (TBD)         | 9260    | 9261     | 9262     |           |
| 7     | (TBD)         | 9270    | 9271     | 9272     |           |
| 8     | (TBD)         | 9280    | 9281     | 9282     |           |
| 9     | (TBD)         | 9290    | 9291     | 9292     |           |

> index 는 **유일**해야 한다. 중복·공식 이탈 여부는
> `scripts/check_port_registry.sh` 로 검증한다.

## 새 프로젝트 index 배정 절차

1. 위 표에서 `(TBD)` 인 가장 작은 index 를 고른다 (= "다음 빈 index").
2. 해당 행의 `project` 를 실제 이름으로 바꾸고 `비고` 를 채운다.
3. 공식으로 나온 3개 포트를 프로젝트 `.env.example` 에 문서화한다 (아래 스니펫).
4. `sh scripts/check_port_registry.sh` 로 index 중복·공식 이탈이 없는지 확인한다.
5. 이 변경을 커밋한다 — 표가 곧 예약 기록이다.

index 0..9 를 모두 소진하면 `9300` 대역으로 블록을 확장하거나, 쓰지 않는
프로젝트를 회수(recycle)한다.

## 프로젝트 쪽 규약

포트는 코드가 아니라 **설정**으로 다룬다. 프로젝트 config 는 env(`.env`)에서
포트를 읽고, `.env.example` 에 블록을 문서화한다(`.env` 는 gitignore).

index=1 프로젝트의 `.env.example` 예시:

```dotenv
# 중앙 포트 레지스트리(dotfiles/PORTS.md) index=1
# port = 9200 + index*10 + role_offset
BACKEND_PORT=9210
FRONTEND_PORT=9211
DB_PORT=9212
```

stock-steward(index 0)에는 이미 decade-block + env-driven 설정이 적용되어 있다.

## 참고

- 스캐폴딩/템플릿 자동 주입 훅(issue #1154 선택 항목 2)은 현재 dotfiles 에 공용
  프로젝트 스캐폴더가 없어 보류한다. 스캐폴더가 생기면 그때 `.env.example` 에 위
  블록을 주입하는 훅을 추가한다.
