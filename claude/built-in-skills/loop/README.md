# /loop - 반복 실행 스케줄러

Claude Code 내장(built-in) 스킬. 지정한 interval마다 prompt 또는 slash command를 반복 실행하는 스케줄러다.

## 동작 요약

사용자가 `/loop`을 호출하면 지정된 interval에 따라 prompt를 주기적으로 반복 실행한다. interval을 생략하면 기본값 10분(10m)이 적용된다. 최소 단위는 1분이며, 초(s)·분(m)·시(h)·일(d) 단위를 지원한다.

## 사용법

```
/loop [interval] <prompt>
```

| 파라미터 | 필수 여부 | 설명 |
| -------- | --------- | ---- |
| `interval` | 선택 | 반복 주기. `Ns`, `Nm`, `Nh`, `Nd` 형식. 생략 시 `10m` |
| `prompt` | 필수 | 반복 실행할 prompt 또는 slash command |

### Interval 형식

| 접미사 | 단위 | 예시 |
| ------ | ---- | ---- |
| `s` | 초(second) | `30s` |
| `m` | 분(minute) | `5m`, `30m` |
| `h` | 시(hour) | `1h`, `2h` |
| `d` | 일(day) | `1d` |

최소 단위(granularity)는 1분이다.

### 대체 문법

prompt 끝에 `every <interval>` 형태로 interval을 지정할 수도 있다.

```
/loop check the deploy every 20m
```

## 예시

```
/loop 5m /babysit-prs
```
5분마다 `/babysit-prs` slash command를 실행한다.

```
/loop 30m check the deploy
```
30분마다 "check the deploy" prompt를 실행한다.

```
/loop 1h /standup 1
```
1시간마다 `/standup 1` slash command를 실행한다.

```
/loop check the deploy
```
interval 생략 — 기본값 10분마다 "check the deploy"를 실행한다.

```
/loop check the deploy every 20m
```
대체 문법으로 20분 interval을 지정한다.

## 특징

- **Slash command 연계**: prompt 자리에 다른 slash command(`/babysit-prs`, `/standup` 등)를 넣어 기존 스킬을 주기적으로 자동 실행할 수 있다.
- **유연한 interval 지정**: 앞에 `interval`을 두는 방식과 뒤에 `every <interval>`을 붙이는 방식 두 가지를 모두 지원하여 자연스러운 명령 작성이 가능하다.
- **합리적인 기본값**: interval을 생략하면 10분으로 설정되어 별도 지정 없이도 바로 사용할 수 있다.
- **장시간 모니터링 용도**: deploy 상태 확인, PR 관리, standup 리마인더 등 지속적인 감시·반복 작업에 적합하다.
