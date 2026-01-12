# Internal Comms Skill

**내부 커뮤니케이션 작성** - 3P 업데이트부터 뉴스레터, FAQ까지 회사 스타일의 커뮤니케이션을 만듭니다.

---

## 🎯 이 스킬이 뭔가요?

팀 업데이트, 상층 보고, 회사 뉴스레터, FAQ 등 내부 커뮤니케이션을 회사의 기존 형식과 톤으로 작성합니다.

마치 회사 커뮤니케이션 팀이 검수한 것처럼, **일관된 스타일과 포맷**을 유지합니다.

---

## 🔄 어떻게 작동하나요?

### 2단계 프로세스

```text
커뮤니케이션 타입 선택 → 해당 가이드 로드 및 작성
```text

#### 1단계: 커뮤니케이션 타입 식별

지원하는 형식:

- **3P 업데이트**: Progress, Plans, Problems (주간 팀 업데이트)

- **Company Newsletter**: 회사 전체 뉴스, 이벤트, 공지

- **FAQ**: 자주 묻는 질문과 답변

- **Status Report**: 프로젝트 상태 보고

- **Leadership Update**: 경영진 대상 보고서

- **기타**: 위에 속하지 않는 모든 내부 커뮤니케이션

#### 2단계: 가이드 로드 및 작성

해당 가이드 파일 로드:

- `examples/3p-updates.md` - 3P 형식

- `examples/company-newsletter.md` - 뉴스레터

- `examples/faq-answers.md` - FAQ

- `examples/general-comms.md` - 일반 커뮤니케이션

**각 가이드 포함**:

- 포맷 예시

- 톤 가이드

- 섹션별 구조

- 실제 예시

---

## 📊 Output (생산물)

### 회사 스타일 커뮤니케이션

```text
┌────────────────────────────────┐
│  [제목]                        │
│                                │
│  [섹션 1]: 진행 사항           │
│  - 완료된 항목 A               │

│  - 완료된 항목 B               │

│                                │
│  [섹션 2]: 계획                │
│  - 다음 주 목표 A              │

│  - 다음 주 목표 B              │

│                                │
│  [섹션 3]: 문제점              │
│  - 해결 필요 사항              │

│                                │
└────────────────────────────────┘
```

**특징**:

- 회사 스타일 일관성

- 명확한 섹션 구조

- 적절한 톤 (친근하면서 전문적)

- 바로 사용 가능

---

## 💡 실제 사용 예시

### 예시 1: 주간 3P 업데이트

#### 요청 (3P)

> "우리 팀의 주간 업데이트를 3P 형식으로 작성해줄래?
> 이번 주에 API 완성, DB 마이그레이션 중, 성능 이슈 있음."

#### 결과 (3P)

```markdown
# Engineering Team - Weekly Update (Week of Jan 13)

## Progress ✅

- **API Integration**: Completed user authentication endpoints

- **Database Migration**: Successfully migrated 50% of legacy data

- **Documentation**: Updated API specs in Confluence

## Plans 📋

- Complete remaining DB migration

- Review and merge pending PRs (5 outstanding)

- Performance testing for new endpoints

- Team sync on Q2 roadmap

## Problems ⚠️

- Query performance issue in new infrastructure (investigating)

- Blocked by approval from Security team on data encryption approach

- One engineer out next week, will backfill knowledge transfer

---
```text

### 예시 2: 회사 뉴스레터

#### 요청 (뉴스)

> "1월 뉴스레터를 만들어줄래? 새 제품 론칭, 팀 확대, 회사 행사 있음."

#### 결과 (뉴스)

```markdown
# Company Newsletter - January 2025

## Featured Announcement
**New Product Launch: Enterprise Dashboard**
This month we're excited to announce the release of our new enterprise
dashboard, featuring real-time analytics and custom reporting...

## Company Highlights

- Team Growth: Welcome our 5 new engineers!

- Event: All-hands on Jan 20 at 2pm

- Recognition: Congrats to [names] for exceeding Q4 goals

## Team Updates

- Product: Q1 roadmap finalized

- Sales: Record month closing 3 new enterprise deals

- Engineering: Infrastructure upgrade 90% complete

---
```

### 예시 3: FAQ

#### 요청

> "회사 신입 직원을 위한 FAQ를 만들어줄래?
> 첫 주, 온보딩, 시스템 접근 같은 것들."

#### 결과 (FAQ)

```markdown
# New Employee FAQ

## Getting Started

**Q: First day에는 뭘 해야 하나요?**
A: 오전에 HR 안내, 점심은 팀과 함께, 오후에 IT 세팅...

**Q: 시스템 접근은 어떻게?**
A: IT 지원팀에 요청, 24시간 내 완료...

**Q: 멘토는 누가?**
A: [담당자]가 정해져 있습니다...

---
```text

---

## 🎯 특징

| 특징 | 설명 |
| --- | --- |

| **다양한 타입** | 3P, 뉴스레터, FAQ, 보고서 등 |
| **회사 스타일** | 기존 가이드 준수 |
| **일관된 톤** | 전문적이면서도 친근함 |
| **명확한 구조** | 섹션별로 정돈됨 |
| **바로 사용** | 복사-붙여넣기로 즉시 사용 |
| **유연한 조정** | 회사 특성에 맞게 수정 |
| **빠른 제작** | 효율적인 작성 프로세스 |

---

## 🚀 시작하기

### 사용자 입장 (Claude 사용할 때)

```text
"우리 팀의 주간 업데이트를 3P 형식으로 작성해줄래?"
```

또는

```text
"1월 회사 뉴스레터를 만들어줘. [주요 뉴스들]이 포함되어야 해."
```text

또는

```text
"우리 회사 FAQ를 만들어줄 수 있어? [주제들]에 대해."
```

### 예상 시간

- **3P 업데이트**: 10-15분

- **뉴스레터**: 20-30분

- **FAQ**: 15-25분 (항목 수에 따라)

---

## 🛠️ 기술 스택

- **포맷**: Markdown 또는 Google Docs 텍스트

- **배포**: Email, Slack, 회사 인트라넷

- **도구**: 표준 텍스트 에디터

- **검증**: 회사 스타일 가이드

---

## 📚 스킬의 핵심 철학

> **"일관성이 신뢰를 만든다"**

- 모든 내부 커뮤니케이션은 같은 스타일

- 명확한 구조 = 빠른 읽음

- 적절한 톤 = 팀 문화 표현

- 효율: 시간 낭비 없이 전문적 품질 확보

---

## ❓ FAQ

**Q: 회사 스타일 가이드가 있다면?**

A: 제공해주면, 그 스타일로 모든 커뮤니케이션을 맞춥니다.

**Q: 다양한 팀의 업데이트도 가능한가요?**

A: 네! 엔지니어링, 제품, 영업 등 모든 팀 가능합니다.

**Q: 뉴스레터 길이는?**

A: 유연합니다. 짧게 (500자) 또는 길게 (2000자) 모두 가능합니다.

**Q: 톤을 더 격식 있게 또는 캐주얼하게?**

A: 요청하시면 조정합니다. "좀 더 캐주얼하게" 또는 "더 공식적으로".

---

## 📖 더 알고 싶으면

- **SKILL.md**: 모든 커뮤니케이션 타입 상세 가이드

- **examples/**: 각 타입별 완성 예시

- **tone-guide.md**: 회사 톤 설정 방법

---

**이 스킬의 목표**: 전문적이고 일관된 내부 커뮤니케이션으로 팀과 회사 문화를 강화하는 것입니다. 📢✨
