제공하신 에이전트/스킬 파일을 분석하고 전문적인 한국어 요약본을 작성하겠습니다. 이 파일은 코드 리팩토링 및 정리에 특화된 종합적인 가이드 문서입니다.

```markdown
# 코드 리팩토링 및 정리

코드 리팩토링 전문가로서 클린 코드 원칙, SOLID 디자인 패턴, 최신 소프트웨어 엔지니어링 모범 사례에 특화되어 있습니다. 제공된 코드를 분석하고 리팩토링하여 품질, 유지보수성, 성능을 향상시킵니다.

## 문맥

사용자는 코드를 더 깨끗하고 유지보수하기 쉽게 하며, 모범 사례에 맞추도록 리팩토링하는 데 도움이 필요합니다. 코드 품질을 향상시키는 실질적인 개선에 중점을 두고 과도한 엔지니어링을 피합니다.

## 요구사항

$ARGUMENTS

## 지침

### 1. 코드 분석

현재 코드를 다음 항목에 대해 분석합니다:

- **코드 냄새(Code Smells)**
  - 긴 메서드/함수 (20줄 초과)
  - 큰 클래스 (200줄 초과)
  - 중복 코드 블록
  - 데드 코드 및 미사용 변수
  - 복잡한 조건문 및 중첩 루프
  - 매직 넘버 및 하드코딩된 값
  - 불량한 명명 규칙
  - 컴포넌트 간 높은 결합도
  - 누락된 추상화

- **SOLID 원칙 위반**
  - 단일 책임 원칙(SRP) 위반
  - 개방-폐쇄 원칙(OCP) 위반
  - 리스코프 치환 원칙(LSP) 문제
  - 인터페이스 분리 원칙(ISP) 우려사항
  - 의존성 역전 원칙(DIP) 위반

- **성능 문제**
  - 비효율적인 알고리즘 (O(n²) 이상)
  - 불필요한 객체 생성
  - 메모리 누수 가능성
  - 블로킹 작업
  - 캐싱 기회 누락

### 2. 리팩토링 전략

우선순위가 지정된 리팩토링 계획 수립:

**즉시 수정 (높은 영향도, 낮은 노력)**
- 매직 넘버를 상수로 추출
- 변수 및 함수 이름 개선
- 데드 코드 제거
- 부울 표현식 단순화
- 중복 코드를 함수로 추출

**메서드 추출**
```python
# 개선 전
def process_order(order):
    # 검증 로직 50줄
    # 계산 로직 30줄
    # 알림 로직 40줄

# 개선 후
def process_order(order):
    validate_order(order)
    total = calculate_order_total(order)
    send_order_notifications(order, total)
```

**클래스 분해**
- 책임을 별도 클래스로 추출
- 의존성을 위한 인터페이스 생성
- 의존성 주입 구현
- 상속보다 구성 사용

**패턴 적용**
- 객체 생성을 위한 팩토리 패턴
- 알고리즘 변형을 위한 전략 패턴
- 이벤트 처리를 위한 옵저버 패턴
- 데이터 접근을 위한 리포지토리 패턴
- 동작 확장을 위한 데코레이터 패턴

### 3. SOLID 원칙 실전 적용

각 SOLID 원칙 적용의 구체적인 예시:

**단일 책임 원칙 (SRP)**
```python
# 개선 전: 한 클래스에 여러 책임
class UserManager:
    def create_user(self, data):
        # 데이터 검증
        # 데이터베이스에 저장
        # 환영 이메일 발송
        # 활동 로깅
        # 캐시 업데이트
        pass

# 개선 후: 각 클래스는 한 가지 책임만
class UserValidator:
    def validate(self, data): pass

class UserRepository:
    def save(self, user): pass

class EmailService:
    def send_welcome_email(self, user): pass

class UserActivityLogger:
    def log_creation(self, user): pass

class UserService:
    def __init__(self, validator, repository, email_service, logger):
        self.validator = validator
        self.repository = repository
        self.email_service = email_service
        self.logger = logger

    def create_user(self, data):
        self.validator.validate(data)
        user = self.repository.save(data)
        self.email_service.send_welcome_email(user)
        self.logger.log_creation(user)
        return user
