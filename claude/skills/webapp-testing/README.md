# WebApp Testing Skill

**Playwright로 웹앱 테스트** - React 앱의 버튼 클릭부터 복잡한 워크플로우까지 자동화합니다.

---

## 🎯 이 스킬이 뭔가요?

로컬 웹앱을 **자동으로 테스트**합니다. Playwright를 사용해 브라우저를 제어하고, 버튼을 클릭하고, 폼을 채우고, 결과를 검증합니다.

마치 테스트 엔지니어처럼, 수동 테스트를 자동화합니다.

---

## 🔄 어떻게 작동하나요?

### 3단계 프로세스

```text
1. 서버 시작 → 2. 페이지 탐색 → 3. 자동화 및 검증
```text

#### 1단계: 서버 시작

**도구**: `with_server.py` (서버 라이프사이클 관리)

```bash
# 단일 서버
python scripts/with_server.py --server "npm run dev" --port 5173 -- python test.py

# 다중 서버 (백엔드 + 프론트엔드)
python scripts/with_server.py \
  --server "python server.py" --port 3000 \
  --server "npm run dev" --port 5173 \
  -- python test.py

```

**결과**: 테스트 시작 전 서버 자동 구성

#### 2단계: 페이지 탐색

```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    page.goto('http://localhost:5173')

    # 페이지 로드 대기
    page.wait_for_load_state('networkidle')

    # DOM 검사, 스크린샷 등
    content = page.content()
    page.screenshot(path='/tmp/page.png')
```text

#### 3단계: 자동화 및 검증

```python
# 요소 찾기
buttons = page.locator('button').all()

# 상호작용
page.click('text=Submit')
page.fill('input[name="email"]', 'test@example.com')

# 검증
assert page.is_visible('text=Success!')
```

---

## 📊 Output (생산물)

### 테스트 결과

```text
┌────────────────────────────────┐
│  Test Results                  │
│                                │
│  ✅ Button click works         │
│  ✅ Form submission success    │
│  ✅ Data appears on page       │
│  ✅ Navigation works           │
│                                │
│  Screenshots & Logs:           │
│  - page-1.png (스크린샷)       │

│  - console.log (브라우저 로그)  │

└────────────────────────────────┘
```text

**포함**:

- 테스트 통과/실패 여부

- 스크린샷

- 브라우저 콘솔 로그

- 타이밍 정보

---

## 💡 실제 사용 예시

### 예시 1: 버튼 클릭 테스트

#### 요청

> "React 앱의 '제출' 버튼을 클릭해서 작동하는지 확인해줄 수 있어?"

#### 자동 테스트

```python
# 서버 시작 (자동)
# 페이지 접근
page.goto('http://localhost:5173')
page.wait_for_load_state('networkidle')

# 버튼 찾기 및 클릭
page.click('text=Submit')

# 결과 확인
assert page.is_visible('text=Success!')
page.screenshot(path='/tmp/success.png')

결과: ✅ 제출 성공
```

### 예시 2: 폼 작성 테스트

#### 요청

> "로그인 폼을 자동으로 채우고 제출해서 작동하는지 확인?"

#### 자동 테스트

```python
page.goto('http://localhost:5173/login')
page.wait_for_load_state('networkidle')

# 폼 입력
page.fill('input[name="email"]', 'user@example.com')
page.fill('input[name="password"]', 'password123')

# 제출
page.click('button[type="submit"]')
page.wait_for_load_state('networkidle')

# 검증: 로그인 성공 확인
assert page.is_visible('text=Welcome!')
```text

### 예시 3: 복잡한 워크플로우

#### 요청

> "전체 구매 흐름(상품 추가 → 체크아웃 → 결제)을 테스트해줄 수 있어?"

#### 자동 테스트

```python
# 상품 페이지 방문
page.goto('http://localhost:5173/products')

# 상품 추가
page.click('button:has-text("Add to Cart")')
assert page.is_visible('text=Added to cart')

# 장바구니 이동
page.click('text=Cart')
assert page.is_visible('text=Item 1')

# 체크아웃
page.click('text=Checkout')

# 배송 정보 입력
page.fill('input[name="address"]', '123 Main St')

# 결제
page.click('text=Pay Now')
page.wait_for_load_state('networkidle')

# 주문 확인
assert page.is_visible('text=Order Confirmed')
page.screenshot(path='/tmp/order_success.png')
```

---

## 🎯 특징

| 특징 | 설명 |
| --- | --- |

| **자동 서버 관리** | with_server.py로 시작/종료 자동화 |
| **Playwright** | 크롬/파이어폭스/사파리 지원 |
| **요소 선택** | CSS, XPath, text, role 등 |
| **상호작용** | 클릭, 입력, 제출, 스크롤 |
| **대기 전략** | networkidle, selector, timeout 등 |
| **스크린샷** | 각 단계마다 스크린샷 캡처 |
| **콘솔 로그** | 브라우저 콘솔 메시지 수집 |
| **비헤드리스** | 백그라운드 또는 헤드리스 모드 |

---

## 🚀 시작하기

### 사용자 입장 (Claude 사용할 때)

```text
"React 앱의 [기능]을 테스트해줄 수 있어?
[예상 결과]를 확인해야 해."
```text

예시들:
```text
"로그인 폼이 작동하는지 확인해줄 수 있어?"

"상품 추가 버튼이 장바구니에 추가하는지 테스트."

"전체 체크아웃 흐름이 성공하는지 자동 테스트."
```

### 기대할 수 있는 것

1. **자동 시작**: 서버 자동 시작
2. **자동 테스트**: 기능 자동 검증
3. **스크린샷**: 각 단계 시각 기록
4. **에러 추적**: 문제 있는 부분 식별
5. **완전 자동화**: 반복 실행 가능

---

## 🛠️ 기술 스택

**테스트 프레임워크**:

- Playwright (동기 및 비동기)

- Python sync API

**서버 관리**:

- with_server.py (구성 자동화)

- 다중 서버 지원

**어설션**:

- assert (표준 Python)

- Playwright 메서드 (is_visible, is_enabled 등)

---

## 📚 스킬의 핵심 철학

> **"사용자처럼 테스트한다"**

- 실제 브라우저에서 테스트

- 클릭, 입력 같은 실제 사용자 행동

- 최종 결과 검증 (렌더링된 UI)

- 반복 가능하고 신뢰할 수 있는 테스트

---

## ❓ FAQ

**Q: 정말 복잡한 앱도 테스트 가능한가요?**

A: 네! 다중 페이지, 복잡한 상호작용, API 호출도 가능.

**Q: 서버를 수동으로 시작해야 하나요?**

A: 아니요! with_server.py가 자동 관리합니다.

**Q: 요소를 어떻게 찾나요?**

A: CSS 선택자, XPath, text 매칭, role 속성 등 다양한 방법.

**Q: 요소가 안 보일 때는?**

A: page.wait_for_selector()로 대기하거나 스크린샷으로 진단.

**Q: 테스트 결과를 저장할 수 있나요?**

A: 네! 스크린샷, 콘솔 로그 등 모두 저장 가능.

---

## 📖 더 알고 싶으면

- **SKILL.md**: Playwright 완전 가이드

- **examples/**: 다양한 테스트 예시

- **element_discovery.py**: 요소 찾기 방법

---

**이 스킬의 목표**: 웹앱의 자동화된 테스트로 버그를 미리 찾고 기능을 보장하는 것입니다. ✅✨
