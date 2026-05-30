# Blog Structure — the 7-section template

Every post follows this exact structure. The narrative arc is: **고통 → 삽질 → 깨달음 → 해결**.

## 1. Title + Subtitle
```markdown
# {자극적 제목} {이모지}
## (feat. {기술 키워드 3개 이내})
```

## 2. TL;DR (3줄 이내)
```markdown
---

## TL;DR

**{한 문장으로 핵심 교훈}**
{보충 설명 1줄}

---
```

The TL;DR is the "trailer" — it should make the reader want to know HOW you got there.

## 3. Problem Situation — "나의 고생"

This is the hook. Write in first person. Include:
- **감정**: 당시 심정 (자신감 → 절망 → 혼란)
- **실제 에러 로그**: 코드블록으로 리얼하게
- **시간/상황 묘사**: "아침 8시 15분, 커피를 마시며..." 같은 디테일
- **반복적 실패**: "고쳤습니다. 다시 실행했습니다. 에러가 났습니다." 패턴
- **표 요약**: 증상 vs 진짜 원인을 한눈에 보여주는 테이블

```markdown
## 문제 상황: {고통을 한 줄로 요약}

### 🔥 나의 현상: "{당시 나의 외침}"

{1인칭 서사. 자신감에 찬 시작 → 현실의 벽}

**결과?**

\`\`\`
{실제 에러 로그 또는 재현한 에러}
\`\`\`
```

## 4. Root Cause — "진짜 원인"

반전 포인트. "알고 보니 이게 문제였다"를 드라마틱하게 전달.

- 코드 비교 (before/after 또는 예상 vs 실제)
- 도표나 다이어그램으로 시각화
- 라이브러리/프레임워크의 반직관적 동작 설명

## 5. Solution — "해결 방법"

Step-by-step으로 구체적으로. 코드블록 필수.

## 6. Lessons Learned — "교훈"

번호 매긴 리스트로 핵심 교훈 3-5개.

## 7. Closing — "결론"

- 감성적 마무리 또는 유머
- P.S. (선택사항, 가벼운 유머)