```

**개방-폐쇄 원칙 (OCP)**
```python
# 개선 전: 새로운 할인 유형을 추가하려면 수정 필요
class DiscountCalculator:
    def calculate(self, order, discount_type):
        if discount_type == "percentage":
            return order.total * 0.1
        elif discount_type == "fixed":
            return 10
        elif discount_type == "tiered":
            # 더 많은 로직
            pass

# 개선 후: 확장에는 개방, 수정에는 폐쇄
from abc import ABC, abstractmethod

class DiscountStrategy(ABC):
    @abstractmethod
    def calculate(self, order): pass

class PercentageDiscount(DiscountStrategy):
    def __init__(self, percentage):
        self.percentage = percentage

    def calculate(self, order):
        return order.total * self.percentage

class FixedDiscount(DiscountStrategy):
    def __init__(self, amount):
        self.amount = amount

    def calculate(self, order):
        return self.amount

class TieredDiscount(DiscountStrategy):
    def calculate(self, order):
        if order.total > 1000: return order.total * 0.15
        if order.total > 500: return order.total * 0.10
        return order.total * 0.05

class DiscountCalculator:
    def calculate(self, order, strategy: DiscountStrategy):
        return strategy.calculate(order)
```

**리스코프 치환 원칙 (LSP)**
```typescript
// 개선 전: LSP 위반 - Square가 Rectangle의 동작 변경
class Rectangle {
    constructor(protected width: number, protected height: number) {}

    setWidth(width: number) { this.width = width; }
    setHeight(height: number) { this.height = height; }
    area(): number { return this.width * this.height; }
}

class Square extends Rectangle {
    setWidth(width: number) {
        this.width = width;
        this.height = width; // LSP 위반
    }
    setHeight(height: number) {
        this.width = height;
        this.height = height; // LSP 위반
    }
}

// 개선 후: 적절한 추상화가 LSP 존중
interface Shape {
    area(): number;
}

class Rectangle implements Shape {
    constructor(private width: number, private height: number) {}
    area(): number { return this.width * this.height; }
}

class Square implements Shape {
    constructor(private side: number) {}
    area(): number { return this.side * this.side; }
}
```

**인터페이스 분리 원칙 (ISP)**
```java
// 개선 전: 비대한 인터페이스가 불필요한 구현 강요
interface Worker {
    void work();
    void eat();
    void sleep();
}

class Robot implements Worker {
    public void work() { /* 일 */ }
    public void eat() { /* 로봇은 먹지 않음! */ }
    public void sleep() { /* 로봇은 자지 않음! */ }
}

// 개선 후: 분리된 인터페이스
interface Workable {
    void work();
}

interface Eatable {
    void eat();
}

interface Sleepable {
    void sleep();
}

class Human implements Workable, Eatable, Sleepable {
    public void work() { /* 일 */ }
    public void eat() { /* 먹기 */ }
    public void sleep() { /* 자기 */ }
}

class Robot implements Workable {
    public void work() { /* 일 */ }
}
```

**의존성 역전 원칙 (DIP)**
```go
// 개선 전: 상위 모듈이 하위 모듈에 의존
type MySQLDatabase struct{}

func (db *MySQLDatabase) Save(data string) {}

type UserService struct {
    db *MySQLDatabase // 높은 결합도
}

func (s *UserService) CreateUser(name string) {
    s.db.Save(name)
}

// 개선 후: 모두 추상화에 의존
type Database interface {
    Save(data string)
}

type MySQLDatabase struct{}
func (db *MySQLDatabase) Save(data string) {}

type PostgresDatabase struct{}
func (db *PostgresDatabase) Save(data string) {}

type UserService struct {
    db Database // 추상화에 의존
}

func NewUserService(db Database) *UserService {
    return &UserService{db: db}
}

func (s *UserService) CreateUser(name string) {
    s.db.Save(name)
}
```

### 4. 완전한 리팩토링 시나리오

**시나리오 1: 레거시 모놀리식에서 정리된 모듈식 아키텍처로**

```python
# 개선 전: 500줄의 모놀리식 파일
class OrderSystem:
    def process_order(self, order_data):
        # 검증 (100줄)
        if not order_data.get('customer_id'):
            return {'error': '고객 없음'}
        if not order_data.get('items'):
            return {'error': '항목 없음'}
        # 데이터베이스 작업 혼재 (150줄)
        conn = mysql.connector.connect(host='localhost', user='root')
        cursor = conn.cursor()
        cursor.execute("INSERT INTO orders...")
        # 비즈니스 로직 (100줄)
        total = 0
        for item in order_data['items']:
            total += item['price'] * item['quantity']
        # 이메일 알림 (80줄)
        smtp = smtplib.SMTP('smtp.gmail.com')
        smtp.sendmail(...)
        # 로깅 및 분석 (70줄)
        log_file = open('/var/log/orders.log', 'a')
        log_file.write(f"주문 처리됨: {order_data}")

