# Web Artifacts Builder

**React/Tailwind 아티팩트 빌드** - 복잡한 대시보드, 도구, SPA를 단일 HTML 파일로 생성합니다.

---

## 🎯 이 스킬이 뭔가요?

고급 웹 아티팩트를 **완전한 React 앱**으로 만듭니다.
상태 관리, 라우팅, shadcn/ui 컴포넌트 등 모든 것을
포함한 완성도 높은 웹앱을 번들링해 단일 HTML 파일로
배포합니다.

마치 전문 프론트엔드 개발자처럼, 현대적인 웹 기술 스택을 모두 활용합니다.

---

## 🔄 어떻게 작동하나요?

### 4단계 프로세스

```text
1. 프로젝트 초기화 → 2. 개발 → 3. 번들링 → 4. 배포
```text

#### 1단계: 프로젝트 초기화

**스크립트**: `init-artifact.sh`

```bash
bash scripts/init-artifact.sh my-dashboard
cd my-dashboard
```

**생성되는 것**:

- React 18 + TypeScript (Vite)

- Tailwind CSS 3.4.1

- shadcn/ui 컴포넌트 40+개

- 경로 별칭 (`@/`)

- 패키지 구성

#### 2단계: 개발

**생성 파일들**:

- `src/App.tsx` - 메인 컴포넌트

- `src/components/` - 재사용 가능한 컴포넌트

- `index.html` - 진입점

- `tailwind.config.js` - 스타일 설정

**사용 기술**:

```typescript
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'

export default function Dashboard() {
  const [count, setCount] = useState(0)

  return (
    <div className="p-8">
      <Card>
        <h1>Dashboard</h1>
        <Button onClick={() => setCount(count + 1)}>
          Count: {count}
        </Button>
      </Card>
    </div>
  )
}
```text

#### 3단계: 번들링

**스크립트**: `bundle-artifact.sh`

```bash
bash scripts/bundle-artifact.sh
```

**결과**: `bundle.html` (자체 완결형 파일)

- 모든 JavaScript 인라인

- 모든 CSS 인라인

- 외부 의존성 없음

- 바로 사용 가능

#### 4단계: 배포

```html
<!-- bundle.html 파일을 :

1. 브라우저에서 열기
2. Claude 아티팩트로 공유
3. 웹 서버에 업로드
4. 이메일로 전송
-->
```text

---

## 📊 Output (생산물)

### 완성된 웹 아티팩트

```text
bundle.html (단일 파일, 완전 자체 포함)

특징:

- React 18 앱 (완전 기능)

- 상태 관리 (useState, useContext 등)

- 라우팅 (React Router)

- UI 컴포넌트 (40+ shadcn/ui)

- Tailwind 스타일링

- 다운로드 가능

- 오프라인에서도 작동

```

**크기**: 일반적으로 200-500KB (gzip)

---

## 💡 실제 사용 예시

### 예시 1: 대시보드 앱

#### 요청 (판매)

> "판매 데이터 대시보드 웹앱을 만들어줄 수 있어?
> 차트, 필터, 테이블 포함."

#### 결과 (판매)

```text
Dashboard.tsx:

- 월별 판매 차트 (recharts)

- 필터 옵션 (상태 관리)

- 판매 데이터 테이블

- 반응형 레이아웃

스타일: Tailwind CSS
컴포넌트: shadcn/ui (Button, Card, Input, Table)

배포: bundle.html (500KB)
```

### 예시 2: 작업 관리 도구

#### 요청 (할일)

> "ToDo 앱을 만들어줄 수 있어?
> 추가, 완료, 삭제, 필터링 기능으로."

#### 결과 (ToDo)

```text
TodoApp.tsx:

- 새 할일 입력 폼

- 할일 목록 (상태별 필터)

- 완료/삭제 버튼

- 로컬 스토리지 저장

스타일: Tailwind + 커스텀 애니메이션
상태: useState로 관리

배포: bundle.html (250KB)
```

