# AI Enable 파트원 코드 매핑 (PL 전용)

> **접근 권한**: 파트장 전용. 외부 공유 금지.
> **용도**: JIRA Story Summary의 `{letter}` 코드 ↔ 실제 파트원 매핑
> **작성일**: 2026-04-17

---

## 매핑 표 (확정)

| 파트원 | Greek Letter | 코드 | 메모 |
|--------|--------------|------|------|
| **명 | δ (delta) | `AIE-δ` | |
| **구 | ξ (xi) | `AIE-ξ` | |
| **우 | λ (lambda) | `AIE-λ` | |
| **형 | ψ (psi) | `AIE-ψ` | |
| **녕 | σ (sigma) | `AIE-σ` | |
| **영 | π (pi) | `AIE-π` | |
| **문 | θ (theta) | `AIE-θ` | |
| **정 | ζ (zeta) | `AIE-ζ` | |
| **빈 | γ (gamma) | `AIE-γ` | |

**예약분**: `φ (phi)` — 10번째 파트원 충원 시 배정

---

## 사용 규칙

### Summary 포맷

- **M-1 (조직목표달성)**: `[K{1..4}-{letter}] 2026 조직목표달성 - OKR 기반 핵심과제 수행`
  - `{1..4}`: 담당 핵심제품 번호 (K-1..K-4)
  - 예: `[K1-δ O-1] 2026 조직목표달성 - ...` → **명, Agent App Store 담당
- **M-2/M-3/M-4 (평가 항목)**: `[AIE-{letter}] 2026 <평가 항목> - ...`
  - 예: `[AIE-δ O-2] 2026 혁신/개선업무 - ...` → **명
- **P-1..P-4 (파트 Story)**: `[AIE O-N] 2026 <평가 항목> - ...` (letter 미사용)

### Letter는 평생 토큰

한 번 배정된 letter는 변경하지 않습니다. 과거 JIRA 이력·평가 기록·검색 쿼리 전체가 letter를 키로 연결되기 때문입니다. 파트원이 퇴사해도 letter는 회수하지 않고 deprecated로 표시합니다.

### JQL 필터 예시

- 특정 파트원 전체 이력: `summary ~ "-δ"` → **명의 M-1~M-4 전부
- 특정 제품 담당자 전체: `summary ~ "[K1-"` → Agent App Store 담당 파트원 전부
- 파트 단위 조회: `summary ~ "[AIE O-" OR summary ~ "[AIE-"`

---

## 담당 제품 매핑 (K-1..K-4 배정)

**TODO**: 파트원별 K-1..K-4 핵심제품 담당 확정 후 기입.

| 파트원 | Letter | 담당 제품 | K-Code |
|--------|--------|-----------|--------|
| **명 | δ | TBD | K?-δ |
| **구 | ξ | TBD | K?-ξ |
| **우 | λ | TBD | K?-λ |
| **형 | ψ | TBD | K?-ψ |
| **녕 | σ | TBD | K?-σ |
| **영 | π | TBD | K?-π |
| **문 | θ | TBD | K?-θ |
| **정 | ζ | TBD | K?-ζ |
| **빈 | γ | TBD | K?-γ |

**제품 참조**:
- K-1: SLSI Agent App Store
- K-2: SLSI Alpha Agent
- K-3: SLSI Cowork
- K-4: MCP/Skill Hub

---

## 매핑 생성 방법

```bash
# 랜덤 풀: 시각적으로 Latin 문자와 구분되는 10개 Greek letter
printf "γ\nδ\nζ\nθ\nλ\nξ\nπ\nσ\nφ\nψ\n" | shuf
```

제외된 Greek letter와 이유:
- `α/β/ε/η/ι/κ/ν/ο/ρ/τ/υ/χ/ω`: Latin 문자와 시각적 혼동
- `μ`: narrow font에서 `u`와 혼동 가능