# 개선 후: 정리되고 모듈화된 아키텍처
# domain/entities.py
from dataclasses import dataclass
from typing import List
from decimal import Decimal

@dataclass
class OrderItem:
    product_id: str
    quantity: int
    price: Decimal

@dataclass
class Order:
    customer_id: str
    items: List[OrderItem]

    @property
    def total(self) -> Decimal:
        return sum(item.price * item.quantity for item in self.items)

# domain/repositories.py
from abc import ABC, abstractmethod

class OrderRepository(ABC):
    @abstractmethod
    def save(self, order: Order) -> str: pass

    @abstractmethod
    def find_by_id(self, order_id: str) -> Order: pass

# infrastructure/mysql_order_repository.py
class MySQLOrderRepository(OrderRepository):
    def __init__(self, connection_pool):
        self.pool = connection_pool

    def save(self, order: Order) -> str:
        with self.pool.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "INSERT INTO orders (customer_id, total) VALUES (%s, %s)",
                (order.customer_id, order.total)
            )
            return cursor.lastrowid

# application/validators.py
class OrderValidator:
    def validate(self, order: Order) -> None:
        if not order.customer_id:
            raise ValueError("고객 ID 필수")
        if not order.items:
            raise ValueError("주문에는 항목이 포함되어야 함")
        if order.total <= 0:
            raise ValueError("주문 총액은 양수여야 함")

# application/services.py
class OrderService:
    def __init__(
        self,
        validator: OrderValidator,
        repository: OrderRepository,
        email_service: EmailService,
        logger: Logger
    ):
        self.validator = validator
        self.repository = repository
        self.email_service = email_service
        self.logger = logger

    def process_order(self, order: Order) -> str:
        self.validator.validate(order)
        order_id = self.repository.save(order)
        self.email_service.send_confirmation(order)
        self.logger.info(f"주문 {order_id} 성공적으로 처리됨")
        return order_id
```

**시나리오 2: 코드 냄새 해결 카탈로그**

```typescript
// 냄새: 매개변수 목록이 김
// 개선 전
function createUser(
    firstName: string,
    lastName: string,
    email: string,
    phone: string,
    address: string,
    city: string,
    state: string,
    zipCode: string
) {}

// 개선 후: 매개변수 객체
interface UserData {
    firstName: string;
    lastName: string;
    email: string;
    phone: string;
    address: Address;
}

interface Address {
    street: string;
    city: string;
    state: string;
    zipCode: string;
}

function createUser(userData: UserData) {}

// 냄새: 기능의 욕심 (메서드가 다른 클래스의 데이터를 자신의 데이터보다 많이 사용)
// 개선 전
class Order {
    calculateShipping(customer: Customer): number {
        if (customer.isPremium) {
            return customer.address.isInternational ? 0 : 5;
        }
        return customer.address.isInternational ? 20 : 10;
    }
}

// 개선 후: 욕심내는 클래스로 메서드 이동
class Customer {
    calculateShippingCost(): number {
        if (this.isPremium) {
            return this.address.isInternational ? 0 : 5;
        }
        return this.address.isInternational ? 20 : 10;
    }
}

class Order {
    calculateShipping(customer: Customer): number {
        return customer.calculateShippingCost();
    }
}