### 예시 3: 복잡한 SPA

#### 요청 (여행)

> "여행 플래너 앱. 여행 만들기, 일정 추가, 맵 통합?"

#### 결과 (여행)

```text
TravelPlanner.tsx:

- 홈페이지 및 여행 목록

- 여행 생성 마법사

- 일정 세부사항 (React Router)

- 상태 관리 (Context API)

- 로컬 스토리지 저장

UI: 10+ shadcn/ui 컴포넌트
스타일: Tailwind (400+ 클래스)
번들: bundle.html (400KB)
```

---

## 🎯 특징

| 특징 | 설명 |
| --- | --- |

| **React 18** | 최신 버전, Hook 지원 |
| **TypeScript** | 타입 안전성 |
| **Vite** | 빠른 개발 서버 |
| **Tailwind CSS** | 유틸리티 기반 스타일링 |
| **shadcn/ui** | 40+ 프로덕션급 컴포넌트 |
| **상태 관리** | useState, useContext, useReducer |
| **라우팅** | React Router 지원 |
| **번들링** | Parcel로 단일 HTML 파일 |
| **자체 완결** | 외부 의존성 없음 |
| **반응형** | 모든 화면 크기 지원 |

---

## 🚀 시작하기

### 사용자 입장 (Claude 사용할 때)

```text
"[설명]을 웹앱으로 만들어줄 수 있어?
[요구 기능들]을 포함해서."
```text

예시들:
```text
"대시보드를 만들어줄 수 있어? 차트와 필터링 포함."

"메모 앱. 추가, 편집, 삭제 기능으로."

"날씨 앱. 도시 검색, 현재/예보 표시."
```

### 기대할 수 있는 것

1. **완전 기능**: 프로덕션급 앱
2. **아름다운 UI**: Tailwind + shadcn/ui
3. **반응형**: 모든 기기에서 작동
4. **번들링됨**: 단일 HTML 파일
5. **즉시 배포**: 다운로드 후 바로 사용

---

## 🛠️ 기술 스택

**프론트엔드**:

- React 18

- TypeScript

- Tailwind CSS 3.4.1

- shadcn/ui (40+ 컴포넌트)

**상태 관리**:

- useState

- useContext

- useReducer

- (Redux, Zustand 커스텀 추가 가능)

**라우팅**:

- React Router v6

- Client-side 네비게이션

**개발 도구**:

- Vite (개발 서버)

- Parcel (번들링)

- TypeScript (컴파일)

---

## 📚 스킬의 핵심 철학

> **"높은 수준의 웹 앱을 간단히"**

- 복잡하지만 사용하기 쉬운 스택

- 프로덕션급 컴포넌트 기본 제공

- 번들화로 배포 단순화

- 개발자 경험 우선

---

## ❓ FAQ

**Q: 정말 복잡한 앱도 가능한가요?**

A: 네! React Router로 다중 페이지, Context로 전역 상태 관리 등 모두 가능.

**Q: shadcn/ui 외 다른 라이브러리?**

A: 기본은 shadcn/ui이지만, 요청하면 recharts, date-picker 등 추가 가능.

**Q: 백엔드 API는?**

A: fetch/axios로 API 호출 가능. CORS 환경에서 작동.

**Q: 파일 크기는?**

A: 일반적으로 200-500KB (gzip). 최적화로 더 작게 가능.

**Q: 수정은 가능한가요?**

A: 네! "버튼 색 바꿔줄래?" 하면 즉시 수정.

---

## 📖 더 알고 싶으면

- **SKILL.md**: Web Artifacts Builder 완전 가이드

- **init-artifact.sh**: 프로젝트 초기화 스크립트

- **bundle-artifact.sh**: 번들링 스크립트

- **shadcn/ui docs**: <https://ui.shadcn.com>

---

**이 스킬의 목표**: 현대적인 웹 기술로 프로덕션급 앱을 빠르게 만들고 배포하는 것입니다. 🚀✨