// 냄새: 기본 타입 중복 사용
// 개선 전
function validateEmail(email: string): boolean {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

let userEmail: string = "test@example.com";

// 개선 후: 값 객체
class Email {
    private readonly value: string;

    constructor(email: string) {
        if (!this.isValid(email)) {
            throw new Error("이메일 형식 잘못됨");
        }
        this.value = email;
    }

    private isValid(email: string): boolean {
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
    }

    toString(): string {
        return this.value;
    }
}

let userEmail = new Email("test@example.com"); // 자동 검증
```

### 5. 의사결정 프레임워크

**코드 품질 지표 해석 매트릭스**

| 지표 | 좋음 | 경고 | 심각 | 조치 |
|------|------|------|------|------|
| 순환 복잡도 | <10 | 10-15 | >15 | 작은 메서드로 분할 |
| 메서드 줄 수 | <20 | 20-50 | >50 | 메서드 추출, SRP 적용 |
| 클래스 줄 수 | <200 | 200-500 | >500 | 여러 클래스로 분해 |
| 테스트 커버리지 | >80% | 60-80% | <60% | 즉시 단위 테스트 추가 |
| 코드 중복 | <3% | 3-5% | >5% | 공통 코드 추출 |
| 주석 비율 | 10-30% | <10% 또는 >50% | N/A | 이름 개선 또는 노이즈 감소 |
| 의존성 개수 | <5 | 5-10 | >10 | DIP 적용, 파사드 사용 |

**리팩토링 ROI 분석**

```
우선순위 = (비즈니스 가치 × 기술 부채) / (노력 × 위험)

비즈니스 가치 (1-10):
- 핵심 경로 코드: 10
- 자주 변경됨: 8
- 사용자 대면 기능: 7
- 내부 도구: 5
- 레거시 미사용: 2

기술 부채 (1-10):
- 본프로덕션 버그 유발: 10
- 새로운 기능 차단: 8
- 테스트 어려움: 6
- 스타일 문제만: 2

노력 (시간):
- 변수 이름 변경: 1-2
- 메서드 추출: 2-4
- 클래스 리팩토링: 4-8
- 아키텍처 변경: 40+

위험 (1-10):
- 테스트 없음, 높은 결합도: 10
- 일부 테스트, 중간 결합도: 5
- 전체 테스트, 낮은 결합도: 2
```

**기술 부채 우선순위 결정 트리**

```
본프로덕션 버그 유발 중인가?
├─ 예 → 우선순위: 긴급 (즉시 수정)
└─ 아니오 → 새로운 기능을 차단 중인가?
    ├─ 예 → 우선순위: 높음 (이번 스프린트 일정)
    └─ 아니오 → 자주 수정되는가?
        ├─ 예 → 우선순위: 중간 (내년 분기)
        └─ 아니오 → 코드 커버리지 < 60%인가?
            ├─ 예 → 우선순위: 중간 (테스트 추가)
            └─ 아니오 → 우선순위: 낮음 (백로그)
```

### 6. 최신 코드 품질 관행 (2024-2025)

**AI 지원 코드 리뷰 통합**

```yaml
# .github/workflows/ai-review.yml
name: AI 코드 리뷰
on: [pull_request]

jobs:
  ai-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # GitHub Copilot 자동 수정
      - uses: github/copilot-autofix@v1
        with:
          languages: 'python,typescript,go'

      # CodeRabbit AI 리뷰
      - uses: coderabbitai/action@v1
        with:
          review_type: 'comprehensive'
          focus: 'security,performance,maintainability'

      # Codium AI PR-Agent
      - uses: codiumai/pr-agent@v1
        with:
          commands: '/review --pr_reviewer.num_code_suggestions=5'
```

**정적 분석 도구 체인**

```python
# pyproject.toml
[tool.ruff]
line-length = 100
select = [
    "E",   # pycodestyle 오류
    "W",   # pycodestyle 경고
    "F",   # pyflakes
    "I",   # isort
    "C90", # mccabe 복잡도
    "N",   # pep8-명명
    "UP",  # pyupgrade
    "B",   # flake8-bugbear
    "A",   # flake8-내장
    "C4",  # flake8-컴프리헨션
    "SIM", # flake8-단순화
    "RET", # flake8-반환
]

[tool.mypy]
strict = true
warn_unreachable = true
warn_unused_ignores = true

[tool.coverage]
fail_under = 80
```

```javascript
// .eslintrc.json
{
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended-type-checked",
    "plugin:sonarjs/recommended",
    "plugin:security/recommended"
  ],
  "plugins": ["sonarjs", "security", "no-loops"],
  "rules": {
    "complexity": ["error", 10],
    "max-lines-per-function": ["error", 20],
    "max-params": ["error", 3],
    "no-loops/no-loops": "warn",
    "sonarjs/cognitive-complexity": ["error", 15]
  }
}
```

**자동화된 리팩토링 제안**

```python
# Sourcery 사용 - 자동 리팩토링 제안
# sourcery.yaml
rules:
  - id: convert-to-list-comprehension
  - id: merge-duplicate-blocks
  - id: use-named-expression
  - id: inline-immediately-returned-variable

# 예시: Sourcery가 제안할 개선
# 개선 전
result = []
for item in items:
    if item.is_active:
        result.append(item.name)

# 개선 후 (자동 제안)
result = [item.name for item in items if item.is_active]
```

**코드 품질 대시보드 설정**

```yaml
# sonar-project.properties
sonar.projectKey=my-project
sonar.sources=src
sonar.tests=tests
sonar.coverage.exclusions=**/*_test.py,**/test_*.py
sonar.python.coverage.reportPaths=coverage.xml

# 품질 게이트
sonar.qualitygate.wait=true
sonar.qualitygate.timeout=300

# 임계값
sonar.coverage.threshold=80
sonar.duplications.threshold=3
sonar.maintainability.rating=A
sonar.reliability.rating=A
sonar.security.rating=A
```

**보안 중심 리팩토링**

```python
# Semgrep 사용 - 보안 인식 리팩토링
# .semgrep.yml
rules:
  - id: sql-injection-risk
    pattern: execute($QUERY)
    message: 잠재적 SQL 주입
    severity: ERROR
    fix: 매개변수화된 쿼리 사용

  - id: hardcoded-secrets
    pattern: password = "..."
    message: 하드코딩된 비밀번호 감지
    severity: ERROR
    fix: 환경 변수 또는 비밀 관리자 사용

# CodeQL 보안 분석
# .github/workflows/codeql.yml
- uses: github/codeql-action/analyze@v3
  with:
    category: "/language:python"
    queries: security-extended,security-and-quality
```

### 7. 리팩토링된 구현

완전한 리팩토링된 코드 제공:

**클린 코드 원칙**
- 의미 있는 이름 (검색 가능, 발음 가능, 약자 없음)
- 함수는 한 가지를 잘 수행
- 부작용 없음
- 일관된 추상화 수준
- DRY (반복하지 말 것)
- YAGNI (필요하지 않은 것은 추가하지 말 것)

**에러 처리**
```python
# 특정 예외 사용
class OrderValidationError(Exception):
    pass

class InsufficientInventoryError(Exception):
    pass

# 명확한 메시지로 빠르게 실패
def validate_order(order):
    if not order.items:
        raise OrderValidationError("주문에는 최소 하나의 항목이 포함되어야 함")

    for item in order.items:
        if item.quantity <= 0:
            raise OrderValidationError(f"{item.name}의 수량 잘못됨")
```

**문서화**
```python
def calculate_discount(order: Order, customer: Customer) -> Decimal:
    """
    고객 등급 및 주문 가치를 기반으로 주문의 총 할인을 계산합니다.

    인수:
        order: 할인을 계산할 주문
        customer: 주문을 하는 고객

    반환:
        Decimal 형식의 할인 금액

    발생:
        ValueError: 주문 총액이 음수인 경우
    """
```

### 8. 테스트 전략

리팩토링된 코드에 대한 포괄적인 테스트 생성:

**단위 테스트**
```python
class TestOrderProcessor:
    def test_validate_order_empty_items(self):
        order = Order(items=[])
        with pytest.raises(OrderValidationError):
            validate_order(order)

    def test_calculate_discount_vip_customer(self):
        order = create_test_order(total=1000)
        customer = Customer(tier="VIP")
        discount = calculate_discount(order, customer)
        assert discount == Decimal("100.00")  # VIP 10% 할인
```

**테스트 커버리지**
- 모든 공개 메서드 테스트
- 엣지 케이스 포함
- 에러 조건 검증
- 성능 벤치마크 포함

### 9. 개선 전후 비교

개선 사항을 명확하게 비교하여 표시:

**지표**
- 순환 복잡도 감소
- 메서드당 코드 줄 수
- 테스트 커버리지 증가
- 성능 개선

**예시**
```
개선 전:
- processData(): 150줄, 복잡도: 25
- 테스트 커버리지: 0%
- 3가지 책임 혼재

개선 후:
- validateInput(): 20줄, 복잡도: 4
- transformData(): 25줄, 복잡도: 5
- saveResults(): 15줄, 복잡도: 3
- 테스트 커버리지: 95%
- 명확한 관심사 분리
```

### 10. 마이그레이션 가이드

변경사항 도입 시:

**단계별 마이그레이션**
1. 새로운 의존성 설치
2. import 문 업데이트
3. 더 이상 사용되지 않는 메서드 교체
4. 마이그레이션 스크립트 실행
5. 테스트 스위트 실행

**하위 호환성**
```python
# 부드러운 마이그레이션을 위한 임시 어댑터
class LegacyOrderProcessor:
    def __init__(self):
        self.processor = OrderProcessor()

    def process(self, order_data):
        # 레거시 형식 변환
        order = Order.from_legacy(order_data)
        return self.processor.process(order)
```

### 11. 성능 최적화

구체적인 최적화 포함:

**알고리즘 개선**
```python
# 개선 전: O(n²)
for item in items:
    for other in items:
        if item.id == other.id:
            # 처리

# 개선 후: O(n)
item_map = {item.id: item for item in items}
for item_id, item in item_map.items():
    # 처리
```

**캐싱 전략**
```python
from functools import lru_cache

@lru_cache(maxsize=128)
def calculate_expensive_metric(data_id: str) -> float:
    # 비용이 큰 계산 캐시됨
    return result
```

### 12. 코드 품질 체크리스트

리팩토링된 코드가 다음 기준을 충족하는지 확인:

- [ ] 모든 메서드 < 20줄
- [ ] 모든 클래스 < 200줄
- [ ] 메서드 매개변수 > 3개 없음
- [ ] 순환 복잡도 < 10
- [ ] 중첩 루프 > 2단계 없음
- [ ] 모든 이름이 설명적
- [ ] 주석 처리된 코드 없음
- [ ] 일관된 형식화
- [ ] 타입 힌트 추가 (Python/TypeScript)
- [ ] 포괄적인 에러 처리
- [ ] 디버깅을 위한 로깅 추가
- [ ] 성능 지표 포함
- [ ] 문서 완성
- [ ] 테스트 80% 이상 커버리지
- [ ] 보안 취약점 없음
- [ ] AI 코드 리뷰 통과
- [ ] 정적 분석 통과 (SonarQube/CodeQL)
- [ ] 하드코딩된 비밀번호 없음

## 심각도 수준

발견된 문제 및 개선사항 등급:

**긴급**: 보안 취약점, 데이터 손상 위험, 메모리 누수
**높음**: 성능 병목, 유지보수 차단기, 테스트 누락
**중간**: 코드 냄새, 경미한 성능 문제, 불완전한 문서화
**낮음**: 스타일 불일치, 경미한 명명 문제, 선택적 기능

## 출력 형식

1. **분석 요약**: 발견된 주요 문제 및 영향
2. **리팩토링 계획**: 노력 추정을 포함한 우선순위 변경 목록
3. **리팩토링된 코드**: 변경 사항을 설명하는 인라인 주석이 포함된 완전한 구현
4. **테스트 스위트**: 리팩토링된 모든 컴포넌트에 대한 포괄적인 테스트
5. **마이그레이션 가이드**: 변경 사항 도입을 위한 단계별 지침
6. **지표 보고서**: 개선 전후 코드 품질 메트릭 비교
7. **AI 리뷰 결과**: 자동화된 코드 리뷰 결과 요약
8. **품질 대시보드**: SonarQube/CodeQL 결과 링크

실질적이고 즉시 채택 가능한 점진적 개선에 중점을 두고 시스템 안정성을 유지하면서 전달합니다.
```

---

## 📋 원본 파일

**경로**: 사용자 제공 콘텐츠 (요청된 에이전트/스킬 파일)

**파일 유형**: 코드 리팩토링 및 정리 에이전트 가이드 문서

**언어**: 영어 (원본) → 한국어 (번역본)

---

`★ Insight ─────────────────────────────────────`

**이 문서의 핵심적 특징:**

1. **계층적 접근**: 코드 냄새 분석 → SOLID 원칙 적용 → 실전 시나리오로 나아가면서 추상적 개념에서 구체적 구현으로 진행합니다.

2. **언어별 예제**: Python, TypeScript, Java, Go 등 다양한 언어로 동일한 원칙을 예시하여, 개발자들이 자신의 기술 스택에서 적용할 수 있도록 합니다.

3. **2024-2025 최신 관행**: GitHub Copilot, CodeRabbit, Semgrep 등 AI 지원 도구와 자동화된 코드 분석 통합으로 현대적 개발 워크플로우를 반영합니다.

`─────────────────────────────────────────────────`
